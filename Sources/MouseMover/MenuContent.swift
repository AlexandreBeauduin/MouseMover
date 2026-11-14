import AppKit
import MouseMoverCore
import SwiftUI

struct MenuContent: View {
    @ObservedObject var controller: MouseMoverController

    var body: some View {
        Button(controller.startStopTitle) { controller.toggle() }
        Button(L10n.runNow) { controller.runNow() }

        Divider()

        Menu(L10n.interval) {
            ForEach(MouseMoverController.intervalPresets, id: \.seconds) { preset in
                Toggle(preset.label, isOn: Binding(
                    get: { controller.interval == preset.seconds },
                    set: { _ in controller.setInterval(seconds: preset.seconds) }))
            }
            Toggle(L10n.customInterval, isOn: Binding(
                get: { controller.isCustomInterval },
                set: { _ in UserPrompts.askCustomInterval(controller: controller) }))
        }

        Menu(patternMenuTitle) {
            ForEach(PatternMode.allCases, id: \.self) { mode in
                Toggle(Self.title(for: mode), isOn: Binding(
                    get: { controller.patternMode == mode },
                    set: { _ in controller.setPatternMode(mode) }))
            }

            Divider()

            ForEach(controller.patterns) { pattern in
                Toggle(pattern.name, isOn: Binding(
                    get: { controller.isPatternSelected(pattern.id) },
                    set: { _ in controller.togglePattern(pattern.id) }))
                    .disabled(pattern.points.isEmpty)
            }

            Divider()

            Button(L10n.managePatterns) { PatternEditorWindow.shared.show() }
        }

        Menu(L10n.display) {
            Toggle(L10n.followMainDisplay, isOn: Binding(
                get: { controller.selectedDisplayID == nil },
                set: { _ in controller.selectDisplay(nil) }))

            Divider()

            ForEach(Array(controller.displays.enumerated()), id: \.element.id) { index, display in
                Toggle(DisplayCatalog.label(for: display, index: index + 1), isOn: Binding(
                    get: { controller.selectedDisplayID == display.id },
                    set: { _ in controller.selectDisplay(display.id) }))
            }

            Divider()

            Button(L10n.refreshDisplays) { controller.refreshDisplays() }
        }

        Divider()

        Toggle(L10n.launchAtLogin, isOn: Binding(
            get: { controller.launchAtLoginEnabled },
            set: { UserPrompts.setLaunchAtLogin($0, controller: controller) }))

        Button(controller.accessibilityTrusted
               ? L10n.openAccessibilitySettings
               : L10n.allowAccessibility) {
            UserPrompts.openAccessibilitySettings()
        }

        Picker(L10n.languageMenu, selection: Binding(
            get: { controller.languageChoice },
            set: { controller.setLanguage($0) })) {
            Text(L10n.systemLanguage).tag("")
            ForEach(Language.allCases, id: \.rawValue) { Text($0.nativeName).tag($0.rawValue) }
        }

        Divider()

        Button(L10n.quit) { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var patternMenuTitle: String {
        let selected = controller.selectedPatterns
        switch controller.patternMode {
        case .single: return L10n.patternMenuSingle(selected.first?.name ?? MousePattern.classic.name)
        case .random: return L10n.patternMenuRandom(selected.count)
        case .sequence: return L10n.patternMenuSequence(selected.count)
        }
    }

    static func title(for mode: PatternMode) -> String {
        switch mode {
        case .single: L10n.modeSingle
        case .random: L10n.modeRandom
        case .sequence: L10n.modeSequence
        }
    }
}

@MainActor
enum UserPrompts {
    static func askCustomInterval(controller: MouseMoverController) {
        NSApp.activate(ignoringOtherApps: true)

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = String(controller.interval / 60)

        let alert = NSAlert()
        alert.messageText = L10n.customIntervalTitle
        alert.informativeText = L10n.customIntervalPrompt
        alert.accessoryView = field
        alert.addButton(withTitle: L10n.ok)
        alert.addButton(withTitle: L10n.cancel)
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if !controller.setCustomInterval(minutesText: field.stringValue) {
            show(title: L10n.invalidValue, message: L10n.invalidMinutes)
        }
    }

    static func setLaunchAtLogin(_ enabled: Bool, controller: MouseMoverController) {
        if case .failure(let error) = controller.setLaunchAtLogin(enabled) {
            show(title: L10n.unavailable, message: L10n.launchAtLoginFailed(error.message))
        }
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    static func show(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: L10n.ok)
        alert.runModal()
    }
}
