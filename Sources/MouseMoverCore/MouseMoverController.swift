import ApplicationServices
import Combine
import Foundation

@MainActor
public protocol CycleRunning: AnyObject {
    /// Lance un cycle sur l'ecran donne puis appelle `completion` (sur le main actor) une fois termine.
    func runCycle(on display: DisplayInfo, completion: @escaping @MainActor () -> Void)
}

@MainActor
public final class SystemCycleRunner: CycleRunning {
    public nonisolated init() {}

    public func runCycle(on display: DisplayInfo, completion: @escaping @MainActor () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let cycle = ActivityCycle(driver: CGMouseDriver(), random: SystemRandom())
            _ = cycle.run(on: display)
            Task { @MainActor in completion() }
        }
    }
}

/// Compte a rebours isole du reste de l'etat : il change chaque seconde et ne doit rafraichir que le titre
/// de la barre de menus, jamais le menu ouvert (sinon les sous-menus se referment).
@MainActor
public final class CountdownState: ObservableObject {
    @Published public var remaining: Int

    public init(remaining: Int) {
        self.remaining = remaining
    }
}

@MainActor
public final class MouseMoverController: ObservableObject {
    public static let intervalPresets: [(label: String, seconds: Int)] = [
        ("1 min", 60), ("3 min", 180), ("5 min", 300), ("10 min", 600), ("15 min", 900),
    ]

    public static let shared = MouseMoverController()

    @Published public private(set) var isRunning = false
    public let countdown: CountdownState
    @Published public private(set) var interval: Int
    @Published public private(set) var selectedDisplayID: UInt32?
    @Published public private(set) var displays: [DisplayInfo]
    @Published public private(set) var isBusy = false
    @Published public private(set) var launchAtLoginEnabled: Bool
    @Published public private(set) var accessibilityTrusted: Bool

    private var config: MouseMoverConfig
    private let configStore: ConfigStore
    private let displayProvider: DisplayProviding
    private let cycleRunner: CycleRunning
    private let loginItem: LoginItemManaging
    private let accessibilityCheck: () -> Bool
    private var timer: Timer?

    public init(configStore: ConfigStore = ConfigStore(),
                displayProvider: DisplayProviding = SystemDisplayProvider(),
                cycleRunner: CycleRunning = SystemCycleRunner(),
                loginItem: LoginItemManaging = SystemLoginItem(),
                accessibilityCheck: @escaping () -> Bool = { AXIsProcessTrusted() }) {
        let config = configStore.load()
        self.config = config
        self.configStore = configStore
        self.displayProvider = displayProvider
        self.cycleRunner = cycleRunner
        self.loginItem = loginItem
        self.accessibilityCheck = accessibilityCheck

        self.interval = config.intervalSeconds
        self.countdown = CountdownState(remaining: config.intervalSeconds)
        self.selectedDisplayID = config.displayID
        self.displays = displayProvider.activeDisplays()
        self.launchAtLoginEnabled = loginItem.isEnabled
        self.accessibilityTrusted = accessibilityCheck()
    }

    public var remaining: Int {
        get { countdown.remaining }
        set { countdown.remaining = newValue }
    }

    // MARK: - Etat affiche

    public var statusTitle: String {
        guard isRunning else { return "🖱 pause" }
        let seconds = max(remaining, 0)
        return String(format: "🖱 %02d:%02d", seconds / 60, seconds % 60)
    }

    public var startStopTitle: String {
        isRunning ? "Arrêter" : "Démarrer"
    }

    public var isCustomInterval: Bool {
        !Self.intervalPresets.contains { $0.seconds == interval }
    }

    // MARK: - Minuterie

    /// Demarre la minuterie d'une seconde (en mode `.common` pour continuer pendant que le menu est ouvert).
    public func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func tick() {
        let trusted = accessibilityCheck()
        if trusted != accessibilityTrusted { accessibilityTrusted = trusted }

        guard isRunning, !isBusy else { return }

        remaining -= 1
        if remaining <= 0 {
            triggerCycle()
            remaining = interval
        }
    }

    // MARK: - Actions

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        remaining = interval
    }

    public func stop() {
        isRunning = false
    }

    public func toggle() {
        isRunning ? stop() : start()
    }

    @discardableResult
    public func runNow() -> Bool {
        let started = triggerCycle()
        remaining = interval
        return started
    }

    @discardableResult
    public func setInterval(seconds: Int) -> Bool {
        guard seconds >= 1 else { return false }
        interval = seconds
        remaining = seconds
        config.intervalSeconds = seconds
        persist()
        return true
    }

    /// Accepte une virgule ou un point decimal. Renvoie `false` si la valeur est invalide.
    @discardableResult
    public func setCustomInterval(minutesText: String) -> Bool {
        let normalized = minutesText.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let minutes = Double(normalized), minutes.isFinite, minutes > 0,
              minutes * 60 < Double(Int32.max) else { return false }
        return setInterval(seconds: Int(minutes * 60))
    }

    public func selectDisplay(_ id: UInt32?) {
        selectedDisplayID = id
        config.displayID = id
        persist()
    }

    public func refreshDisplays() {
        let current = displayProvider.activeDisplays()
        if current != displays { displays = current }
    }

    public func setLaunchAtLogin(_ enabled: Bool) -> Result<Void, LoginItemError> {
        do {
            try loginItem.setEnabled(enabled)
            launchAtLoginEnabled = loginItem.isEnabled
            config.launchAtLogin = enabled
            persist()
            return .success(())
        } catch let error as LoginItemError {
            launchAtLoginEnabled = loginItem.isEnabled
            return .failure(error)
        } catch {
            launchAtLoginEnabled = loginItem.isEnabled
            return .failure(LoginItemError(message: error.localizedDescription))
        }
    }

    public func refreshLaunchAtLogin() {
        let enabled = loginItem.isEnabled
        if enabled != launchAtLoginEnabled { launchAtLoginEnabled = enabled }
    }

    // MARK: - Interne

    @discardableResult
    private func triggerCycle() -> Bool {
        guard !isBusy else { return false }

        let current = displayProvider.activeDisplays()
        if current != displays { displays = current }
        guard let target = DisplayCatalog.resolve(selected: selectedDisplayID, in: current) else {
            Log.core.error("Aucun ecran actif, cycle ignore.")
            return false
        }
        if let selectedDisplayID, selectedDisplayID != target.id {
            Log.core.notice("Ecran selectionne introuvable, retour a l'ecran principal.")
        }

        isBusy = true
        cycleRunner.runCycle(on: target) { [weak self] in
            self?.isBusy = false
        }
        return true
    }

    private func persist() {
        do {
            try configStore.save(config)
        } catch {
            Log.core.error("Sauvegarde de la config impossible: \(String(describing: error))")
        }
    }
}
