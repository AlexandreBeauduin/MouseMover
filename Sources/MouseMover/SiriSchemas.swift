import AppIntents
import Combine
import CoreSpotlight
import os
import MouseMoverCore

// Siri AI (macOS 27) n'exécute que les intents qui adoptent un schéma d'app (voir
// « Apple Intelligence and Siri AI » dans la doc App Intents). Il n'existe pas de domaine
// générique : le cycle de MouseMover (compte à rebours puis mouvement de souris, démarrable,
// en pause, reprenable) est modélisé avec le groupe de schémas `clock` « timer ».
// « Mets MouseMover en pause » = pauseTimer, « relance MouseMover » = resumeTimer, etc.

@available(macOS 27.0, *)
@AppEnum(schema: .clock.timerState)
enum MouseMoverTimerState: String {
    case firing
    case paused
    case running
    case undefined

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .firing: "En cours",
        .paused: "En pause",
        .running: "Actif",
        .undefined: "Inconnu",
    ]
}

@available(macOS 27.0, *)
@AppEntity(schema: .clock.timer)
struct MouseMoverTimerEntity: IndexedEntity {
    static let timerID = "mousemover"
    static let defaultQuery = MouseMoverTimerQuery()

    let id: String

    // Les propriétés du schéma sont calculées depuis un instantané de l'état du contrôleur.
    private let intervalSeconds: Int
    private let remainingSeconds: Int
    private let timerState: MouseMoverTimerState

    var duration: Duration { .seconds(intervalSeconds) }
    var durationRemaining: Duration { .seconds(remainingSeconds) }
    var state: MouseMoverTimerState { timerState }
    var label: String? { "MouseMover" }
    var isSleepTimer: Bool { false }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "MouseMover")
    }

    @MainActor
    static func current() -> MouseMoverTimerEntity {
        let controller = MouseMoverController.shared
        let state: MouseMoverTimerState
        if controller.isBusy {
            state = .firing
        } else {
            state = controller.isRunning ? .running : .paused
        }
        return MouseMoverTimerEntity(
            id: timerID,
            intervalSeconds: controller.interval,
            remainingSeconds: max(controller.remaining, 0),
            timerState: state)
    }

    struct MouseMoverTimerQuery: EntityStringQuery, IndexedEntityQuery {
        func entities(for identifiers: [MouseMoverTimerEntity.ID]) async throws -> [MouseMoverTimerEntity] {
            MouseMoverSiriLog.logger.notice("Requête minuteur par identifiants")
            guard identifiers.contains(MouseMoverTimerEntity.timerID) else { return [] }
            return [await MainActor.run { MouseMoverTimerEntity.current() }]
        }

        func reindexEntities(for identifiers: [MouseMoverTimerEntity.ID],
                             indexDescription: CSSearchableIndexDescription) async throws {
            try await MouseMoverTimerIndexer.donate()
        }

        func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
            try await MouseMoverTimerIndexer.donate()
        }

        func entities(matching string: String) async throws -> [MouseMoverTimerEntity] {
            // Un seul « minuteur » existe : quelle que soit la recherche, c'est celui-là.
            MouseMoverSiriLog.logger.notice("Recherche de minuteur")
            return [await MainActor.run { MouseMoverTimerEntity.current() }]
        }

        func suggestedEntities() async throws -> [MouseMoverTimerEntity] {
            [await MainActor.run { MouseMoverTimerEntity.current() }]
        }
    }
}

/// Siri retrouve les entités via l'index Spotlight : on y dépose l'état courant du minuteur
/// au lancement puis à chaque changement (actif / en pause / intervalle).
@available(macOS 27.0, *)
@MainActor
enum MouseMoverTimerIndexer {
    private static var observation: AnyCancellable?
    private static var usage: AnyCancellable?

    static func start() {
        let controller = MouseMoverController.shared
        observation = Publishers.CombineLatest(controller.$isRunning, controller.$interval)
            .removeDuplicates { $0 == $1 }
            .sink { _, _ in Task { try? await donate() } }
        usage = controller.$isRunning.dropFirst().removeDuplicates()
            .sink { running in Task { await donateUsage(running ? .start : .stop) } }
    }

    private static let logger = Logger(subsystem: "com.pudeldoodle.MouseMoverApp", category: "spotlight")

    /// Les donations aident Siri à déduire la bonne app ; seuls les intents à schéma comptent.
    private static func donateUsage(_ command: MouseMoverCommand) async {
        var intent = OpenMouseMoverCommandIntent()
        intent.target = MouseMoverCommandEntity(id: command.rawValue)
        do {
            _ = try await IntentDonationManager.shared.donate(intent: intent)
            logger.notice("Donation de la commande \(command.rawValue, privacy: .public)")
        } catch {
            logger.error("Donation échouée : \(String(describing: error), privacy: .public)")
        }
    }

    static func donate() async throws {
        do {
            let index = CSSearchableIndex(name: "MouseMoverTimer")
            try await index.indexAppEntities([MouseMoverTimerEntity.current()])
            try await index.indexAppEntities([MouseMoverAlarmEntity.current()])
            try await index.indexAppEntities(MouseMoverCommandEntity.all)
            logger.notice("Minuteur, alarme et commandes indexés dans Spotlight")
        } catch {
            logger.error("Indexation Spotlight échouée : \(String(describing: error), privacy: .public)")
            throw error
        }
    }
}

// Le registre d'outils de Siri ignore un conteneur s'il lui manque des schémas requis
// (« is missing required schemas ») : le groupe alarme complète donc le groupe timer.
// L'alarme MouseMover est le même cycle vu autrement : « active » = démarré.

@available(macOS 27.0, *)
@AppEnum(schema: .clock.alarmTriggerState)
enum MouseMoverAlarmTriggerState: String {
    case firing
    case snoozed
    case none

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .firing: "En cours",
        .snoozed: "Reportée",
        .none: "Aucun",
    ]
}

@available(macOS 27.0, *)
@AppEntity(schema: .clock.alarm)
struct MouseMoverAlarmEntity: IndexedEntity {
    static let alarmID = "mousemover-alarm"
    static let defaultQuery = MouseMoverAlarmQuery()

    let id: String

    private let enabled: Bool
    private let nextRun: DateComponents
    private let alarmTriggerState: MouseMoverAlarmTriggerState

    var time: DateComponents { nextRun }
    var isEnabled: Bool { enabled }
    var label: String? { "MouseMover" }
    var recurrenceDays: Calendar.RecurrenceRule? { nil }
    var canSnooze: Bool { true }
    var triggerState: MouseMoverAlarmTriggerState { alarmTriggerState }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "MouseMover")
    }

    @MainActor
    static func current() -> MouseMoverAlarmEntity {
        let controller = MouseMoverController.shared
        let next = Date().addingTimeInterval(TimeInterval(max(controller.remaining, 0)))
        return MouseMoverAlarmEntity(
            id: alarmID,
            enabled: controller.isRunning,
            nextRun: Calendar.current.dateComponents([.hour, .minute], from: next),
            alarmTriggerState: controller.isBusy ? .firing : .none)
    }

    struct MouseMoverAlarmQuery: EntityStringQuery, IndexedEntityQuery {
        func entities(for identifiers: [MouseMoverAlarmEntity.ID]) async throws -> [MouseMoverAlarmEntity] {
            MouseMoverSiriLog.logger.notice("Requête alarme par identifiants")
            guard identifiers.contains(MouseMoverAlarmEntity.alarmID) else { return [] }
            return [await MainActor.run { MouseMoverAlarmEntity.current() }]
        }

        func reindexEntities(for identifiers: [MouseMoverAlarmEntity.ID],
                             indexDescription: CSSearchableIndexDescription) async throws {
            try await MouseMoverTimerIndexer.donate()
        }

        func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
            try await MouseMoverTimerIndexer.donate()
        }

        func entities(matching string: String) async throws -> [MouseMoverAlarmEntity] {
            MouseMoverSiriLog.logger.notice("Recherche d'alarme")
            return [await MainActor.run { MouseMoverAlarmEntity.current() }]
        }

        func suggestedEntities() async throws -> [MouseMoverAlarmEntity] {
            [await MainActor.run { MouseMoverAlarmEntity.current() }]
        }
    }
}

@available(macOS 27.0, *)
@AppIntent(schema: .clock.createAlarm)
struct CreateMouseMoverAlarmIntent {
    static let isAssistantOnly: Bool = true

    var time: DateComponents
    var label: String?
    var recurrenceDays: Calendar.RecurrenceRule?
    var canSnooze: Bool

    @MainActor
    func perform() async throws -> some ReturnsValue<MouseMoverAlarmEntity> {
        MouseMoverSiriLog.logger.notice("Siri : createAlarm")
        MouseMoverController.shared.start()
        return .result(value: MouseMoverAlarmEntity.current())
    }
}

@available(macOS 27.0, *)
@AppIntent(schema: .clock.updateAlarm)
struct UpdateMouseMoverAlarmIntent {
    static let isAssistantOnly: Bool = true

    var alarm: MouseMoverAlarmEntity
    var isEnabled: Bool?
    var time: DateComponents?
    var label: String?
    var recurrenceDays: Calendar.RecurrenceRule?
    var allowsSnooze: Bool?

    @MainActor
    func perform() async throws -> some ReturnsValue<MouseMoverAlarmEntity> {
        MouseMoverSiriLog.logger.notice("Siri : updateAlarm")
        if let isEnabled {
            isEnabled ? MouseMoverController.shared.start() : MouseMoverController.shared.stop()
        }
        return .result(value: MouseMoverAlarmEntity.current())
    }
}

@available(macOS 27.0, *)
@AppIntent(schema: .clock.dismissAlarm)
struct DismissMouseMoverAlarmIntent {
    static let isAssistantOnly: Bool = true

    var alarm: MouseMoverAlarmEntity

    @MainActor
    func perform() async throws -> some ReturnsValue<MouseMoverAlarmEntity> {
        MouseMoverSiriLog.logger.notice("Siri : dismissAlarm")
        MouseMoverController.shared.stop()
        return .result(value: MouseMoverAlarmEntity.current())
    }
}

@available(macOS 27.0, *)
@AppIntent(schema: .clock.snoozeAlarm)
struct SnoozeMouseMoverAlarmIntent {
    static let isAssistantOnly: Bool = true

    var alarm: MouseMoverAlarmEntity
    var duration: Duration

    @MainActor
    func perform() async throws -> some ReturnsValue<MouseMoverAlarmEntity> {
        MouseMoverSiriLog.logger.notice("Siri : snoozeAlarm")
        MouseMoverController.shared.remaining = max(Int(duration.components.seconds), 1)
        return .result(value: MouseMoverAlarmEntity.current())
    }
}

@available(macOS 27.0, *)
@AppIntent(schema: .clock.deleteAlarm)
struct DeleteMouseMoverAlarmIntent: DeleteIntent {
    static let isAssistantOnly: Bool = true

    var entities: [MouseMoverAlarmEntity]

    @MainActor
    func perform() async throws -> some IntentResult {
        MouseMoverSiriLog.logger.notice("Siri : deleteAlarm")
        MouseMoverController.shared.stop()
        return .result()
    }
}

enum MouseMoverSiriLog {
    static let logger = Logger(subsystem: "com.pudeldoodle.MouseMoverApp", category: "siri")
}

// Le domaine `system` est le seul sans modèle métier imposé : `open` agit sur n'importe quelle
// entité et `searchInApp` reçoit un texte libre. Chaque commande de MouseMover devient donc une
// entité indexée : « ouvrir » la commande Pause met MouseMover en pause. L'entité porte aussi
// les mots-clés qui permettent à l'index sémantique de la retrouver.

@available(macOS 27.0, *)
struct MouseMoverCommandEntity: IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Commande MouseMover"
    static let defaultQuery = MouseMoverCommandQuery()

    static var all: [MouseMoverCommandEntity] {
        MouseMoverCommand.allCases.map { MouseMoverCommandEntity(id: $0.rawValue) }
    }

    let id: String

    private var command: MouseMoverCommand? { MouseMoverCommand(rawValue: id) }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(command?.title ?? id) (MouseMover)")
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.keywords = ["MouseMover"] + (command?.keywords ?? [])
        return attributes
    }

    @MainActor
    func run() {
        command?.apply(to: MouseMoverController.shared)
    }

    struct MouseMoverCommandQuery: EntityStringQuery, EnumerableEntityQuery, IndexedEntityQuery {
        func entities(for identifiers: [MouseMoverCommandEntity.ID]) async throws -> [MouseMoverCommandEntity] {
            MouseMoverSiriLog.logger.notice("Requête commande par identifiants")
            return MouseMoverCommandEntity.all.filter { identifiers.contains($0.id) }
        }

        func entities(matching string: String) async throws -> [MouseMoverCommandEntity] {
            MouseMoverSiriLog.logger.notice("Recherche de commande")
            guard let command = MouseMoverCommand(matching: string) else {
                return MouseMoverCommandEntity.all
            }
            return [MouseMoverCommandEntity(id: command.rawValue)]
        }

        func allEntities() async throws -> [MouseMoverCommandEntity] {
            MouseMoverCommandEntity.all
        }

        func suggestedEntities() async throws -> [MouseMoverCommandEntity] {
            MouseMoverCommandEntity.all
        }

        func reindexEntities(for identifiers: [MouseMoverCommandEntity.ID],
                             indexDescription: CSSearchableIndexDescription) async throws {
            try await MouseMoverTimerIndexer.donate()
        }

        func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
            try await MouseMoverTimerIndexer.donate()
        }
    }
}

@available(macOS 27.0, *)
@AppIntent(schema: .system.open)
struct OpenMouseMoverCommandIntent {
    static let supportedModes: IntentModes = .background

    var target: MouseMoverCommandEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        MouseMoverSiriLog.logger.notice("Siri : open \(target.id, privacy: .public)")
        target.run()
        return .result()
    }
}

@available(macOS 27.0, *)
@AppIntent(schema: .system.searchInApp)
struct SearchMouseMoverCommandIntent {
    static let searchScopes: [StringSearchScope] = [.general]

    var criteria: StringSearchCriteria

    @MainActor
    func perform() async throws -> some IntentResult {
        MouseMoverSiriLog.logger.notice("Siri : searchInApp")
        MouseMoverCommand(matching: criteria.term)?.apply(to: MouseMoverController.shared)
        return .result()
    }
}

@available(macOS 27.0, *)
enum MouseMoverTimerActions {
    @MainActor
    static func apply(duration: Duration) throws {
        let seconds = Int(duration.components.seconds)
        guard MouseMoverController.shared.setInterval(seconds: seconds) else {
            throw IntentError.invalidMinutes
        }
    }
}

@available(macOS 27.0, *)
@AppIntent(schema: .clock.createTimer)
struct CreateMouseMoverTimerIntent {
    static let isAssistantOnly: Bool = true

    var duration: Duration
    var label: String?
    var isSleepTimer: Bool

    @MainActor
    func perform() async throws -> some ReturnsValue<MouseMoverTimerEntity> {
        MouseMoverSiriLog.logger.notice("Siri : createTimer")
        try MouseMoverTimerActions.apply(duration: duration)
        MouseMoverController.shared.start()
        return .result(value: MouseMoverTimerEntity.current())
    }
}

@available(macOS 27.0, *)
@AppIntent(schema: .clock.updateTimer)
struct UpdateMouseMoverTimerIntent {
    static let isAssistantOnly: Bool = true

    var timer: MouseMoverTimerEntity
    var duration: Duration?
    var label: String?
    var isSleepTimer: Bool?

    @MainActor
    func perform() async throws -> some ReturnsValue<MouseMoverTimerEntity> {
        MouseMoverSiriLog.logger.notice("Siri : updateTimer")
        if let duration { try MouseMoverTimerActions.apply(duration: duration) }
        return .result(value: MouseMoverTimerEntity.current())
    }
}

@available(macOS 27.0, *)
@AppIntent(schema: .clock.pauseTimer)
struct PauseMouseMoverTimerIntent {
    static let isAssistantOnly: Bool = true

    var timer: MouseMoverTimerEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        MouseMoverSiriLog.logger.notice("Siri : pauseTimer")
        MouseMoverController.shared.stop()
        return .result()
    }
}

@available(macOS 27.0, *)
@AppIntent(schema: .clock.resumeTimer)
struct ResumeMouseMoverTimerIntent {
    static let isAssistantOnly: Bool = true

    var timer: MouseMoverTimerEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        MouseMoverSiriLog.logger.notice("Siri : resumeTimer")
        MouseMoverController.shared.start()
        return .result()
    }
}

@available(macOS 27.0, *)
@AppIntent(schema: .clock.cancelTimer)
struct CancelMouseMoverTimerIntent {
    static let isAssistantOnly: Bool = true

    var entities: [MouseMoverTimerEntity]

    @MainActor
    func perform() async throws -> some IntentResult {
        MouseMoverSiriLog.logger.notice("Siri : cancelTimer")
        MouseMoverController.shared.stop()
        return .result()
    }
}
