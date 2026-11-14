import ApplicationServices
import Combine
import Foundation

@MainActor
public protocol CycleRunning: AnyObject {
    /// Plays `pattern` on the given display, then calls `completion` (on the main actor) when done.
    /// `displays` (all active displays) is used by cursor-centered patterns.
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

/// Countdown kept apart from the rest of the state: it changes every second and must only refresh the
/// menu bar title, never the open menu (otherwise submenus close).
@MainActor
public final class CountdownState: ObservableObject {
    @Published public var remaining: Int

    public init(remaining: Int) {
        self.remaining = remaining
    }
}

@MainActor
public final class MouseMoverController: ObservableObject {
    public static let intervalPresetMinutes = [1, 3, 5, 10, 15]

    public static var intervalPresets: [(label: String, seconds: Int)] {
        intervalPresetMinutes.map { (L10n.minutesShort($0), $0 * 60) }
    }

    public static let shared = MouseMoverController()

    @Published public private(set) var isRunning = false
    public let countdown: CountdownState
    @Published public private(set) var interval: Int
    @Published public private(set) var selectedDisplayID: UInt32?
    @Published public private(set) var displays: [DisplayInfo]
    @Published public private(set) var isBusy = false
    @Published public private(set) var launchAtLoginEnabled: Bool
    @Published public private(set) var accessibilityTrusted: Bool
    /// Built-in patterns, then the user's patterns.
    @Published public private(set) var patterns: [MousePattern]
    @Published public private(set) var patternMode: PatternMode
    @Published public private(set) var selectedPatternIDs: [String]
    /// Language menu choice: a `Language` raw value, or "" to follow the system.
    @Published public private(set) var languageChoice: String

    private var config: MouseMoverConfig
    private let configStore: ConfigStore
    private let displayProvider: DisplayProviding
    private let cycleRunner: CycleRunning
    private let loginItem: LoginItemManaging
    private let accessibilityCheck: () -> Bool
    private let random: RandomSource
    private let defaults: UserDefaults
    static let languageKey = "language"
    private var timer: Timer?
    private var sequenceIndex = 0
    /// Called after every change to the pattern list (e.g. to refresh the App Shortcuts parameters).
    public var onPatternsChanged: (() -> Void)?

    public init(configStore: ConfigStore = ConfigStore(),
                displayProvider: DisplayProviding = SystemDisplayProvider(),
                cycleRunner: CycleRunning = SystemCycleRunner(),
                loginItem: LoginItemManaging = SystemLoginItem(),
                accessibilityCheck: @escaping () -> Bool = { AXIsProcessTrusted() },
                random: RandomSource = SystemRandom(),
                defaults: UserDefaults = .standard) {
        let config = configStore.load()
        self.config = config
        self.configStore = configStore
        self.displayProvider = displayProvider
        self.cycleRunner = cycleRunner
        self.loginItem = loginItem
        self.accessibilityCheck = accessibilityCheck
        self.random = random
        self.defaults = defaults
        self.languageChoice = defaults.string(forKey: Self.languageKey) ?? ""

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

    // MARK: - Displayed state

    public var statusTitle: String {
        guard isRunning else { return "🖱 \(L10n.paused)" }
        let seconds = max(remaining, 0)
        return String(format: "🖱 %02d:%02d", seconds / 60, seconds % 60)
    }

    public var startStopTitle: String {
        isRunning ? L10n.stop : L10n.start
    }

    public var isCustomInterval: Bool {
        !Self.intervalPresets.contains { $0.seconds == interval }
    }

    // MARK: - Timer

    /// Starts the one-second timer (in `.common` mode so it keeps running while the menu is open).
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

    /// Accepts a decimal comma or point. Returns `false` if the value is invalid.
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

    // MARK: - Patterns

    public func pattern(id: String) -> MousePattern? {
        patterns.first { $0.id == id }
    }

    public var customPatterns: [MousePattern] {
        patterns.filter { !$0.isBuiltIn }
    }

    public func isPatternSelected(_ id: String) -> Bool {
        selectedPatternIDs.contains(id)
    }

    /// Checked patterns, in list order.
    public var selectedPatterns: [MousePattern] {
        patterns.filter { selectedPatternIDs.contains($0.id) }
    }

    public func setPatternMode(_ mode: PatternMode) {
        guard mode != patternMode else { return }
        patternMode = mode
        sequenceIndex = 0
        updateSelection(selectedPatternIDs)
    }

    /// Single mode: selects this pattern. Other modes: checks or unchecks it (at least one stays checked).
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

    /// From now on, plays only this pattern (single mode).
    @discardableResult
    public func usePattern(_ id: String) -> Bool {
        guard pattern(id: id) != nil else { return false }
        patternMode = .single
        sequenceIndex = 0
        updateSelection([id])
        return true
    }

    /// Adds or replaces a user pattern. Built-in patterns cannot be changed.
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

    /// Editable copy of a pattern (built-in or not), added to the list.
    @discardableResult
    public func duplicatePattern(_ id: String) -> MousePattern? {
        guard let source = pattern(id: id) else { return nil }
        var copy = source
        copy.id = UUID().uuidString
        copy.name = uniqueName(base: L10n.copyName(source.name))
        return savePattern(copy)
    }

    /// New pattern (empty by default, to fill in the editor), with a unique name.
    @discardableResult
    public func createPattern(named base: String = L10n.newPattern, points: [PatternPoint] = []) -> MousePattern {
        let pattern = MousePattern(name: uniqueName(base: base), points: points)
        return savePattern(pattern) ?? pattern
    }

    public func deletePattern(_ id: String) {
        guard let target = pattern(id: id), !target.isBuiltIn else { return }
        updatePatterns(customPatterns.filter { $0.id != id })
    }

    /// Pattern to play on the next cycle, depending on the mode.
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

    /// Plays a given pattern right away (the editor's Test button), without touching the countdown.
    @discardableResult
    public func runPattern(_ pattern: MousePattern) -> Bool {
        triggerCycle(with: pattern.sanitized())
    }

    // MARK: - Language

    /// Applies the stored Language menu choice (call once at launch).
    public func applyLanguageChoice() {
        L10n.apply(choice: languageChoice)
        refreshLocalizedNames()
    }

    public func setLanguage(_ choice: String) {
        let choice = Language(rawValue: choice)?.rawValue ?? ""
        languageChoice = choice
        defaults.set(choice, forKey: Self.languageKey)
        applyLanguageChoice()
    }

    /// Re-reads the built-in patterns after a language change (their names are localized).
    public func refreshLocalizedNames() {
        patterns = MousePattern.builtIns + customPatterns
        onPatternsChanged?()
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

    /// Existing ids, no duplicates, at least one (Classic by default), only one in single mode.
    static func validSelection(_ ids: [String], mode: PatternMode, in patterns: [MousePattern]) -> [String] {
        let known = Set(patterns.map(\.id))
        var seen = Set<String>()
        var valid = ids.filter { known.contains($0) && seen.insert($0).inserted }
        if valid.isEmpty { valid = MouseMoverConfig.defaultPatternIDs }
        if mode == .single { valid = [valid[0]] }
        return valid
    }

    // MARK: - Internal

    @discardableResult
    private func triggerCycle(with pattern: MousePattern? = nil) -> Bool {
        guard !isBusy else { return false }

        let current = displayProvider.activeDisplays()
        if current != displays { displays = current }
        guard let target = DisplayCatalog.resolve(selected: selectedDisplayID, in: current) else {
            Log.core.error("No active display, cycle skipped.")
            return false
        }
        if let selectedDisplayID, selectedDisplayID != target.id {
            Log.core.notice("Selected display not found, using the main display.")
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
            Log.core.error("Could not save the config: \(String(describing: error))")
        }
    }
}
