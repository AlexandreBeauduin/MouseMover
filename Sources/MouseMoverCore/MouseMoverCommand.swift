import Foundation

/// Commande exposée à Siri : un état cible ou une action, désignée par une phrase libre.
public enum MouseMoverCommand: String, CaseIterable, Sendable {
    case start
    case stop
    case runNow

    public var title: String {
        switch self {
        case .start: "Démarrer"
        case .stop: "Pause"
        case .runNow: "Bouger la souris"
        }
    }

    public var keywords: [String] {
        switch self {
        case .start: ["demarrer", "demarre", "reprendre", "reprends", "activer", "active", "lancer", "lance", "marche"]
        case .stop: ["pause", "arreter", "arrete", "stop", "desactiver", "desactive", "suspendre", "suspends"]
        case .runNow: ["bouger", "bouge", "souris", "maintenant", "executer", "execute", "cycle"]
        }
    }

    /// Le mot le plus tôt dans la phrase décide : « arrête le mouvement de souris » est un arrêt.
    public init?(matching text: String) {
        let words = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr"))
            .split { !$0.isLetter }
            .map(String.init)
        for word in words {
            if let command = Self.allCases.first(where: { $0.keywords.contains(word) }) {
                self = command
                return
            }
        }
        return nil
    }

    @MainActor
    @discardableResult
    public func apply(to controller: MouseMoverController) -> Bool {
        switch self {
        case .start:
            controller.start()
            return true
        case .stop:
            controller.stop()
            return true
        case .runNow:
            return controller.runNow()
        }
    }
}
