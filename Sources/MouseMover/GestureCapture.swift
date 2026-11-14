import AppKit
import MouseMoverCore
import SwiftUI

/// Enregistre un geste de l'utilisateur : compte a rebours, puis position du curseur a 60 Hz et clics,
/// jusqu'a la fin du temps choisi ou la touche Echap. Un bandeau flottant indique ou on en est.
@MainActor
final class GestureCapture {
    static let shared = GestureCapture()

    static let countdown: Double = 3

    private let hud = CaptureHUDModel()
    private var panel: NSPanel?
    private var timer: Timer?
    private var keyMonitors: [Any] = []
    private var clickMonitors: [Any] = []
    private var samples: [GestureSample] = []
    private var phaseStart = Date()
    private var duration: Double = 10
    private var recording = false
    private var completion: ((MousePattern?) -> Void)?

    var isActive: Bool { completion != nil }

    /// `completion` recoit `nil` si l'utilisateur annule pendant le compte a rebours.
    func start(seconds: Int, completion: @escaping (MousePattern?) -> Void) {
        guard !isActive else { return }
        self.completion = completion
        duration = Double(seconds)
        samples = []
        recording = false
        phaseStart = Date()

        PatternEditorWindow.shared.hide()
        showPanel()
        installKeyMonitors()

        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { _ in
            MainActor.assumeIsolated { GestureCapture.shared.step() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        step()
    }

    private func step() {
        let elapsed = Date().timeIntervalSince(phaseStart)
        if elapsed < Self.countdown {
            hud.update(recording: false, title: "Prépare ta souris… \(Int((Self.countdown - elapsed).rounded(.up)))",
                       detail: "Échap pour annuler")
            return
        }
        let time = elapsed - Self.countdown
        if !recording {
            recording = true
            installClickMonitors()
        }
        guard time < duration else { return finish() }
        samples.append(GestureSample(time: time, point: Self.cursor()))
        hud.update(recording: true, title: "Enregistrement… \(Int((duration - time).rounded(.up))) s",
                   detail: "Les clics sont réellement effectués · Échap pour terminer")
    }

    private func recordClick() {
        guard recording else { return }
        let time = Date().timeIntervalSince(phaseStart) - Self.countdown
        samples.append(GestureSample(time: time, point: Self.cursor(), click: true))
    }

    private func escape() {
        recording ? finish() : cancel()
    }

    private func finish() {
        let samples = self.samples
        let controller = MouseMoverController.shared
        controller.refreshDisplays()
        let displays = controller.displays
        let first = samples.first?.point ?? Self.cursor()
        let display = displays.first { $0.bounds.contains(first) }
            ?? displays.first { $0.isMain } ?? displays.first
        let pattern = display.flatMap { GestureRecorder.pattern(from: samples, in: $0.bounds) }
            ?? MousePattern(name: "Geste enregistré", points: [])
        end(with: pattern)
    }

    private func cancel() {
        end(with: nil)
    }

    private func end(with pattern: MousePattern?) {
        timer?.invalidate()
        timer = nil
        (keyMonitors + clickMonitors).forEach(NSEvent.removeMonitor)
        keyMonitors = []
        clickMonitors = []
        panel?.orderOut(nil)
        samples = []
        recording = false
        let completion = self.completion
        self.completion = nil
        completion?(pattern)
    }

    private static func cursor() -> Point {
        let location = CGEvent(source: nil)?.location ?? .zero
        return Point(x: Int(location.x.rounded()), y: Int(location.y.rounded()))
    }

    // MARK: Evenements

    private func installKeyMonitors() {
        let escapeKeyCode: UInt16 = 53
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { event in
            guard event.keyCode == escapeKeyCode else { return }
            MainActor.assumeIsolated { GestureCapture.shared.escape() }
        }) {
            keyMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            guard event.keyCode == escapeKeyCode else { return event }
            MainActor.assumeIsolated { GestureCapture.shared.escape() }
            return nil
        }) {
            keyMonitors.append(local)
        }
    }

    private func installClickMonitors() {
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { _ in
            MainActor.assumeIsolated { GestureCapture.shared.recordClick() }
        }) {
            clickMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown, handler: { event in
            MainActor.assumeIsolated { GestureCapture.shared.recordClick() }
            return event
        }) {
            clickMonitors.append(local)
        }
    }

    // MARK: Bandeau

    private func showPanel() {
        let panel = self.panel ?? makePanel()
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2,
                                         y: frame.maxY - panel.frame.height - 12))
        }
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 64),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: CaptureHUD(model: hud))
        self.panel = panel
        return panel
    }
}

@MainActor
final class CaptureHUDModel: ObservableObject {
    @Published private(set) var recording = false
    @Published private(set) var title = ""
    @Published private(set) var detail = ""

    func update(recording: Bool, title: String, detail: String) {
        if recording != self.recording { self.recording = recording }
        if title != self.title { self.title = title }
        if detail != self.detail { self.detail = detail }
    }
}

struct CaptureHUD: View {
    @ObservedObject var model: CaptureHUDModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: model.recording ? "record.circle.fill" : "timer")
                .font(.title)
                .foregroundStyle(model.recording ? Color.red : Color.secondary)
                .symbolEffect(.pulse, isActive: model.recording)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title).font(.headline.monospacedDigit())
                Text(model.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(width: 440, height: 64)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
