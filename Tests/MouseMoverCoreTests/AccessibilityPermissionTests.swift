import XCTest
@testable import MouseMoverCore

final class AccessibilityPermissionTests: XCTestCase {
    private var defaults: InMemoryDefaults!

    override func setUp() {
        defaults = InMemoryDefaults()
    }

    func testPromptsOnlyOnceWhenNotTrusted() {
        var prompts = 0
        AccessibilityPermission.requestPromptOnce(defaults: defaults, isTrusted: { false }, prompt: { prompts += 1 })
        AccessibilityPermission.requestPromptOnce(defaults: defaults, isTrusted: { false }, prompt: { prompts += 1 })
        XCTAssertEqual(prompts, 1)
    }

    func testNeverPromptsWhenAlreadyTrusted() {
        var prompts = 0
        AccessibilityPermission.requestPromptOnce(defaults: defaults, isTrusted: { true }, prompt: { prompts += 1 })
        XCTAssertEqual(prompts, 0)
    }
}
