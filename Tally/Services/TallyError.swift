import Foundation

enum TallyError: Error, LocalizedError {
    case network(URLError)
    case serverError(statusCode: Int, message: String?)
    case unauthorized
    case notFound
    case decodingFailed(Error)
    case tokenUnavailable

    var errorDescription: String? {
        switch self {
        case .network(let e):              return e.localizedDescription
        case .serverError(let code, let msg): return msg ?? "Server error (\(code))"
        case .unauthorized:                return String(localized: "Session expired. Please sign in again.")
        case .notFound:                    return String(localized: "Resource not found.")
        case .decodingFailed:              return String(localized: "Unexpected response from server.")
        case .tokenUnavailable:            return String(localized: "Not signed in.")
        }
    }
}
