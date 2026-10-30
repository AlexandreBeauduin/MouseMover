import XCTest
@testable import MouseMoverCore

@MainActor
final class MouseMoverCommandTests: XCTestCase {
    private var configURL: URL!

    override func setUp() async throws {
        configURL = Fixtures.tempURL()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: configURL.deletingLastPathComponent())
    }

    private func makeController() -> (MouseMoverController, FakeCycleRunner) {
        let runner = FakeCycleRunner()
        let controller = MouseMoverController(
            configStore: ConfigStore(url: configURL), displayProvider: MutableDisplayProvider([Fixtures.main]),
            cycleRunner: runner, loginItem: FakeLoginItem(), accessibilityCheck: { true })
        return (controller, runner)
    }

    func testMatchesFrenchPhrasesWithAccents() {
        XCTAssertEqual(MouseMoverCommand(matching: "Démarre"), .start)
        XCTAssertEqual(MouseMoverCommand(matching: "reprends"), .start)
        XCTAssertEqual(MouseMoverCommand(matching: "Mets en PAUSE"), .stop)
        XCTAssertEqual(MouseMoverCommand(matching: "désactive"), .stop)
        XCTAssertEqual(MouseMoverCommand(matching: "bouge la souris"), .runNow)
    }

    func testFirstKeywordInPhraseDecides() {
        XCTAssertEqual(MouseMoverCommand(matching: "arrête le mouvement de souris"), .stop)
        XCTAssertEqual(MouseMoverCommand(matching: "active le mouvement de souris"), .start)
    }

    func testUnknownTextMatchesNothing() {
        XCTAssertNil(MouseMoverCommand(matching: "quelle heure est-il"))
        XCTAssertNil(MouseMoverCommand(matching: ""))
    }

    func testEveryCommandCanBeFoundByItsOwnTitle() {
        for command in MouseMoverCommand.allCases {
            XCTAssertEqual(MouseMoverCommand(matching: command.title), command)
        }
    }

    func testApplyDrivesController() {
        let (controller, runner) = makeController()

        XCTAssertTrue(MouseMoverCommand.start.apply(to: controller))
        XCTAssertTrue(controller.isRunning)

        XCTAssertTrue(MouseMoverCommand.stop.apply(to: controller))
        XCTAssertFalse(controller.isRunning)

        XCTAssertTrue(MouseMoverCommand.runNow.apply(to: controller))
        XCTAssertEqual(runner.ranOn.count, 1)
        XCTAssertFalse(MouseMoverCommand.runNow.apply(to: controller), "Un cycle est déjà en cours.")
    }
}
