import AppKit
import Combine
import MouseMoverCore
import SwiftUI

/// Fenetre « Motifs de souris ». Fenetre AppKit plutot qu'une scene `Window` : sur macOS 14,
/// une scene peut s'ouvrir toute seule au lancement d'une app de barre de menus.
@MainActor
final class PatternEditorWindow {
    static let shared = PatternEditorWindow()

    let model = PatternEditorModel()
    private var window: NSWindow?
    private var busyObserver: AnyCancellable?

    func show(selecting id: String? = nil) {
        let window = self.window ?? makeWindow()
        if let id { model.selectedID = id }
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
        window.title = "Motifs de souris"
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.center()
        window.setFrameAutosaveName("PatternEditor")
        // Pendant un cycle la souris traverse l'ecran (et clique parfois) : la fenetre ne doit pas reagir.
        busyObserver = controller.$isBusy.sink { [weak window] busy in
            window?.ignoresMouseEvents = busy
        }
        self.window = window
        return window
    }
}

@MainActor
final class PatternEditorModel: ObservableObject {
    @Published var selectedID: String? = MousePattern.classic.id
}

// MARK: - Fenetre

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
                    Text("Choisis un motif dans la liste.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 640, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minHeight: 520)
    }

    private var selectedPattern: MousePattern? {
        model.selectedID.flatMap { controller.pattern(id: $0) }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $model.selectedID) {
                Section("Intégrés") {
                    ForEach(controller.patterns.filter(\.isBuiltIn)) { row($0) }
                }
                Section("Mes motifs") {
                    ForEach(controller.customPatterns) { row($0) }
                    if controller.customPatterns.isEmpty {
                        Text("Aucun pour l'instant")
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
                .help("Nouveau motif")

                Button {
                    if let id = model.selectedID, let copy = controller.duplicatePattern(id) {
                        model.selectedID = copy.id
                    }
                } label: {
                    Image(systemName: "plus.square.on.square").frame(width: 22, height: 18)
                }
                .help("Dupliquer le motif")
                .disabled(selectedPattern == nil)

                Button { confirmDelete = true } label: {
                    Image(systemName: "minus").frame(width: 22, height: 18)
                }
                .help("Supprimer le motif")
                .disabled(selectedPattern?.isBuiltIn ?? true)

                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(6)
        }
        .confirmationDialog(
            "Supprimer « \(selectedPattern?.name ?? "") » ?", isPresented: $confirmDelete
        ) {
            Button("Supprimer", role: .destructive) {
                guard let id = model.selectedID else { return }
                controller.deletePattern(id)
                model.selectedID = controller.customPatterns.last?.id ?? MousePattern.classic.id
            }
        } message: {
            Text("Le motif sera définitivement supprimé.")
        }
    }

    private func row(_ pattern: MousePattern) -> some View {
        HStack {
            Text(pattern.name).lineLimit(1)
            Spacer()
            if controller.isPatternSelected(pattern.id) {
                Image(systemName: "checkmark")
                    .foregroundStyle(.secondary)
                    .help("Utilisé par MouseMover")
            }
        }
        .tag(pattern.id)
    }
}

// MARK: - Detail d'un motif

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
                    Text("Motif intégré : il n'est pas modifiable.")
                    Spacer()
                    Button("Dupliquer pour modifier") {
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

    // MARK: En-tete

    private var header: some View {
        HStack(spacing: 10) {
            TextField("Nom du motif", text: $draft.name)
                .textFieldStyle(.plain)
                .font(.title2.weight(.semibold))
                .disabled(!editable)

            Spacer()

            if controller.isPatternSelected(draft.id) {
                Label("Utilisé", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
            } else {
                Button("Utiliser ce motif") { controller.usePattern(draft.id) }
                    .disabled(draft.points.isEmpty)
                    .help("MouseMover jouera uniquement ce motif.")
            }

            Menu("Capturer un geste") {
                ForEach([5, 10, 15], id: \.self) { seconds in
                    Button("Pendant \(seconds) secondes") { capture(seconds: seconds) }
                }
            }
            .fixedSize()
            .help("Enregistre tes propres mouvements de souris et clics dans un nouveau motif.")

            Button {
                flushSave()
                controller.runPattern(draft)
            } label: {
                Label("Tester", systemImage: "play.fill")
            }
            .disabled(draft.points.isEmpty || controller.isBusy)
            .help("Joue le motif tout de suite (souris dans un coin pour l'interrompre).")
        }
    }

    private var options: some View {
        HStack(spacing: 16) {
            Picker("Repère", selection: $draft.anchor) {
                Text("Sur l'écran").tag(PatternAnchor.screen)
                Text("Autour du curseur").tag(PatternAnchor.cursor)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .help("Autour du curseur : le centre du cadre est la position du curseur au début du cycle.")

            Toggle("Ordre aléatoire", isOn: $draft.shuffle)
                .help("Mélange l'ordre des points à chaque cycle (sauf ceux qui gardent leur place).")
        }
        .disabled(!editable)
    }

    private var footer: String {
        let count = draft.points.count
        let base = count == 0
            ? "Clique dans le cadre pour ajouter un point, ou capture un geste."
            : "\(count) point\(count > 1 ? "s" : "") · environ \(Self.format(estimatedDuration)) s par cycle"
        return editable && count > 0 ? base + " · clic : ajouter · glisser : déplacer" : base
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

    // MARK: Inspecteur du point

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
                Text("Aucun point sélectionné").font(.headline)
                Text("Chaque point est une étape : la souris s'y rend, attend éventuellement, puis clique si demandé. Les points sont joués dans l'ordre de leur numéro.")
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

    // MARK: Sauvegarde et capture

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
                UserPrompts.show(title: "Aucun mouvement enregistré",
                                 message: "Bouge la souris après le compte à rebours pour enregistrer un geste.")
                return
            }
            model.selectedID = controller.createPattern(named: "Geste enregistré", points: pattern.points).id
        }
    }

    static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

// MARK: - Cadre de dessin

struct PatternCanvas: View {
    @Binding var points: [PatternPoint]
    @Binding var selection: Int?
    let anchor: PatternAnchor
    let aspectRatio: CGFloat
    let editable: Bool

    /// Appui en cours sur une poignee : point vise, et si le geste est un simple clic ou un glisser.
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
                        .help("Position du curseur au début du cycle")
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
                Text("\(index + 1)")
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
                Text("×\(stack.count)")
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
                        // Sur une pile de points, on garde le point deja selectionne s'il en fait partie.
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
                    // Un clic sur un point deja selectionne d'une pile passe au point suivant de la pile.
                    guard let current = press, !current.moved, current.wasSelected, current.stack.count > 1,
                          let position = current.stack.firstIndex(of: current.target) else { return }
                    selection = current.stack[(position + 1) % current.stack.count]
                })
        .help(help(for: index, stack: stack))
    }

    /// Les points dont la poignee recouvre celle de `index` (lui compris), dans l'ordre de jeu.
    private func overlapping(_ index: Int, in size: CGSize) -> [Int] {
        let center = Self.location(of: points[index], in: size)
        let limit = diameter * 0.75
        return points.indices.filter { other in
            let location = Self.location(of: points[other], in: size)
            return hypot(location.x - center.x, location.y - center.y) < limit
        }
    }

    private func help(for index: Int, stack: [Int]) -> String {
        let name = points[index].click ? "Point \(index + 1) (clic)" : "Point \(index + 1)"
        guard stack.count > 1 else { return name }
        let numbers = stack.map { String($0 + 1) }.formatted(.list(type: .and))
        return "Points \(numbers) superposés · clique encore pour passer de l'un à l'autre"
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

// MARK: - Inspecteur

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

    /// Passe d'un point a l'autre sans toucher au cadre (utile quand des points se superposent).
    private var navigation: some View {
        HStack {
            Button { select(index - 1) } label: { Image(systemName: "chevron.left") }
                .disabled(index == 0)
                .help("Point précédent")
            Spacer()
            Menu("Point \(index + 1) sur \(count)") {
                ForEach(0..<count, id: \.self) { other in
                    Button("Point \(other + 1)") { select(other) }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .font(.headline)
            Spacer()
            Button { select(index + 1) } label: { Image(systemName: "chevron.right") }
                .disabled(index == count - 1)
                .help("Point suivant")
        }
        .buttonStyle(.borderless)
    }

    private var form: some View {
        Form {
            Section("Position") {
                percentField("Horizontal", value: $point.x)
                percentField("Vertical", value: $point.y)
                Toggle("Cliquer à l'arrivée", isOn: $point.click)
                if shuffle {
                    Toggle("Garder sa place", isOn: $point.fixed)
                        .help("Ce point n'est pas mélangé avec les autres.")
                }
            }

            Section("Pause à l'arrivée") {
                Toggle("Attendre", isOn: Binding(
                    get: { point.pause != nil },
                    set: { point.pause = $0 ? PauseRange(min: 0.2, max: 0.5) : nil }))
                if let pause = point.pause {
                    secondsField("Au moins", value: Binding(
                        get: { pause.min },
                        set: { point.pause = PauseRange(min: $0, max: max($0, point.pause?.max ?? $0)) }))
                    secondsField("Au plus", value: Binding(
                        get: { pause.max },
                        set: { point.pause = PauseRange(min: min($0, point.pause?.min ?? $0), max: $0) }))
                }
            }

            Section("Trajet jusqu'au point") {
                Toggle("Durée imposée", isOn: Binding(
                    get: { point.duration != nil },
                    set: { point.duration = $0 ? 0.4 : nil }))
                if let duration = point.duration {
                    Slider(value: Binding(get: { duration }, set: { point.duration = ($0 * 100).rounded() / 100 }),
                           in: MousePattern.durationRange) {
                        Text("\(PatternDetailView.format(duration)) s")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .leading)
                    }
                    Text("Trajet en ligne droite, à vitesse constante.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Durée et courbe au hasard, comme une main.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                HStack {
                    Button { move(-1) } label: { Image(systemName: "arrow.up") }
                        .help("Jouer ce point plus tôt")
                        .disabled(index == 0)
                    Button { move(1) } label: { Image(systemName: "arrow.down") }
                        .help("Jouer ce point plus tard")
                        .disabled(index == count - 1)
                    Spacer()
                    Button("Supprimer", role: .destructive, action: delete)
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
                Text("%").foregroundStyle(.secondary)
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
                Text("s").foregroundStyle(.secondary)
            }
        }
    }
}
