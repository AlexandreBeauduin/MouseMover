import AppKit
import Combine
import MouseMoverCore
import SwiftUI

/// "Mouse patterns" window. An AppKit window rather than a `Window` scene: on macOS 14 a scene
/// can open by itself when a menu bar app launches.
@MainActor
final class PatternEditorWindow {
    static let shared = PatternEditorWindow()

    let model = PatternEditorModel()
    private var window: NSWindow?
    private var observers: Set<AnyCancellable> = []

    func show(selecting id: String? = nil) {
        let window = self.window ?? makeWindow()
        if let id { model.selectedID = id }
        window.title = L10n.editorTitle
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func makeWindow() -> NSWindow {
        let controller = MouseMoverController.shared
        let hosting = NSHostingView(rootView: PatternEditorView(controller: controller, model: model))
        hosting.sizingOptions = [.minSize]
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = L10n.editorTitle
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.center()
        window.setFrameAutosaveName("PatternEditor")
        // During a cycle the mouse crosses the screen (and sometimes clicks): the window must not react.
        controller.$isBusy.sink { [weak window] busy in
            window?.ignoresMouseEvents = busy
        }.store(in: &observers)
        // @Published emits before the new language is applied: read it on the next run loop turn.
        controller.$languageChoice.receive(on: RunLoop.main).sink { [weak window] _ in
            window?.title = L10n.editorTitle
        }.store(in: &observers)
        self.window = window
        return window
    }
}

@MainActor
final class PatternEditorModel: ObservableObject {
    @Published var selectedID: String? = MousePattern.classic.id
}

// MARK: - Window

struct PatternEditorView: View {
    @ObservedObject var controller: MouseMoverController
    @ObservedObject var model: PatternEditorModel
    @State private var confirmDelete = false

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 200, idealWidth: 230, maxWidth: 320)
            Group {
                if let id = model.selectedID, let pattern = controller.pattern(id: id) {
                    PatternDetailView(controller: controller, model: model, pattern: pattern)
                        .id(pattern.id)
                } else {
                    Text(L10n.choosePattern)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 640, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minHeight: 520)
        .environment(\.locale, L10n.locale)
    }

    private var selectedPattern: MousePattern? {
        model.selectedID.flatMap { controller.pattern(id: $0) }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $model.selectedID) {
                Section(L10n.builtInSection) {
                    ForEach(controller.patterns.filter(\.isBuiltIn)) { row($0) }
                }
                Section(L10n.myPatterns) {
                    ForEach(controller.customPatterns) { row($0) }
                    if controller.customPatterns.isEmpty {
                        Text(L10n.noneYet)
                            .foregroundStyle(.secondary)
                            .selectionDisabled()
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            HStack(spacing: 2) {
                Button { model.selectedID = controller.createPattern().id } label: {
                    Image(systemName: "plus").frame(width: 22, height: 18)
                }
                .help(L10n.newPattern)

                Button {
                    if let id = model.selectedID, let copy = controller.duplicatePattern(id) {
                        model.selectedID = copy.id
                    }
                } label: {
                    Image(systemName: "plus.square.on.square").frame(width: 22, height: 18)
                }
                .help(L10n.duplicatePattern)
                .disabled(selectedPattern == nil)

                Button { confirmDelete = true } label: {
                    Image(systemName: "minus").frame(width: 22, height: 18)
                }
                .help(L10n.deletePattern)
                .disabled(selectedPattern?.isBuiltIn ?? true)

                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(6)
        }
        .confirmationDialog(
            L10n.confirmDelete(selectedPattern?.name ?? ""), isPresented: $confirmDelete
        ) {
            Button(L10n.delete, role: .destructive) {
                guard let id = model.selectedID else { return }
                controller.deletePattern(id)
                model.selectedID = controller.customPatterns.last?.id ?? MousePattern.classic.id
            }
        } message: {
            Text(L10n.deleteWarning)
        }
    }

    private func row(_ pattern: MousePattern) -> some View {
        HStack {
            Text(pattern.name).lineLimit(1)
            Spacer()
            if controller.isPatternSelected(pattern.id) {
                Image(systemName: "checkmark")
                    .foregroundStyle(.secondary)
                    .help(L10n.usedByMouseMover)
            }
        }
        .tag(pattern.id)
    }
}

// MARK: - Pattern detail

struct PatternDetailView: View {
    @ObservedObject var controller: MouseMoverController
    @ObservedObject var model: PatternEditorModel
    @State private var draft: MousePattern
    @State private var selection: Int?
    @State private var saveTask: Task<Void, Never>?

    init(controller: MouseMoverController, model: PatternEditorModel, pattern: MousePattern) {
        self.controller = controller
        self.model = model
        _draft = State(initialValue: pattern)
    }

    private var editable: Bool { !draft.isBuiltIn }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !editable {
                HStack {
                    Image(systemName: "lock.fill").foregroundStyle(.secondary)
                    Text(L10n.builtInLocked)
                    Spacer()
                    Button(L10n.duplicateToEdit) {
                        if let copy = controller.duplicatePattern(draft.id) { model.selectedID = copy.id }
                    }
                }
                .padding(8)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }
            options
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    PatternCanvas(points: $draft.points, selection: $selection, anchor: draft.anchor,
                                  aspectRatio: aspectRatio, editable: editable)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Text(footer).font(.caption).foregroundStyle(.secondary)
                }
                inspector
                    .frame(width: 250)
            }
        }
        .padding(16)
        .onChange(of: draft) { _, newValue in scheduleSave(newValue) }
        .onDisappear { flushSave() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            TextField(L10n.patternName, text: $draft.name)
                .textFieldStyle(.plain)
                .font(.title2.weight(.semibold))
                .disabled(!editable)

            Spacer()

            if controller.isPatternSelected(draft.id) {
                Label(L10n.inUse, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
            } else {
                Button(L10n.useThisPattern) { controller.usePattern(draft.id) }
                    .disabled(draft.points.isEmpty)
                    .help(L10n.useThisPatternHelp)
            }

            Menu(L10n.captureGesture) {
                ForEach([5, 10, 15], id: \.self) { seconds in
                    Button(L10n.captureFor(seconds)) { capture(seconds: seconds) }
                }
            }
            .fixedSize()
            .help(L10n.captureHelp)

            Button {
                flushSave()
                controller.runPattern(draft)
            } label: {
                Label(L10n.test, systemImage: "play.fill")
            }
            .disabled(draft.points.isEmpty || controller.isBusy)
            .help(L10n.testHelp)
        }
    }

    private var options: some View {
        HStack(spacing: 16) {
            Picker(L10n.anchor, selection: $draft.anchor) {
                Text(L10n.anchorScreen).tag(PatternAnchor.screen)
                Text(L10n.anchorCursor).tag(PatternAnchor.cursor)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .help(L10n.anchorHelp)

            Toggle(L10n.shuffle, isOn: $draft.shuffle)
                .help(L10n.shuffleHelp)
        }
        .disabled(!editable)
    }

    private var footer: String {
        let count = draft.points.count
        let base = count == 0
            ? L10n.emptyCanvasHint
            : L10n.patternSummary(points: count, seconds: Self.format(estimatedDuration))
        return editable && count > 0 ? base + L10n.canvasEditHint : base
    }

    private var estimatedDuration: Double {
        draft.points.reduce(0) { total, point in
            let move = point.duration ?? 0.365
            let pause = point.pause.map { ($0.min + $0.max) / 2 } ?? 0
            return total + move + pause + (point.click ? 0.1 : 0)
        }
    }

    private var aspectRatio: CGFloat {
        let controller = self.controller
        let display = controller.displays.first { $0.id == controller.selectedDisplayID }
            ?? controller.displays.first { $0.isMain } ?? controller.displays.first
        guard let display, display.height > 0 else { return 16 / 10 }
        return CGFloat(display.width) / CGFloat(display.height)
    }

    // MARK: Point inspector

    @ViewBuilder
    private var inspector: some View {
        if let index = selection, draft.points.indices.contains(index) {
            PointInspector(point: $draft.points[index], index: index, count: draft.points.count,
                           shuffle: draft.shuffle, editable: editable,
                           select: { selection = $0 },
                           move: { offset in movePoint(index, by: offset) },
                           delete: { deletePoint(index) })
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.noPointSelected).font(.headline)
                Text(L10n.pointsExplanation)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(12)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func movePoint(_ index: Int, by offset: Int) {
        let target = index + offset
        guard draft.points.indices.contains(target) else { return }
        draft.points.swapAt(index, target)
        selection = target
    }

    private func deletePoint(_ index: Int) {
        guard draft.points.indices.contains(index) else { return }
        draft.points.remove(at: index)
        selection = draft.points.isEmpty ? nil : min(index, draft.points.count - 1)
    }

    // MARK: Saving and capture

    private func scheduleSave(_ pattern: MousePattern) {
        guard !pattern.isBuiltIn else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            controller.savePattern(pattern)
        }
    }

    private func flushSave() {
        saveTask?.cancel()
        saveTask = nil
        if editable { controller.savePattern(draft) }
    }

    private func capture(seconds: Int) {
        flushSave()
        let controller = self.controller
        let model = self.model
        GestureCapture.shared.start(seconds: seconds) { pattern in
            PatternEditorWindow.shared.show()
            guard let pattern else { return }
            guard !pattern.points.isEmpty else {
                UserPrompts.show(title: L10n.noMovementRecorded, message: L10n.noMovementHint)
                return
            }
            model.selectedID = controller.createPattern(named: L10n.recordedGesture, points: pattern.points).id
        }
    }

    static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(L10n.locale))
    }
}

// MARK: - Canvas

struct PatternCanvas: View {
    @Binding var points: [PatternPoint]
    @Binding var selection: Int?
    let anchor: PatternAnchor
    let aspectRatio: CGFloat
    let editable: Bool

    /// Ongoing press on a handle: the target point, and whether the gesture is a plain click or a drag.
    private struct Press {
        var target: Int
        var wasSelected: Bool
        var moved: Bool
        var stack: [Int]
    }

    @State private var press: Press?

    private var dense: Bool { points.count > 40 }
    private var diameter: CGFloat { dense ? 9 : 20 }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .textBackgroundColor))
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(nsColor: .separatorColor))

                if anchor == .cursor {
                    Image(systemName: "cursorarrow")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .position(x: size.width / 2 + 4, y: size.height / 2 + 8)
                        .help(L10n.cursorStartHelp)
                }

                Path { path in
                    for (index, point) in points.enumerated() {
                        let location = Self.location(of: point, in: size)
                        index == 0 ? path.move(to: location) : path.addLine(to: location)
                    }
                }
                .stroke(Color.accentColor.opacity(0.55), style: StrokeStyle(lineWidth: 2, lineJoin: .round))

                ForEach(points.indices, id: \.self) { index in
                    if index < points.count {
                        handle(index, size: size)
                            .zIndex(selection == index ? 1 : 0)
                    }
                }
            }
            .contentShape(Rectangle())
            .coordinateSpace(name: "canvas")
            .onTapGesture(coordinateSpace: .named("canvas")) { location in
                addPoint(at: location, in: size)
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
    }

    private func handle(_ index: Int, size: CGSize) -> some View {
        let point = points[index]
        let selected = selection == index
        let stack = overlapping(index, in: size)
        return ZStack {
            Circle()
                .fill(index == 0 ? Color.green : point.click ? Color.orange : Color.accentColor)
            if selected {
                Circle().strokeBorder(Color.primary, lineWidth: 2)
            }
            if !dense {
                Text(verbatim: "\(index + 1)")
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
            }
        }
        .frame(width: diameter, height: diameter)
        .overlay(alignment: .topTrailing) {
            if point.pause != nil, !dense {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .offset(x: 6, y: -6)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if stack.count > 1, !dense {
                Text(verbatim: "×\(stack.count)")
                    .font(.system(size: 8, weight: .bold).monospacedDigit())
                    .padding(.horizontal, 3)
                    .background(Color(nsColor: .windowBackgroundColor), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor)))
                    .offset(x: 9, y: 6)
            }
        }
        .contentShape(Circle().inset(by: -4))
        .position(Self.location(of: point, in: size))
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("canvas"))
                .onChanged { value in
                    if press == nil {
                        // On a stack of points, keep the selected point if it belongs to the stack.
                        let target = selection.flatMap { stack.contains($0) ? $0 : nil } ?? index
                        press = Press(target: target, wasSelected: selection == target, moved: false, stack: stack)
                        selection = target
                    }
                    guard var current = press, editable, points.indices.contains(current.target),
                          hypot(value.translation.width, value.translation.height) > 1 else { return }
                    current.moved = true
                    press = current
                    points[current.target].x = Self.fraction(value.location.x, of: size.width)
                    points[current.target].y = Self.fraction(value.location.y, of: size.height)
                }
                .onEnded { _ in
                    defer { press = nil }
                    // Clicking the selected point of a stack moves on to the next point of the stack.
                    guard let current = press, !current.moved, current.wasSelected, current.stack.count > 1,
                          let position = current.stack.firstIndex(of: current.target) else { return }
                    selection = current.stack[(position + 1) % current.stack.count]
                })
        .help(help(for: index, stack: stack))
    }

    /// Points whose handle overlaps the handle of `index` (itself included), in playing order.
    private func overlapping(_ index: Int, in size: CGSize) -> [Int] {
        let center = Self.location(of: points[index], in: size)
        let limit = diameter * 0.75
        return points.indices.filter { other in
            let location = Self.location(of: points[other], in: size)
            return hypot(location.x - center.x, location.y - center.y) < limit
        }
    }

    private func help(for index: Int, stack: [Int]) -> String {
        let name = points[index].click ? L10n.clickPoint(index + 1) : L10n.point(index + 1)
        guard stack.count > 1 else { return name }
        return L10n.overlappingPoints(stack.map { $0 + 1 })
    }

    private func addPoint(at location: CGPoint, in size: CGSize) {
        guard editable, points.count < MousePattern.maxPoints else { return }
        let point = PatternPoint(x: Self.fraction(location.x, of: size.width),
                                 y: Self.fraction(location.y, of: size.height))
        let index = selection.map { min($0 + 1, points.count) } ?? points.count
        points.insert(point, at: index)
        selection = index
    }

    static func location(of point: PatternPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }

    static func fraction(_ value: CGFloat, of length: CGFloat) -> Double {
        guard length > 0 else { return 0.5 }
        let ratio = Double(min(max(value / length, 0), 1))
        return (ratio * 1000).rounded() / 1000
    }
}

// MARK: - Inspector

struct PointInspector: View {
    @Binding var point: PatternPoint
    let index: Int
    let count: Int
    let shuffle: Bool
    let editable: Bool
    let select: (Int) -> Void
    let move: (Int) -> Void
    let delete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            navigation
                .padding(.horizontal, 12)
                .padding(.top, 8)
            form
        }
    }

    /// Moves from point to point without touching the canvas (handy when points overlap).
    private var navigation: some View {
        HStack {
            Button { select(index - 1) } label: { Image(systemName: "chevron.left") }
                .disabled(index == 0)
                .help(L10n.previousPoint)
            Spacer()
            Menu(L10n.pointOf(index + 1, count)) {
                ForEach(0..<count, id: \.self) { other in
                    Button(L10n.point(other + 1)) { select(other) }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .font(.headline)
            Spacer()
            Button { select(index + 1) } label: { Image(systemName: "chevron.right") }
                .disabled(index == count - 1)
                .help(L10n.nextPoint)
        }
        .buttonStyle(.borderless)
    }

    private var form: some View {
        Form {
            Section(L10n.position) {
                percentField(L10n.horizontal, value: $point.x)
                percentField(L10n.vertical, value: $point.y)
                Toggle(L10n.clickOnArrival, isOn: $point.click)
                if shuffle {
                    Toggle(L10n.keepPlace, isOn: $point.fixed)
                        .help(L10n.keepPlaceHelp)
                }
            }

            Section(L10n.pauseOnArrival) {
                Toggle(L10n.wait, isOn: Binding(
                    get: { point.pause != nil },
                    set: { point.pause = $0 ? PauseRange(min: 0.2, max: 0.5) : nil }))
                if let pause = point.pause {
                    secondsField(L10n.atLeast, value: Binding(
                        get: { pause.min },
                        set: { point.pause = PauseRange(min: $0, max: max($0, point.pause?.max ?? $0)) }))
                    secondsField(L10n.atMost, value: Binding(
                        get: { pause.max },
                        set: { point.pause = PauseRange(min: min($0, point.pause?.min ?? $0), max: $0) }))
                }
            }

            Section(L10n.pathToPoint) {
                Toggle(L10n.fixedDuration, isOn: Binding(
                    get: { point.duration != nil },
                    set: { point.duration = $0 ? 0.4 : nil }))
                if let duration = point.duration {
                    Slider(value: Binding(get: { duration }, set: { point.duration = ($0 * 100).rounded() / 100 }),
                           in: MousePattern.durationRange) {
                        Text(verbatim: "\(PatternDetailView.format(duration)) s")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .leading)
                    }
                    Text(L10n.straightPath)
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(L10n.humanPath)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                HStack {
                    Button { move(-1) } label: { Image(systemName: "arrow.up") }
                        .help(L10n.playEarlier)
                        .disabled(index == 0)
                    Button { move(1) } label: { Image(systemName: "arrow.down") }
                        .help(L10n.playLater)
                        .disabled(index == count - 1)
                    Spacer()
                    Button(L10n.delete, role: .destructive, action: delete)
                }
            }
        }
        .formStyle(.grouped)
        .disabled(!editable)
    }

    private func percentField(_ title: String, value: Binding<Double>) -> some View {
        LabeledContent(title) {
            HStack(spacing: 2) {
                TextField(title, value: Binding(
                    get: { (value.wrappedValue * 1000).rounded() / 10 },
                    set: { value.wrappedValue = min(max($0, 0), 100) / 100 }),
                    format: .number.precision(.fractionLength(0...1)))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                Text(verbatim: "%").foregroundStyle(.secondary)
            }
        }
    }

    private func secondsField(_ title: String, value: Binding<Double>) -> some View {
        LabeledContent(title) {
            HStack(spacing: 2) {
                TextField(title, value: Binding(
                    get: { value.wrappedValue },
                    set: { value.wrappedValue = min(max($0, 0), MousePattern.maxPause) }),
                    format: .number.precision(.fractionLength(0...2)))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                Text(verbatim: "s").foregroundStyle(.secondary)
            }
        }
    }
}
