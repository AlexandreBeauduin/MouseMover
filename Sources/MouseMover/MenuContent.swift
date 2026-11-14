import AppKit
import MouseMoverCore
import SwiftUI

struct MenuContent: View {
    @ObservedObject var controller: MouseMoverController

    var body: some View {
        Button(controller.startStopTitle) { controller.toggle() }
        Button("Exécuter maintenant") { controller.runNow() }

        Divider()

        Menu("Intervalle") {
            ForEach(MouseMoverController.intervalPresets, id: \.seconds) { preset in
                Toggle(preset.label, isOn: Binding(
                    get: { controller.interval == preset.seconds },
                    set: { _ in controller.setInterval(seconds: preset.seconds) }))
            }
            Toggle("Personnalisé…", isOn: Binding(
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

            Button("Gérer les motifs…") { PatternEditorWindow.shared.show() }
        }

        Menu("Écran") {
            Toggle("Suivre l'écran principal (auto)", isOn: Binding(
                get: { controller.selectedDisplayID == nil },
                set: { _ in controller.selectDisplay(nil) }))

            Divider()

            ForEach(Array(controller.displays.enumerated()), id: \.element.id) { index, display in
                Toggle(DisplayCatalog.label(for: display, index: index + 1), isOn: Binding(
                    get: { controller.selectedDisplayID == display.id },
                    set: { _ in controller.selectDisplay(display.id) }))
            }

            Divider()

            Button("Actualiser la liste des écrans") { controller.refreshDisplays() }
        }

        Divider()

        Toggle("Lancer au démarrage de session", isOn: Binding(
            get: { controller.launchAtLoginEnabled },
            set: { UserPrompts.setLaunchAtLogin($0, controller: controller) }))

        Button(controller.accessibilityTrusted
               ? "Ouvrir Réglages Accessibilité…"
               : "⚠︎ Autoriser l'Accessibilité…") {
            UserPrompts.openAccessibilitySettings()
        }

        Divider()

        Button("Quitter") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var patternMenuTitle: String {
        let selected = controller.selectedPatterns
        switch controller.patternMode {
        case .single: return "Motif : \(selected.first?.name ?? MousePattern.classic.name)"
        case .random: return "Motif : \(selected.count) au hasard"
        case .sequence: return "Motif : \(selected.count) chacun son tour"
        }
    }

    static func title(for mode: PatternMode) -> String {
        switch mode {
        case .single: "Toujours le même"
        case .random: "Au hasard parmi les cochés"
        case .sequence: "Chacun son tour"
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
        alert.messageText = "Intervalle personnalisé"
        alert.informativeText = "Durée en minutes entre deux activités :"
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Annuler")
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if !controller.setCustomInterval(minutesText: field.stringValue) {
            show(title: "Valeur invalide", message: "Entre un nombre de minutes supérieur à 0.")
        }
    }

    static func setLaunchAtLogin(_ enabled: Bool, controller: MouseMoverController) {
        if case .failure(let error) = controller.setLaunchAtLogin(enabled) {
            show(title: "Indisponible",
                 message: "Impossible de modifier le lancement au démarrage : \(error.message)")
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
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
