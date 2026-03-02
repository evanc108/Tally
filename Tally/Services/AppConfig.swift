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
}
