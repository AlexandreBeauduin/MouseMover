import AppIntents
import MouseMoverCore

// MARK: - Display entity

struct DisplayEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Display"
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
        DisplayEntity(id: autoID, name: L10n.mainDisplayAuto)
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

// MARK: - Pattern entity

struct PatternEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Pattern"
    static let defaultQuery = PatternEntityQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct PatternEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [PatternEntity] {
        await Self.allEntities().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [PatternEntity] {
        let query = string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return await Self.allEntities().filter {
            $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(query)
        }
    }

    func suggestedEntities() async throws -> [PatternEntity] {
        await Self.allEntities()
    }

    @MainActor
    private static func allEntities() -> [PatternEntity] {
        MouseMoverController.shared.patterns
            .filter { !$0.points.isEmpty }
            .map { PatternEntity(id: $0.id, name: $0.name) }
    }
}

// MARK: - Intents

struct StartMouseMoverIntent: AppIntent {
    static let title: LocalizedStringResource = "Start MouseMover"
    static let description = IntentDescription("Starts moving the mouse automatically.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        MouseMoverController.shared.start()
        return .result(dialog: "\(L10n.startedDialog)")
    }
}

struct StopMouseMoverIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop MouseMover"
    static let description = IntentDescription("Pauses the automatic mouse movement.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        MouseMoverController.shared.stop()
        return .result(dialog: "\(L10n.stoppedDialog)")
    }
}

struct RunNowIntent: AppIntent {
    static let title: LocalizedStringResource = "Run MouseMover Now"
    static let description = IntentDescription("Runs a mouse activity cycle right away.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let started = MouseMoverController.shared.runNow()
        return .result(dialog: "\(started ? L10n.cycleStarted : L10n.cycleAlreadyRunning)")
    }
}

struct SetIntervalIntent: AppIntent {
    static let title: LocalizedStringResource = "Set MouseMover Interval"
    static let description = IntentDescription("Sets the time, in minutes, between two activities.")

    @Parameter(title: "Minutes", description: "Time between two activities, in minutes.", default: 5,
               controlStyle: .field)
    var minutes: Double

    static var parameterSummary: some ParameterSummary {
        Summary("Set MouseMover interval to \(\.$minutes) minutes")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard MouseMoverController.shared.setCustomInterval(minutesText: String(minutes)) else {
            throw IntentError.invalidMinutes
        }
        return .result(dialog: "\(L10n.intervalSet(Self.format(minutes)))")
    }

    private static func format(_ minutes: Double) -> String {
        minutes.rounded() == minutes ? String(Int(minutes)) : String(minutes)
    }
}

struct SetDisplayIntent: AppIntent {
    static let title: LocalizedStringResource = "Choose MouseMover Display"
    static let description = IntentDescription("Chooses the display on which the mouse moves.")

    @Parameter(title: "Display")
    var display: DisplayEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Use \(\.$display) for MouseMover")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        MouseMoverController.shared.selectDisplay(display.displayID)
        return .result(dialog: "\(L10n.displaySet(display.name))")
    }
}

struct SetPatternIntent: AppIntent {
    static let title: LocalizedStringResource = "Choose MouseMover Pattern"
    static let description = IntentDescription("Chooses the mouse movement played on each cycle.")

    @Parameter(title: "Pattern")
    var pattern: PatternEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Use the \(\.$pattern) pattern for MouseMover")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard MouseMoverController.shared.usePattern(pattern.id) else {
            throw IntentError.unknownPattern
        }
        return .result(dialog: "\(L10n.patternSet(pattern.name))")
    }
}

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case invalidMinutes
    case unknownPattern

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .invalidMinutes: "\(L10n.invalidMinutes)"
        case .unknownPattern: "\(L10n.unknownPattern)"
        }
    }
}

// MARK: - App Shortcuts
//
// English is the source language. Translations of every static string above (titles, descriptions,
// parameters, summaries) are in *.lproj/Localizable.strings, and of the phrases below in
// *.lproj/AppShortcuts.strings. Runtime dialogs use L10n, like the rest of the app.

struct MouseMoverShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartMouseMoverIntent(),
            phrases: [
                // Avoid "Open" / "Launch": Siri takes them as "open the app".
                "Start mouse movement with \(.applicationName)",
                "Turn on mouse movement in \(.applicationName)",
                "Turn on \(.applicationName)",
                "Start \(.applicationName)",
            ],
            shortTitle: "Start",
            systemImageName: "play.fill")

        AppShortcut(
            intent: StopMouseMoverIntent(),
            phrases: [
                "Stop mouse movement in \(.applicationName)",
                "Pause \(.applicationName)",
                "Turn off \(.applicationName)",
                "Stop \(.applicationName)",
            ],
            shortTitle: "Stop",
            systemImageName: "pause.fill")

        AppShortcut(
            intent: RunNowIntent(),
            phrases: [
                "Run \(.applicationName) now",
                "Move the mouse with \(.applicationName)",
            ],
            shortTitle: "Run Now",
            systemImageName: "cursorarrow.motionlines")

        AppShortcut(
            intent: SetDisplayIntent(),
            phrases: [
                "Use \(\.$display) for \(.applicationName)",
                "Change the \(.applicationName) display to \(\.$display)",
            ],
            shortTitle: "Choose Display",
            systemImageName: "display")

        AppShortcut(
            intent: SetPatternIntent(),
            phrases: [
                "Use the \(\.$pattern) pattern with \(.applicationName)",
                "Change the \(.applicationName) pattern to \(\.$pattern)",
            ],
            shortTitle: "Choose Pattern",
            systemImageName: "scribble.variable")
    }
}
