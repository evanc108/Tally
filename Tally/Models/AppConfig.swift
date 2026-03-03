import Foundation

enum AppConfig {
    static var clerkPublishableKey: String {
        guard let key = Bundle.main.infoDictionary?["CLERK_PUBLISHABLE_KEY"] as? String, !key.isEmpty else {
            fatalError("CLERK_PUBLISHABLE_KEY not found in Info.plist. Check Secrets.xcconfig.")
        }
        return key
    }
}
