import Combine
import XCTest
@testable import MouseMoverCore

@MainActor
final class ControllerTests: XCTestCase {
    private var configURL: URL!
    private var runner: FakeCycleRunner!
    private var loginItem: FakeLoginItem!
    private var displays: MutableDisplayProvider!
    private var accessibility = true

    override func setUp() async throws {
        configURL = Fixtures.tempURL()
        runner = FakeCycleRunner()
        loginItem = FakeLoginItem()
        displays = MutableDisplayProvider([Fixtures.left, Fixtures.main])
        accessibility = true
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: configURL.deletingLastPathComponent())
    }

    private func makeController(config: MouseMoverConfig? = nil) -> MouseMoverController {
        let store = ConfigStore(url: configURL)
        if let config { try? store.save(config) }
        return MouseMoverController(
            configStore: store, displayProvider: displays, cycleRunner: runner, loginItem: loginItem,
            accessibilityCheck: { [unowned self] in self.accessibility })
    }

    private func tick(_ controller: MouseMoverController, _ count: Int) {
        for _ in 0..<count { controller.tick() }
    }

    // MARK: Etat initial et titres

    func testInitialState() {
        let c = makeController()
        XCTAssertFalse(c.isRunning)
        XCTAssertEqual(c.interval, 300)
        XCTAssertEqual(c.remaining, 300)
        XCTAssertNil(c.selectedDisplayID)
        XCTAssertEqual(c.statusTitle, "🖱 pause")
        XCTAssertEqual(c.startStopTitle, "Démarrer")
        XCTAssertFalse(c.isBusy)
    }

    func testStatusTitleFormatsMinutesAndSeconds() {
        let c = makeController(config: MouseMoverConfig(intervalSeconds: 125))
        c.start()
        XCTAssertEqual(c.statusTitle, "🖱 02:05")
        XCTAssertEqual(c.startStopTitle, "Arrêter")
        tick(c, 5)
        XCTAssertEqual(c.statusTitle, "🖱 02:00")
    }

    func testLoadsPersistedConfig() {
        let c = makeController(config: MouseMoverConfig(intervalSeconds: 60, launchAtLogin: false, displayID: 2))
        XCTAssertEqual(c.interval, 60)
        XCTAssertEqual(c.selectedDisplayID, 2)
    }

    // MARK: Minuterie

    func testTickDoesNothingWhenPaused() {
        let c = makeController(config: MouseMoverConfig(intervalSeconds: 10))
        tick(c, 20)
        XCTAssertEqual(c.remaining, 10)
        XCTAssertTrue(runner.ranOn.isEmpty)
    }

    func testCycleTriggersWhenCountdownReachesZeroAndResets() {
        let c = makeController(config: MouseMoverConfig(intervalSeconds: 3))
        c.start()
        tick(c, 2)
        XCTAssertTrue(runner.ranOn.isEmpty)
        tick(c, 1)
        XCTAssertEqual(runner.ranOn.count, 1)
        XCTAssertEqual(c.remaining, 3)
        XCTAssertTrue(c.isBusy)
    }

    func testCountdownFreezesWhileBusy() {
        let c = makeController(config: MouseMoverConfig(intervalSeconds: 2))
        c.start()
        tick(c, 2)
        XCTAssertTrue(c.isBusy)
        tick(c, 10)
        XCTAssertEqual(c.remaining, 2)
        XCTAssertEqual(runner.ranOn.count, 1)
        runner.finishAll()
        XCTAssertFalse(c.isBusy)
        tick(c, 2)
        XCTAssertEqual(runner.ranOn.count, 2)
    }

    func testStartResetsCountdownAndIsIdempotent() {
        let c = makeController(config: MouseMoverConfig(intervalSeconds: 10))
        c.start()
        tick(c, 4)
        c.start()
        XCTAssertEqual(c.remaining, 6)
        c.stop()
        XCTAssertFalse(c.isRunning)
        c.toggle()
        XCTAssertTrue(c.isRunning)
        XCTAssertEqual(c.remaining, 10)
    }

    // MARK: Stabilite du menu

    /// Un menu ouvert est reconstruit a chaque notification : le timer ne doit rien publier sur le controleur.
    func testTickDoesNotNotifyMenuObservers() {
        let c = makeController(config: MouseMoverConfig(intervalSeconds: 100))
        var notifications = 0
        let cancellable = c.objectWillChange.sink { notifications += 1 }
        tick(c, 5)          // en pause
        c.start()
        let afterStart = notifications
        tick(c, 5)          // en marche : seul le compte a rebours change
        XCTAssertEqual(notifications, afterStart)
        XCTAssertEqual(c.remaining, 95)
        cancellable.cancel()
    }

    func testCountdownPublishesOnItsOwnObject() {
        let c = makeController(config: MouseMoverConfig(intervalSeconds: 100))
        c.start()
        var notifications = 0
        let cancellable = c.countdown.objectWillChange.sink { notifications += 1 }
        tick(c, 3)
        XCTAssertEqual(notifications, 3)
        cancellable.cancel()
    }

    func testRefreshesWithoutChangeDoNotNotify() {
        let c = makeController()
        var notifications = 0
        let cancellable = c.objectWillChange.sink { notifications += 1 }
        c.refreshDisplays()
        c.refreshLaunchAtLogin()
        XCTAssertEqual(notifications, 0)
        cancellable.cancel()
    }

    // MARK: Executer maintenant

    func testRunNowWorksWhenPausedAndResetsCountdown() {
        let c = makeController(config: MouseMoverConfig(intervalSeconds: 10))
        c.start()
        tick(c, 4)
        XCTAssertTrue(c.runNow())
        XCTAssertEqual(runner.ranOn.count, 1)
        XCTAssertEqual(c.remaining, 10)
        c.stop()
        runner.finishAll()
        XCTAssertTrue(c.runNow())
        XCTAssertEqual(runner.ranOn.count, 2)
    }

    func testRunNowIgnoredWhileBusy() {
        let c = makeController()
        XCTAssertTrue(c.runNow())
        XCTAssertFalse(c.runNow())
        XCTAssertEqual(runner.ranOn.count, 1)
    }

    func testRunNowWithoutDisplayDoesNothing() {
        displays.displays = []
        let c = makeController()
        XCTAssertFalse(c.runNow())
        XCTAssertFalse(c.isBusy)
    }

    // MARK: Ecrans

    func testCycleUsesSelectedDisplay() {
        let c = makeController()
        c.selectDisplay(2)
        c.runNow()
        XCTAssertEqual(runner.ranOn.last?.id, 2)
    }

    func testCycleUsesMainDisplayInAutoMode() {
        let c = makeController()
        c.runNow()
        XCTAssertEqual(runner.ranOn.last?.id, 1)
    }

    func testMissingSelectedDisplayFallsBackToMainButKeepsSelection() {
        let c = makeController(config: MouseMoverConfig(displayID: 3))
        c.runNow()
        XCTAssertEqual(runner.ranOn.last?.id, 1)
        XCTAssertEqual(c.selectedDisplayID, 3)
    }

    func testSelectDisplayPersistsAndAutoClearsIt() {
        let c = makeController()
        c.selectDisplay(2)
        XCTAssertEqual(ConfigStore(url: configURL).load().displayID, 2)
        c.selectDisplay(nil)
        XCTAssertNil(ConfigStore(url: configURL).load().displayID)
    }

    func testRefreshDisplaysPicksUpHotplug() {
        let c = makeController()
        XCTAssertEqual(c.displays.count, 2)
        displays.displays.append(Fixtures.upperLeft)
        c.refreshDisplays()
        XCTAssertEqual(c.displays.count, 3)
    }

    // MARK: Intervalle

    func testSetIntervalPersistsAndResetsCountdown() {
        let c = makeController()
        c.start()
        tick(c, 3)
        XCTAssertTrue(c.setInterval(seconds: 60))
        XCTAssertEqual(c.interval, 60)
        XCTAssertEqual(c.remaining, 60)
        XCTAssertEqual(ConfigStore(url: configURL).load().intervalSeconds, 60)
    }

    func testSetIntervalRejectsNonPositive() {
        let c = makeController()
        XCTAssertFalse(c.setInterval(seconds: 0))
        XCTAssertFalse(c.setInterval(seconds: -1))
        XCTAssertEqual(c.interval, 300)
    }

    func testCustomIntervalParsing() {
        let c = makeController()
        XCTAssertTrue(c.setCustomInterval(minutesText: "2"))
        XCTAssertEqual(c.interval, 120)
        XCTAssertTrue(c.setCustomInterval(minutesText: " 1,5 "))
        XCTAssertEqual(c.interval, 90)
        XCTAssertTrue(c.setCustomInterval(minutesText: "0.5"))
        XCTAssertEqual(c.interval, 30)
    }

    func testCustomIntervalRejectsInvalidValues() {
        let c = makeController()
        for text in ["", "abc", "0", "-3", "nan", "inf", "1e300", "0,001"] {
            XCTAssertFalse(c.setCustomInterval(minutesText: text), text)
        }
        XCTAssertEqual(c.interval, 300)
    }

    func testIsCustomInterval() {
        let c = makeController()
        XCTAssertFalse(c.isCustomInterval)
        c.setInterval(seconds: 90)
        XCTAssertTrue(c.isCustomInterval)
        c.setInterval(seconds: 600)
        XCTAssertFalse(c.isCustomInterval)
    }

    // MARK: Lancement a la connexion

    func testLaunchAtLoginSuccessIsPersisted() {
        let c = makeController()
        if case .failure(let error) = c.setLaunchAtLogin(true) { XCTFail("echec inattendu: \(error)") }
        XCTAssertTrue(c.launchAtLoginEnabled)
        XCTAssertEqual(loginItem.setCalls, [true])
        XCTAssertTrue(ConfigStore(url: configURL).load().launchAtLogin)
    }

    func testLaunchAtLoginFailureKeepsStateAndReportsError() {
        loginItem.failure = LoginItemError(message: "refuse")
        let c = makeController()
        guard case .failure(let error) = c.setLaunchAtLogin(true) else { return XCTFail("succes inattendu") }
        XCTAssertEqual(error, LoginItemError(message: "refuse"))
        XCTAssertFalse(c.launchAtLoginEnabled)
        XCTAssertFalse(ConfigStore(url: configURL).load().launchAtLogin)
    }

    func testRefreshLaunchAtLoginReflectsSystemState() {
        let c = makeController()
        loginItem.isEnabled = true
        c.refreshLaunchAtLogin()
        XCTAssertTrue(c.launchAtLoginEnabled)
    }

    // MARK: Accessibilite

    func testAccessibilityIsPolledEachTick() {
        let c = makeController()
        XCTAssertTrue(c.accessibilityTrusted)
        accessibility = false
        c.tick()
        XCTAssertFalse(c.accessibilityTrusted)
        accessibility = true
        c.tick()
        XCTAssertTrue(c.accessibilityTrusted)
    }
}
