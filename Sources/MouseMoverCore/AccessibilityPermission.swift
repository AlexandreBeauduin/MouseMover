import ApplicationServices
import Foundation

public enum AccessibilityPermission {
    private static let promptedKey = "accessibilityPromptShown"

    /// Shows the system Accessibility prompt (adds the app to the list in System Settings).
    public static func requestPrompt() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Asks only once, on the first launch without the permission.
    public static func requestPromptOnce(defaults: UserDefaults = .standard,
                                         isTrusted: () -> Bool = { AXIsProcessTrusted() },
                                         prompt: () -> Void = AccessibilityPermission.requestPrompt) {
        guard !isTrusted(), !defaults.bool(forKey: promptedKey) else { return }
        defaults.set(true, forKey: promptedKey)
        prompt()
    }
}
