import AppIntents
import MouseMoverCore

// MARK: - Entite « Écran »

struct DisplayEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Écran"
    static let defaultQuery = DisplayEntityQuery()

    static let autoID = "auto"

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    var displayID: UInt32? {
        id == Self.autoID ? nil : UInt32(id)
    }

    static var auto: DisplayEntity {
        DisplayEntity(id: autoID, name: "Écran principal (auto)")
    }
}

struct DisplayEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [DisplayEntity] {
        let all = await Self.allEntities()
        return all.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [DisplayEntity] {
        await Self.allEntities()
    }

    @MainActor
    private static func allEntities() -> [DisplayEntity] {
        let controller = MouseMoverController.shared
        controller.refreshDisplays()
        let displays = controller.displays.enumerated().map { index, display in
            DisplayEntity(id: String(display.id),
                          name: DisplayCatalog.label(for: display, index: index + 1))
        }
        return [DisplayEntity.auto] + displays
    }
}

// MARK: - Intents

struct StartMouseMoverIntent: AppIntent {
    static let title: LocalizedStringResource = "Démarrer MouseMover"
    static let description = IntentDescription("Démarre le mouvement automatique de la souris.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        MouseMoverController.shared.start()
        return .result(dialog: "MouseMover est démarré.")
    }
}

struct StopMouseMoverIntent: AppIntent {
    static let title: LocalizedStringResource = "Arrêter MouseMover"
    static let description = IntentDescription("Met en pause le mouvement automatique de la souris.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        MouseMoverController.shared.stop()
        return .result(dialog: "MouseMover est en pause.")
    }
}

struct RunNowIntent: AppIntent {
    static let title: LocalizedStringResource = "Exécuter MouseMover maintenant"
    static let description = IntentDescription("Lance immédiatement un cycle d'activité de la souris.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let started = MouseMoverController.shared.runNow()
        return .result(dialog: started
            ? "Cycle lancé."
            : "Un cycle est déjà en cours.")
    }
}

struct SetIntervalIntent: AppIntent {
    static let title: LocalizedStringResource = "Régler l'intervalle de MouseMover"
    static let description = IntentDescription("Définit la durée, en minutes, entre deux activités.")

    @Parameter(title: "Minutes", description: "Durée entre deux activités, en minutes.", default: 5,
               controlStyle: .field)
    var minutes: Double

    static var parameterSummary: some ParameterSummary {
        Summary("Régler l'intervalle de MouseMover sur \(\.$minutes) minutes")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard MouseMoverController.shared.setCustomInterval(minutesText: String(minutes)) else {
            throw IntentError.invalidMinutes
        }
        return .result(dialog: "Intervalle réglé sur \(Self.format(minutes)) minutes.")
    }

    private static func format(_ minutes: Double) -> String {
        minutes.rounded() == minutes ? String(Int(minutes)) : String(minutes)
    }
}

struct SetDisplayIntent: AppIntent {
    static let title: LocalizedStringResource = "Choisir l'écran de MouseMover"
    static let description = IntentDescription("Choisit l'écran sur lequel la souris est déplacée.")

    @Parameter(title: "Écran")
    var display: DisplayEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Utiliser \(\.$display) pour MouseMover")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        MouseMoverController.shared.selectDisplay(display.displayID)
        return .result(dialog: "MouseMover utilise maintenant « \(display.name) ».")
    }
}

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case invalidMinutes

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .invalidMinutes: "Entre un nombre de minutes supérieur à 0."
        }
    }
}

// MARK: - Phrases Siri

struct MouseMoverShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartMouseMoverIntent(),
            phrases: [
                // Pas de « Lance » / « Ouvre » : Siri les prend pour « ouvrir l'application ».
                "Démarre le mouvement de souris avec \(.applicationName)",
                "Active le mouvement de souris de \(.applicationName)",
                "Mets \(.applicationName) en marche",
                "Démarre \(.applicationName)",
            ],
            shortTitle: "Démarrer",
            systemImageName: "play.fill")

        AppShortcut(
            intent: StopMouseMoverIntent(),
            phrases: [
                "Arrête le mouvement de souris de \(.applicationName)",
                "Mets \(.applicationName) en pause",
                "Désactive \(.applicationName)",
                "Arrête \(.applicationName)",
            ],
            shortTitle: "Arrêter",
            systemImageName: "pause.fill")

        AppShortcut(
            intent: RunNowIntent(),
            phrases: [
                "Exécute \(.applicationName) maintenant",
                "Bouge la souris avec \(.applicationName)",
            ],
            shortTitle: "Exécuter maintenant",
            systemImageName: "cursorarrow.motionlines")

        AppShortcut(
            intent: SetDisplayIntent(),
            phrases: [
                "Utilise \(\.$display) pour \(.applicationName)",
                "Change l'écran de \(.applicationName) pour \(\.$display)",
            ],
            shortTitle: "Choisir l'écran",
            systemImageName: "display")
    }
}
