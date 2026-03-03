import Foundation

enum AppConfig {
    /// Reads CLERK_PUBLISHABLE_KEY from Secrets.xcconfig via Info.plist build settings.
    static var clerkPublishableKey: String {
        guard let key = Bundle.main.infoDictionary?["CLERK_PUBLISHABLE_KEY"] as? String,
              !key.isEmpty
        else {
            fatalError(
                """
                Missing CLERK_PUBLISHABLE_KEY.
                1. Copy Tally/Secrets.xcconfig.example to Tally/Secrets.xcconfig
                2. Add your Clerk publishable key
                3. Clean build (Cmd+Shift+K) and rebuild
                """
            )
        }
        return key
    }

    /// Base URL for the Tally REST API.
    /// Reads API_BASE_URL from Secrets.xcconfig via Info.plist.
    /// Falls back to localhost:8080 in DEBUG builds if the key is absent.
    static var apiBaseURL: URL {
        // Validate that the URL has a non-empty host. xcconfig strips // as a
        // comment if not escaped, leaving just "http:" with no host. Catch that.
        if let raw = Bundle.main.infoDictionary?["API_BASE_URL"] as? String,
           !raw.isEmpty,
           let url = URL(string: raw),
           url.host?.isEmpty == false {
            return url
        }
        #if DEBUG
        return URL(string: "http://localhost:8080")!
        #else
        fatalError(
            """
            Missing API_BASE_URL.
            1. Copy Tally/Secrets.xcconfig.example to Tally/Secrets.xcconfig
            2. Set API_BASE_URL to your backend URL
            3. Clean build (Cmd+Shift+K) and rebuild
            """
        )
        #endif
    }
}
