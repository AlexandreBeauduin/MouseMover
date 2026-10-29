import XCTest
@testable import MouseMoverCore

final class MigratorTests: XCTestCase {
    private var plistURL: URL!

    override func setUpWithError() throws {
        plistURL = Fixtures.tempURL("com.pudeldoodle.mousemover.plist")
        try FileManager.default.createDirectory(
            at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: plistURL.deletingLastPathComponent())
    }

    private func createPlist() throws {
        try Data("<plist/>".utf8).write(to: plistURL)
    }

    func testNothingToMigrateWithoutPlist() {
        let loginItem = FakeLoginItem()
        var unloaded: [URL] = []
        let migrator = LegacyLaunchAgentMigrator(plistURL: plistURL, loginItem: loginItem) { unloaded.append($0) }
        XCTAssertFalse(migrator.migrateIfNeeded())
        XCTAssertTrue(loginItem.setCalls.isEmpty)
        XCTAssertTrue(unloaded.isEmpty)
    }

    func testMigrationRegistersLoginItemUnloadsAndDeletesPlist() throws {
        try createPlist()
        let loginItem = FakeLoginItem()
        var unloaded: [URL] = []
        let migrator = LegacyLaunchAgentMigrator(plistURL: plistURL, loginItem: loginItem) { unloaded.append($0) }
        XCTAssertTrue(migrator.migrateIfNeeded())
        XCTAssertEqual(loginItem.setCalls, [true])
        XCTAssertEqual(unloaded, [plistURL])
        XCTAssertFalse(FileManager.default.fileExists(atPath: plistURL.path))
    }

    func testPlistIsKeptWhenRegistrationFails() throws {
        try createPlist()
        let loginItem = FakeLoginItem()
        loginItem.failure = LoginItemError(message: "non")
        var unloaded: [URL] = []
        let migrator = LegacyLaunchAgentMigrator(plistURL: plistURL, loginItem: loginItem) { unloaded.append($0) }
        XCTAssertFalse(migrator.migrateIfNeeded())
        XCTAssertTrue(unloaded.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: plistURL.path))
    }

    func testDefaultPlistURLMatchesPythonVersion() {
        XCTAssertTrue(LegacyLaunchAgentMigrator.defaultPlistURL.path
            .hasSuffix("Library/LaunchAgents/com.pudeldoodle.mousemover.plist"))
    }
}
