import Foundation
import ClerkKit

// MARK: - HTTP Method

private enum HTTPMethod: String {
    case get    = "GET"
    case post   = "POST"
    case put    = "PUT"
    case patch  = "PATCH"
    case delete = "DELETE"
}

// MARK: - APIClient

/// Single actor that owns URLSession, auth-token injection, and retry logic.
/// All API calls go through here — never construct URLRequest elsewhere.
actor APIClient {
    static let shared = APIClient()

    private let urlSession: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    /// Cached at init to avoid @MainActor hop on every request.
    private let baseURL: URL

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 15
        config.timeoutIntervalForResource = 30
        urlSession = URLSession(configuration: config)

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        // Bundle.main.infoDictionary is safe to read from any context.
        // url.host check guards against "http:" produced when xcconfig strips
        // "//localhost:8080" as a comment (URL parses but has no hostname).
        if let raw = Bundle.main.infoDictionary?["API_BASE_URL"] as? String,
           !raw.isEmpty,
           let url = URL(string: raw),
           url.host?.isEmpty == false {
            baseURL = url
        } else {
            #if DEBUG
            baseURL = URL(string: "http://localhost:8080")!
            #else
            fatalError("Missing API_BASE_URL in Info.plist")
            #endif
        }
    }

    // MARK: - Public API

    func get<T: Decodable>(path: String) async throws -> T {
        try await sendData(method: .get, path: path, bodyData: nil)
    }

    /// POST with a JSON-encodable body.
    func post<T: Decodable, B: Encodable>(path: String, body: B) async throws -> T {
        let data = try encoder.encode(body)
        return try await sendData(method: .post, path: path, bodyData: data)
    }

    /// POST with no request body (e.g. /v1/users/me).
    func post<T: Decodable>(path: String) async throws -> T {
        try await sendData(method: .post, path: path, bodyData: nil)
    }

    /// PATCH with a JSON-encodable body (e.g. /v1/groups/:id).
    func patch<T: Decodable, B: Encodable>(path: String, body: B) async throws -> T {
        let data = try encoder.encode(body)
        return try await sendData(method: .patch, path: path, bodyData: data)
    }

    /// PATCH that ignores the response body — succeeds if the server returns any 2xx.
    func patch<B: Encodable>(path: String, body: B) async throws {
        let data = try encoder.encode(body)
        try await sendVoid(method: .patch, path: path, bodyData: data)
    }

    /// DELETE with no request body (e.g. /v1/groups/:id).
    func delete<T: Decodable>(path: String) async throws -> T {
        try await sendData(method: .delete, path: path, bodyData: nil)
    }

    /// DELETE that ignores the response body — succeeds if the server returns any 2xx.
    func delete(path: String) async throws {
        try await sendVoid(method: .delete, path: path)
    }

    // MARK: - Core: void request (no decode)

    private func sendVoid(method: HTTPMethod, path: String, bodyData: Data? = nil) async throws {
        var lastError: Error = TallyError.network(URLError(.unknown))

        for attempt in 0..<3 {
            if attempt > 0 {
                let base   = Double(1 << attempt)
                let jitter = Double.random(in: 0...0.5)
                try await Task.sleep(for: .seconds(base + jitter))
            }

            do {
                let token   = try await fetchToken()
                let request = buildRequest(method: method, path: path, bodyData: bodyData, token: token)
                let (_, response) = try await urlSession.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw TallyError.network(URLError(.badServerResponse))
                }
                switch http.statusCode {
                case 200..<300, 404:
                    // 2xx = success, 404 = already gone — both fine for delete
                    return
                case 401:
                    throw TallyError.unauthorized
                default:
                    throw TallyError.serverError(statusCode: http.statusCode, message: nil)
                }
            } catch TallyError.serverError(let code, _) where code >= 500 {
                lastError = TallyError.serverError(statusCode: code, message: nil)
            } catch let urlErr as URLError where isRetryable(urlErr) {
                lastError = TallyError.network(urlErr)
            } catch {
                throw error
            }
        }

        throw lastError
    }

    // MARK: - Core: retry loop

    private func sendData<T: Decodable>(
        method: HTTPMethod,
        path: String,
        bodyData: Data?
    ) async throws -> T {
        var lastError: Error = TallyError.network(URLError(.unknown))

        for attempt in 0..<3 {
            if attempt > 0 {
                // Exponential backoff: 2s, 4s with up to 0.5s jitter.
                let base   = Double(1 << attempt) // 2.0, 4.0
                let jitter = Double.random(in: 0...0.5)
                try await Task.sleep(for: .seconds(base + jitter))
            }

            do {
                return try await executeRequest(method: method, path: path, bodyData: bodyData)
            } catch TallyError.serverError(let code, _) where code >= 500 {
                lastError = TallyError.serverError(statusCode: code, message: nil)
            } catch let urlErr as URLError where isRetryable(urlErr) {
                lastError = TallyError.network(urlErr)
            } catch {
                throw error  // 4xx, decoding errors, token errors — no retry
            }
        }

        throw lastError
    }

    // MARK: - Single request execution

    private func executeRequest<T: Decodable>(
        method: HTTPMethod,
        path: String,
        bodyData: Data?
    ) async throws -> T {
        let token   = try await fetchToken()
        let request = buildRequest(method: method, path: path, bodyData: bodyData, token: token)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch let urlErr as URLError {
            throw TallyError.network(urlErr)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TallyError.network(URLError(.badServerResponse))
        }

        switch http.statusCode {
        case 200..<300:
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw TallyError.decodingFailed(error)
            }
        case 401:
            throw TallyError.unauthorized
        case 404:
            throw TallyError.notFound
        default:
            let msg = try? decoder.decode(ServerErrorBody.self, from: data)
            throw TallyError.serverError(statusCode: http.statusCode, message: msg?.error)
        }
    }

    // MARK: - Helpers

    private func buildRequest(
        method: HTTPMethod,
        path: String,
        bodyData: Data?,
        token: String
    ) -> URLRequest {
        // Use string concatenation — appendingPathComponent can percent-encode
        // or mishandle leading slashes in multi-segment paths like "/v1/groups".
        let base = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = URL(string: base + path)!
        var req = URLRequest(url: url)
        req.httpMethod = method.rawValue
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json",  forHTTPHeaderField: "Accept")
        if let bodyData {
            req.httpBody = bodyData
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return req
    }

    /// Fetch a fresh Clerk session JWT.
    /// Clerk.shared is @MainActor-isolated, so we hop there just to read the
    /// Session reference (a Sendable struct), then call getToken() from this actor.
    private func fetchToken() async throws -> String {
        let session: Session? = await MainActor.run { Clerk.shared.session }
        guard let session else { throw TallyError.tokenUnavailable }
        guard let token = try await session.getToken() else {
            throw TallyError.tokenUnavailable
        }
        return token
    }

    private func isRetryable(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost:
            return true
        default:
            return false
        }
    }

    // Nested so its Decodable conformance is actor-isolated to APIClient,
    // avoiding a Swift 6 MainActor isolation mismatch warning.
    private struct ServerErrorBody: Decodable, Sendable {
        let error: String?
    }
}
