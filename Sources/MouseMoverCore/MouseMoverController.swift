import ApplicationServices
import Combine
import Foundation

@MainActor
public protocol CycleRunning: AnyObject {
    /// Joue `pattern` sur l'ecran donne puis appelle `completion` (sur le main actor) une fois termine.
    /// `displays` (tous les ecrans actifs) sert aux motifs centres sur le curseur.
    func runCycle(_ pattern: MousePattern, on display: DisplayInfo, displays: [DisplayInfo],
                  completion: @escaping @MainActor () -> Void)
}

@MainActor
public final class SystemCycleRunner: CycleRunning {
    public nonisolated init() {}

    public func runCycle(_ pattern: MousePattern, on display: DisplayInfo, displays: [DisplayInfo],
                         completion: @escaping @MainActor () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let cycle = ActivityCycle(driver: CGMouseDriver(), random: SystemRandom())
            _ = cycle.run(pattern, on: display, displays: displays)
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
    /// Motifs integres puis motifs de l'utilisateur.
    @Published public private(set) var patterns: [MousePattern]
    @Published public private(set) var patternMode: PatternMode
    @Published public private(set) var selectedPatternIDs: [String]

    private var config: MouseMoverConfig
    private let configStore: ConfigStore
    private let displayProvider: DisplayProviding
    private let cycleRunner: CycleRunning
    private let loginItem: LoginItemManaging
    private let accessibilityCheck: () -> Bool
    private let random: RandomSource
    private var timer: Timer?
    private var sequenceIndex = 0
    /// Appele apres chaque changement de la liste des motifs (ex. : rafraichir les parametres Siri).
    public var onPatternsChanged: (() -> Void)?

    public init(configStore: ConfigStore = ConfigStore(),
                displayProvider: DisplayProviding = SystemDisplayProvider(),
                cycleRunner: CycleRunning = SystemCycleRunner(),
                loginItem: LoginItemManaging = SystemLoginItem(),
                accessibilityCheck: @escaping () -> Bool = { AXIsProcessTrusted() },
                random: RandomSource = SystemRandom()) {
        let config = configStore.load()
        self.config = config
        self.configStore = configStore
        self.displayProvider = displayProvider
        self.cycleRunner = cycleRunner
        self.loginItem = loginItem
        self.accessibilityCheck = accessibilityCheck
        self.random = random

        self.interval = config.intervalSeconds
        self.countdown = CountdownState(remaining: config.intervalSeconds)
        self.selectedDisplayID = config.displayID
        self.displays = displayProvider.activeDisplays()
        self.launchAtLoginEnabled = loginItem.isEnabled
        self.accessibilityTrusted = accessibilityCheck()

        let all = MousePattern.builtIns + config.patterns
        self.patterns = all
        self.patternMode = config.patternMode
        self.selectedPatternIDs = Self.validSelection(config.selectedPatternIDs, mode: config.patternMode, in: all)
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

    // MARK: - Motifs

    public func pattern(id: String) -> MousePattern? {
        patterns.first { $0.id == id }
    }

    public var customPatterns: [MousePattern] {
        patterns.filter { !$0.isBuiltIn }
    }

    public func isPatternSelected(_ id: String) -> Bool {
        selectedPatternIDs.contains(id)
    }

    /// Motifs coches, dans l'ordre de la liste.
    public var selectedPatterns: [MousePattern] {
        patterns.filter { selectedPatternIDs.contains($0.id) }
    }

    public func setPatternMode(_ mode: PatternMode) {
        guard mode != patternMode else { return }
        patternMode = mode
        sequenceIndex = 0
        updateSelection(selectedPatternIDs)
    }

    /// Mode « un seul » : choisit ce motif. Autres modes : le coche ou le decoche (au moins un reste coche).
    public func togglePattern(_ id: String) {
        guard pattern(id: id) != nil else { return }
        if patternMode == .single {
            updateSelection([id])
        } else if isPatternSelected(id) {
            guard selectedPatternIDs.count > 1 else { return }
            updateSelection(selectedPatternIDs.filter { $0 != id })
        } else {
            updateSelection(selectedPatternIDs + [id])
        }
    }

    /// Joue uniquement ce motif desormais (mode « un seul »).
    @discardableResult
    public func usePattern(_ id: String) -> Bool {
        guard pattern(id: id) != nil else { return false }
        patternMode = .single
        sequenceIndex = 0
        updateSelection([id])
        return true
    }

    /// Ajoute ou remplace un motif de l'utilisateur. Les motifs integres ne sont pas modifiables.
    @discardableResult
    public func savePattern(_ pattern: MousePattern) -> MousePattern? {
        guard !pattern.isBuiltIn else { return nil }
        let clean = pattern.sanitized()
        var custom = customPatterns
        if let index = custom.firstIndex(where: { $0.id == clean.id }) {
            guard custom[index] != clean else { return clean }
            custom[index] = clean
        } else {
            custom.append(clean)
        }
        updatePatterns(custom)
        return clean
    }

    /// Copie modifiable d'un motif (integre ou non), ajoutee a la liste.
    @discardableResult
    public func duplicatePattern(_ id: String) -> MousePattern? {
        guard let source = pattern(id: id) else { return nil }
        var copy = source
        copy.id = UUID().uuidString
        copy.name = uniqueName(base: "\(source.name) (copie)")
        return savePattern(copy)
    }

    /// Nouveau motif (vide par defaut, a remplir dans l'editeur), avec un nom unique.
    @discardableResult
    public func createPattern(named base: String = "Nouveau motif", points: [PatternPoint] = []) -> MousePattern {
        let pattern = MousePattern(name: uniqueName(base: base), points: points)
        return savePattern(pattern) ?? pattern
    }

    public func deletePattern(_ id: String) {
        guard let target = pattern(id: id), !target.isBuiltIn else { return }
        updatePatterns(customPatterns.filter { $0.id != id })
    }

    /// Motif a jouer au prochain cycle, selon le mode.
    public func nextPattern() -> MousePattern {
        let candidates = selectedPatterns.filter { !$0.points.isEmpty }
        guard !candidates.isEmpty else { return .classic }
        switch patternMode {
        case .single:
            return candidates[0]
        case .random:
            return candidates.count == 1 ? candidates[0] : random.choice(candidates)
        case .sequence:
            let pattern = candidates[sequenceIndex % candidates.count]
            sequenceIndex = (sequenceIndex + 1) % candidates.count
            return pattern
        }
    }

    /// Joue tout de suite un motif precis (bouton « Tester » de l'editeur), sans toucher au compte a rebours.
    @discardableResult
    public func runPattern(_ pattern: MousePattern) -> Bool {
        triggerCycle(with: pattern.sanitized())
    }

    private func uniqueName(base: String) -> String {
        let names = Set(patterns.map(\.name))
        guard names.contains(base) else { return base }
        var n = 2
        while names.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    private func updatePatterns(_ custom: [MousePattern]) {
        patterns = MousePattern.builtIns + custom
        config.patterns = custom
        updateSelection(selectedPatternIDs, persisting: false)
        persist()
        onPatternsChanged?()
    }

    private func updateSelection(_ ids: [String], persisting: Bool = true) {
        let valid = Self.validSelection(ids, mode: patternMode, in: patterns)
        if valid != selectedPatternIDs { selectedPatternIDs = valid }
        config.patternMode = patternMode
        config.selectedPatternIDs = valid
        if persisting { persist() }
    }

    /// Ids existants, sans doublon, au moins un (le Classique par defaut), un seul en mode « un seul ».
    static func validSelection(_ ids: [String], mode: PatternMode, in patterns: [MousePattern]) -> [String] {
        let known = Set(patterns.map(\.id))
        var seen = Set<String>()
        var valid = ids.filter { known.contains($0) && seen.insert($0).inserted }
        if valid.isEmpty { valid = MouseMoverConfig.defaultPatternIDs }
        if mode == .single { valid = [valid[0]] }
        return valid
    }

    // MARK: - Interne

    @discardableResult
    private func triggerCycle(with pattern: MousePattern? = nil) -> Bool {
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
        cycleRunner.runCycle(pattern ?? nextPattern(), on: target, displays: current) { [weak self] in
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
