import AppKit
import MouseMoverCore
import SwiftUI

@main
struct MouseMoverApp: App {
    @StateObject private var controller = MouseMoverController.shared

    init() {
        if let path = Self.selfTestOutputPath() {
            Self.runSelfTestAndExit(outputPath: path)
        }

        Self.terminateIfAlreadyRunning()

        let controller = MouseMoverController.shared
        controller.startTimer()

        // La migration du LaunchAgent Python n'a de sens que pour l'app installee.
        if Bundle.main.bundlePath.hasPrefix("/Applications/") {
            LegacyLaunchAgentMigrator().migrateIfNeeded()
            controller.refreshLaunchAtLogin()
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { _ in
            Task { @MainActor in MouseMoverController.shared.refreshDisplays() }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(controller: controller)
        } label: {
            Text(controller.statusTitle)
        }
        .menuBarExtraStyle(.menu)
    }

    private static func selfTestOutputPath() -> String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--self-test") else { return nil }
        return arguments.indices.contains(index + 1) ? arguments[index + 1] : "/dev/stdout"
    }

    private static func runSelfTestAndExit(outputPath: String) -> Never {
        let report = SelfTest.run()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(report) {
            try? data.write(to: URL(fileURLWithPath: outputPath))
        }
        exit(report.passed ? 0 : 1)
    }

    private static func terminateIfAlreadyRunning() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0 != NSRunningApplication.current }
        if !others.isEmpty { exit(0) }
    }
}
