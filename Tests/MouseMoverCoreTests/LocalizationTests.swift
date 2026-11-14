import XCTest
@testable import MouseMoverCore

@MainActor
final class LocalizationTests: XCTestCase {
    override func tearDown() {
        L10n.language = L10n.automaticLanguage
    }

    func testPicksFirstSupportedPreferredLanguage() {
        XCTAssertEqual(Language.preferred(from: ["nl-BE", "fr-FR"]), .nl)
        XCTAssertEqual(Language.preferred(from: ["ja-JP", "de_AT"]), .de)
        XCTAssertEqual(Language.preferred(from: ["fr"]), .fr)
        XCTAssertEqual(Language.preferred(from: ["ja", "zh-Hans"]), .en)
        XCTAssertEqual(Language.preferred(from: []), .en)
    }

    func testApplyChoiceFallsBackToAutomatic() {
        L10n.apply(choice: "de")
        XCTAssertEqual(L10n.language, .de)
        L10n.apply(choice: "")
        XCTAssertEqual(L10n.language, L10n.automaticLanguage)
        L10n.apply(choice: "klingon")
        XCTAssertEqual(L10n.language, L10n.automaticLanguage)
    }

    private var samples: [String] {
        [L10n.runNow, L10n.interval, L10n.managePatterns, L10n.display, L10n.launchAtLogin, L10n.quit,
         L10n.modeRandom, L10n.customIntervalPrompt, L10n.invalidMinutes, L10n.editorTitle,
         L10n.pointsExplanation, L10n.recordingDetail, L10n.patternClassic, L10n.untitledPattern,
         L10n.startedDialog, L10n.unknownPattern, L10n.patternSummary(points: 3, seconds: "2"),
         L10n.displayLabel(index: 1, width: 10, height: 10, isMain: true)]
    }

    func testEveryLanguageHasItsOwnStrings() {
        L10n.language = .en
        let english = samples
        for language in Language.allCases {
            L10n.language = language
            let strings = samples
            XCTAssertTrue(strings.allSatisfy { !$0.isEmpty }, "\(language)")
            if language != .en {
                XCTAssertNotEqual(strings, english, "\(language)")
            }
        }
    }

    func testBuiltInNamesFollowTheLanguage() {
        L10n.language = .de
        XCTAssertEqual(MousePattern.classic.name, "Klassisch")
        L10n.language = .en
        XCTAssertEqual(MousePattern.builtIns.map(\.name), ["Classic", "Discreet", "Circle", "Zigzag"])
    }

    func testPlurals() {
        L10n.language = .en
        XCTAssertTrue(L10n.patternSummary(points: 1, seconds: "1").hasPrefix("1 point ·"))
        XCTAssertTrue(L10n.patternSummary(points: 2, seconds: "1").hasPrefix("2 points ·"))
        L10n.language = .fr
        XCTAssertTrue(L10n.patternSummary(points: 1, seconds: "1").hasPrefix("1 point ·"))
        XCTAssertTrue(L10n.patternSummary(points: 0, seconds: "1").hasPrefix("0 point ·"))
    }

    func testControllerPersistsAndAppliesLanguageChoice() throws {
        let suite = "MouseMoverTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let url = Fixtures.tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let make = {
            MouseMoverController(configStore: ConfigStore(url: url),
                                 displayProvider: FakeDisplayProvider(displays: [Fixtures.main]),
                                 cycleRunner: FakeCycleRunner(), loginItem: FakeLoginItem(),
                                 accessibilityCheck: { true }, random: FakeRandom(), defaults: defaults)
        }
        let c = make()
        XCTAssertEqual(c.languageChoice, "")
        c.setLanguage("nl")
        XCTAssertEqual(L10n.language, .nl)
        XCTAssertEqual(c.pattern(id: "builtin.circle")?.name, "Cirkel")
        XCTAssertEqual(make().languageChoice, "nl")
        c.setLanguage("bogus")
        XCTAssertEqual(c.languageChoice, "")
        XCTAssertEqual(L10n.language, L10n.automaticLanguage)
    }
}
