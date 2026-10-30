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
            [await MainActor.run { MouseMoverTimerEntity.current() }]
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

    static func start() {
        let controller = MouseMoverController.shared
        observation = Publishers.CombineLatest(controller.$isRunning, controller.$interval)
            .removeDuplicates { $0 == $1 }
            .sink { _, _ in Task { try? await donate() } }
    }

    private static let logger = Logger(subsystem: "com.pudeldoodle.MouseMoverApp", category: "spotlight")

    static func donate() async throws {
        do {
            try await CSSearchableIndex(name: "MouseMoverTimer")
                .indexAppEntities([MouseMoverTimerEntity.current()])
            logger.notice("Minuteur indexé dans Spotlight")
        } catch {
            logger.error("Indexation Spotlight échouée : \(String(describing: error), privacy: .public)")
            throw error
        }
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
        MouseMoverController.shared.stop()
        return .result()
    }
}
