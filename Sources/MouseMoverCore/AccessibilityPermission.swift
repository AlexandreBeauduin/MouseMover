import ApplicationServices
import Foundation

public enum AccessibilityPermission {
    private static let promptedKey = "accessibilityPromptShown"

    /// Affiche la demande systeme d'Accessibilite (ajoute l'app a la liste des Reglages).
    public static func requestPrompt() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Demande l'autorisation une seule fois, au premier lancement sans permission.
    public static func requestPromptOnce(defaults: UserDefaults = .standard,
                                         isTrusted: () -> Bool = { AXIsProcessTrusted() },
                                         prompt: () -> Void = AccessibilityPermission.requestPrompt) {
        guard !isTrusted(), !defaults.bool(forKey: promptedKey) else { return }
        defaults.set(true, forKey: promptedKey)
        prompt()
    }
}
