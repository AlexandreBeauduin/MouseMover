import XCTest
@testable import MouseMoverCore

final class ConfigTests: XCTestCase {
    private func decode(_ json: String) throws -> MouseMoverConfig {
        try JSONDecoder().decode(MouseMoverConfig.self, from: Data(json.utf8))
    }

    func testDefaults() {
        let config = MouseMoverConfig()
        XCTAssertEqual(config.intervalSeconds, 300)
        XCTAssertFalse(config.launchAtLogin)
        XCTAssertNil(config.displayID)
    }

    func testDecodesPythonFormat() throws {
        let config = try decode(#"{"interval_seconds": 60, "launch_at_login": true, "display_id": 724052222}"#)
        XCTAssertEqual(config, MouseMoverConfig(intervalSeconds: 60, launchAtLogin: true, displayID: 724052222))
    }

    func testNullAndMissingDisplayID() throws {
        XCTAssertNil(try decode(#"{"interval_seconds": 60, "display_id": null}"#).displayID)
        XCTAssertNil(try decode(#"{"interval_seconds": 60}"#).displayID)
    }

    func testFloatIntervalIsTruncated() throws {
        XCTAssertEqual(try decode(#"{"interval_seconds": 90.0}"#).intervalSeconds, 90)
        XCTAssertEqual(try decode(#"{"interval_seconds": 90.7}"#).intervalSeconds, 90)
    }

    func testInvalidIntervalFallsBackToDefault() throws {
        XCTAssertEqual(try decode(#"{"interval_seconds": 0}"#).intervalSeconds, 300)
        XCTAssertEqual(try decode(#"{"interval_seconds": -5}"#).intervalSeconds, 300)
        XCTAssertEqual(try decode(#"{"interval_seconds": "abc"}"#).intervalSeconds, 300)
        XCTAssertEqual(try decode(#"{}"#).intervalSeconds, 300)
    }

    func testWrongTypesAreIgnored() throws {
        let config = try decode(#"{"launch_at_login": "yes", "display_id": "main"}"#)
        XCTAssertFalse(config.launchAtLogin)
        XCTAssertNil(config.displayID)
    }

    func testEncodeUsesSnakeCaseAndExplicitNull() throws {
        let data = try JSONEncoder().encode(MouseMoverConfig())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["interval_seconds"] as? Int, 300)
        XCTAssertEqual(object["launch_at_login"] as? Bool, false)
        XCTAssertTrue(object.keys.contains("display_id"))
        XCTAssertTrue(object["display_id"] is NSNull)
    }

    func testStoreRoundTripCreatesDirectory() throws {
        let url = Fixtures.tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = ConfigStore(url: url)
        let config = MouseMoverConfig(intervalSeconds: 123, launchAtLogin: true, displayID: 42)
        try store.save(config)
        XCTAssertEqual(store.load(), config)
    }

    func testStoreLoadMissingFileGivesDefaults() {
        XCTAssertEqual(ConfigStore(url: Fixtures.tempURL()).load(), MouseMoverConfig())
    }

    func testStoreLoadCorruptFileGivesDefaults() throws {
        let url = Fixtures.tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("pas du json".utf8).write(to: url)
        XCTAssertEqual(ConfigStore(url: url).load(), MouseMoverConfig())
    }

    func testDefaultURLIsCompatibleWithPythonVersion() {
        XCTAssertTrue(ConfigStore.defaultURL.path.hasSuffix("Application Support/MouseMover/config.json"))
    }
}
