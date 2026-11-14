import XCTest
@testable import MouseMoverCore

@MainActor
final class ControllerPatternTests: XCTestCase {
    private var configURL: URL!
    private var runner: FakeCycleRunner!
    private var random: FakeRandom!

    override func setUp() async throws {
        configURL = Fixtures.tempURL()
        runner = FakeCycleRunner()
        random = FakeRandom()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: configURL.deletingLastPathComponent())
    }

    private func makeController(config: MouseMoverConfig? = nil) -> MouseMoverController {
        let store = ConfigStore(url: configURL)
        if let config { try? store.save(config) }
        return MouseMoverController(
            configStore: store, displayProvider: FakeDisplayProvider(displays: [Fixtures.main]),
            cycleRunner: runner, loginItem: FakeLoginItem(), accessibilityCheck: { true }, random: random)
    }

    private var saved: MouseMoverConfig { ConfigStore(url: configURL).load() }

    private func runCycles(_ c: MouseMoverController, _ count: Int) -> [String] {
        for _ in 0..<count {
            c.runNow()
            runner.finishAll()
        }
        return runner.ranPatterns.map(\.id)
    }

    private let custom = MousePattern(id: "perso", name: "Perso", points: [PatternPoint(x: 0.3, y: 0.3)])

    func testDefaultsToClassic() {
        let c = makeController()
        XCTAssertEqual(c.patternMode, .single)
        XCTAssertEqual(c.selectedPatternIDs, ["builtin.classic"])
        XCTAssertEqual(c.patterns.map(\.id), MousePattern.builtIns.map(\.id))
        XCTAssertEqual(runCycles(c, 2), ["builtin.classic", "builtin.classic"])
        XCTAssertEqual(runner.ranOn, [Fixtures.main, Fixtures.main])
    }

    func testSingleModeSelectsExactlyOne() {
        let c = makeController()
        c.togglePattern("builtin.circle")
        XCTAssertEqual(c.selectedPatternIDs, ["builtin.circle"])
        XCTAssertEqual(saved.selectedPatternIDs, ["builtin.circle"])
        XCTAssertEqual(runCycles(c, 1), ["builtin.circle"])
    }

    func testSequenceModeCyclesThroughCheckedPatterns() {
        let c = makeController()
        c.setPatternMode(.sequence)
        c.togglePattern("builtin.zigzag")
        c.togglePattern("builtin.discreet")
        XCTAssertEqual(c.selectedPatternIDs, ["builtin.classic", "builtin.zigzag", "builtin.discreet"])
        // List order, not click order.
        XCTAssertEqual(runCycles(c, 4), ["builtin.classic", "builtin.discreet", "builtin.zigzag", "builtin.classic"])
        XCTAssertEqual(saved.patternMode, .sequence)
    }

    func testRandomModeDrawsAmongChecked() {
        let c = makeController()
        c.setPatternMode(.random)
        c.togglePattern("builtin.circle")
        XCTAssertEqual(runCycles(c, 1), ["builtin.classic"])
        XCTAssertEqual(random.calls, ["choice 2"])
    }

    func testCannotUncheckLastPattern() {
        let c = makeController()
        c.setPatternMode(.random)
        c.togglePattern("builtin.classic")
        XCTAssertEqual(c.selectedPatternIDs, ["builtin.classic"])
    }

    func testSwitchingBackToSingleKeepsFirstChecked() {
        let c = makeController()
        c.setPatternMode(.random)
        c.togglePattern("builtin.circle")
        c.setPatternMode(.single)
        XCTAssertEqual(c.selectedPatternIDs, ["builtin.classic"])
    }

    func testSaveAddsThenReplacesCustomPattern() {
        let c = makeController()
        c.savePattern(custom)
        XCTAssertEqual(c.customPatterns, [custom])
        var renamed = custom
        renamed.name = "Renommé"
        c.savePattern(renamed)
        XCTAssertEqual(c.customPatterns.map(\.name), ["Renommé"])
        XCTAssertEqual(saved.patterns.map(\.name), ["Renommé"])
    }

    func testBuiltInsCannotBeSavedOrDeleted() {
        let c = makeController()
        var classic = MousePattern.classic
        classic.name = "Pirate"
        XCTAssertNil(c.savePattern(classic))
        c.deletePattern("builtin.classic")
        XCTAssertEqual(c.pattern(id: "builtin.classic"), .classic)
    }

    func testDuplicateGivesEditableCopyWithUniqueName() throws {
        let saved = L10n.language
        defer { L10n.language = saved }
        L10n.language = .fr
        let c = makeController()
        let first = try XCTUnwrap(c.duplicatePattern("builtin.circle"))
        let second = try XCTUnwrap(c.duplicatePattern("builtin.circle"))
        XCTAssertFalse(first.isBuiltIn)
        XCTAssertEqual(first.points, MousePattern.circle.points)
        XCTAssertEqual(first.name, "Cercle (copie)")
        XCTAssertEqual(second.name, "Cercle (copie) 2")
    }

    func testDeletingSelectedPatternFallsBackToClassic() {
        let c = makeController()
        c.savePattern(custom)
        c.togglePattern("perso")
        c.deletePattern("perso")
        XCTAssertEqual(c.selectedPatternIDs, ["builtin.classic"])
        XCTAssertEqual(saved.selectedPatternIDs, ["builtin.classic"])
        XCTAssertTrue(saved.patterns.isEmpty)
    }

    func testEmptySelectedPatternIsSkipped() {
        let c = makeController()
        let empty = c.createPattern()
        c.togglePattern(empty.id)
        XCTAssertEqual(runCycles(c, 1), ["builtin.classic"])
    }

    func testUnknownSavedSelectionIsRepaired() {
        let c = makeController(config: MouseMoverConfig(patternMode: .random, selectedPatternIDs: ["nope", "nope"]))
        XCTAssertEqual(c.selectedPatternIDs, ["builtin.classic"])
    }

    func testCustomPatternsSurviveRestart() {
        let c = makeController()
        c.savePattern(custom)
        c.setPatternMode(.sequence)
        c.togglePattern("perso")
        let restarted = makeController()
        XCTAssertEqual(restarted.customPatterns, [custom])
        XCTAssertEqual(restarted.patternMode, .sequence)
        XCTAssertEqual(restarted.selectedPatternIDs, ["builtin.classic", "perso"])
    }

    func testRunPatternPlaysThatPatternWithoutAdvancingSequence() {
        let c = makeController()
        c.setPatternMode(.sequence)
        c.togglePattern("builtin.circle")
        XCTAssertTrue(c.runPattern(custom))
        runner.finishAll()
        XCTAssertEqual(runCycles(c, 1), ["perso", "builtin.classic"])
    }

    func testUsePatternSwitchesToSingleMode() {
        let c = makeController()
        c.setPatternMode(.random)
        XCTAssertTrue(c.usePattern("builtin.zigzag"))
        XCTAssertEqual(c.patternMode, .single)
        XCTAssertEqual(c.selectedPatternIDs, ["builtin.zigzag"])
        XCTAssertFalse(c.usePattern("inconnu"))
    }

    func testPatternsChangedCallback() {
        let c = makeController()
        var calls = 0
        c.onPatternsChanged = { calls += 1 }
        c.savePattern(custom)
        c.savePattern(custom) // unchanged: no notification
        c.deletePattern("perso")
        XCTAssertEqual(calls, 2)
    }
}
