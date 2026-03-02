import Foundation
import ClerkKit

/// Maps Clerk SDK errors to user-friendly messages per SYSTEM.md 2.7:
/// "Never show raw error codes, exception messages, or technical jargon to users."
enum ClerkErrorMapper {

    static func userMessage(for error: Error) -> String {
        // Check for Clerk API errors with structured codes
        if let apiError = error as? ClerkAPIError {
            return message(for: apiError)
        }

        // Check for Clerk client-side errors
        if let clientError = error as? ClerkClientError,
           let message = clientError.message {
            return message
        }

        // Catch network-level errors
        let description = error.localizedDescription.lowercased()
        if description.contains("network") || description.contains("internet")
            || description.contains("offline") || description.contains("timed out") {
            return "Unable to connect. Please check your internet connection and try again."
        }

        return "Something went wrong. Please try again."
    }

    private static func message(for error: ClerkAPIError) -> String {
        switch error.code {
        case "form_identifier_not_found":
            return "No account found with this email."
        case "form_password_incorrect":
            return "Incorrect password. Please try again."
        case "form_identifier_exists":
            return "An account with this email already exists. Try signing in instead."
        case "form_password_pwned",
             "form_password_length_too_short",
             "form_password_not_strong_enough":
            return error.message ?? "Password doesn't meet requirements. Use at least 8 characters with a mix of letters and numbers."
        case "form_code_incorrect":
            return "Invalid verification code. Please check and try again."
        case "verification_expired":
            return "Verification code has expired. Please request a new one."
        case "session_exists":
            return "You're already signed in."
        case "too_many_requests":
            return "Too many attempts. Please wait a moment and try again."
        case "form_param_nil":
            return "Please fill in all required fields."
        default:
            // Use Clerk's own message if it looks safe, otherwise generic fallback
            if let message = error.message, !message.isEmpty, message.count < 120 {
                return message
            }
            return "Something went wrong. Please try again."
        }
    }
}
