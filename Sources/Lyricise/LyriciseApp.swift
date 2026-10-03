import AppKit
import LyriciseCore
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()
    var panel: PanelController?
    func application(_ application: NSApplication, open urls: [URL]) {
        guard
            urls.contains(where: { url in
                url.scheme == "lyricise" && url.host == "show" && url.user == nil && url.password == nil
                    && url.query == nil
            })
        else { return }
        panel?.show()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel?.show()
        return false
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = PanelController(store: store)
        panel?.show()
    }
}

@main struct LyriciseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private var menuIcon: NSImage {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
            let image = NSImage(contentsOf: url)
        else { return NSImage() }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = false
        return image
    }
    var body: some Scene {
        MenuBarExtra {
            Button("Show / Hide Lyrics") { delegate.panel?.toggle() }
            Button("Quick Settings…") {
                delegate.panel?.show()
                delegate.store.quickSettingsPresented = true
            }
            Button("Open Spotify") { NSWorkspace.shared.open(URL(string: "spotify:")!) }
            Button("Open Config…") { delegate.store.openConfig() }
            Button("Reload Config") { delegate.store.settings.reload() }
            if let error = delegate.store.settings.error { Text(error) }
            Divider()
            Text(delegate.store.playback.connected ? "Connected to Spotify" : "Waiting for Spotify companion")
            Divider()
            Button("Quit Lyricise", role: .destructive) { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(nsImage: menuIcon).accessibilityLabel("Lyricise")
        }
        .menuBarExtraStyle(.menu)
        Settings { EmptyView() }
    }
}

@MainActor final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor final class PanelController: NSObject, NSWindowDelegate {
    static weak var current: PanelController?
    let panel: NSPanel
    let store: Store
    init(store: Store) {
        self.store = store
        panel = FloatingPanel(
            contentRect: NSRect(x: 180, y: 180, width: store.settings.value.width, height: store.settings.value.height),
            styleMask: [.borderless, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        Self.current = self
        panel.title = "Lyricise"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.minSize = NSSize(width: 260, height: 120)
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentView = NSHostingView(rootView: LyricsView(store: store))
        panel.acceptsMouseMovedEvents = true
        panel.delegate = self
        if store.settings.value.rememberPosition {
            panel.setFrameAutosaveName("LyriciseWindow")
            panel.setFrameUsingName("LyriciseWindow")
        }
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) {
            panel.center()
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(clampToScreen),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        clampToScreen()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(updateBlur),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        observe()
    }
    @objc func clampToScreen() {
        guard
            let screen = NSScreen.screens.max(by: { a, b in
                let x = a.visibleFrame.intersection(panel.frame)
                let y = b.visibleFrame.intersection(panel.frame)
                return (x.isNull ? 0 : x.width * x.height) < (y.isNull ? 0 : y.width * y.height)
            })
        else { return }
        let bounds = screen.visibleFrame
        var frame = panel.frame
        frame.size.width = min(frame.width, bounds.width)
        frame.size.height = min(frame.height, bounds.height)
        frame.origin.x = min(max(frame.minX, bounds.minX), bounds.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, bounds.minY), bounds.maxY - frame.height)
        panel.setFrame(frame, display: true)
    }
    @objc func updateBlur() {
        WindowBlur.apply(radius: store.settings.value.blurRadius, window: panel)
    }
    func observe() {
        withObservationTracking {
            panel.level = store.settings.value.alwaysOnTop ? .floating : .normal
            panel.collectionBehavior =
                store.settings.value.allSpaces
                ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.moveToActiveSpace, .fullScreenAuxiliary]
            updateBlur()
            _ = store.settings.value
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }
    func refreshHover() {
        // Window coordinates stay stable when SwiftUI changes its subviews or opens a menu.
        let pointer = NSEvent.mouseLocation
        let frame = panel.frame
        let inside = panel.isVisible && frame.contains(pointer)
        if store.hovering != inside { store.hovering = inside }
        // AppKit's screen coordinates start at the bottom-left; controls occupy the top-left 35%.
        let controlsRegion = NSRect(
            x: frame.minX, y: frame.maxY - frame.height * 0.35,
            width: frame.width * 0.35, height: frame.height * 0.35)
        let nearControls = inside && controlsRegion.contains(pointer)
        if store.hoveringControls != nearControls { store.hoveringControls = nearControls }
    }
    func show() {
        NSApplication.shared.unhide(nil)
        panel.orderFrontRegardless()
        updateBlur()
        refreshHover()
    }
    func toggle() { panel.isVisible ? panel.orderOut(nil) : show() }
}

extension Color {
    init(hex: String) {
        let n = UInt64(hex.dropFirst(), radix: 16) ?? 0
        self.init(
            red: Double((n >> 16) & 255) / 255, green: Double((n >> 8) & 255) / 255,
            blue: Double(n & 255) / 255)
    }
}
struct LyricsView: View {
    let store: Store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var suspended = false
    @State private var hoveredLine: Int?
    private var hovering: Bool { store.hovering }
    private var headerCollapsed: Bool {
        store.settings.value.trackTitleVisibility == .hover
            && store.settings.value.artworkVisibility == .hover && !hovering
    }
    @State private var resizeStart: NSRect?
    private func setting<Value>(_ key: WritableKeyPath<AppConfig, Value>) -> Binding<Value> {
        Binding(get: { store.settings.value[keyPath: key] }, set: { store.settings.set(key, to: $0) })
    }
    var body: some View {
        ZStack {
            Color(hex: store.settings.value.background).opacity(reduceTransparency ? 1 : store.settings.value.opacity)
            VStack(alignment: .leading, spacing: 0) {
                if !headerCollapsed
                    && (store.settings.value.trackTitleVisibility != .never
                        || store.settings.value.artworkVisibility != .never)
                {
                    HStack(spacing: 12) {
                        if store.settings.value.trackTitleVisibility != .never {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(store.playback.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                Text(store.playback.artist).font(.system(size: 11)).foregroundStyle(
                                    Color(hex: store.settings.value.mutedText)
                                ).lineLimit(1)
                            }
                            .opacity(store.settings.value.trackTitleVisibility.isVisible(hovering: hovering) ? 1 : 0)
                        }
                        Spacer(minLength: 0)
                        if store.settings.value.artworkVisibility != .never, let url = store.playback.artworkURL {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Color(hex: store.settings.value.mutedText).opacity(0.15)
                            }
                            .frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 6))
                            .accessibilityLabel("Album cover")
                            .opacity(store.settings.value.artworkVisibility.isVisible(hovering: hovering) ? 1 : 0)
                        }
                    }.padding(.horizontal, store.settings.value.padding).padding(.top, 16).padding(.bottom, 10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if store.playback.lines.isEmpty || !store.playback.connected {
                    Text(store.message).font(.system(size: 14)).foregroundStyle(
                        Color(hex: store.settings.value.mutedText)
                    ).frame(maxWidth: .infinity, maxHeight: .infinity).padding()
                } else {
                    GeometryReader { geometry in
                        ScrollViewReader { proxy in
                            ScrollView(.vertical) {
                                VStack(alignment: .leading, spacing: 18) {
                                    ForEach(store.playback.lines) { line in
                                        Text(line.text.isEmpty ? "♪" : line.text)
                                            .underline(line.time != nil && hoveredLine == line.id)
                                            .font(
                                                store.settings.value.font == "SF Pro"
                                                    ? .system(size: store.settings.value.fontSize, weight: .semibold)
                                                    : .custom(store.settings.value.font, size: store.settings.value.fontSize)
                                                        .weight(
                                                            .semibold)
                                            )
                                            .foregroundStyle(
                                                Color(
                                                    hex: line.id == store.playback.active
                                                        ? store.settings.value.accent : store.settings.value.text
                                                ).opacity(
                                                    line.id == store.playback.active || line.time == nil ? 1 : 0.32)
                                            )
                                            .fixedSize(horizontal: false, vertical: true)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .contentShape(Rectangle())
                                            .pointerStyle(line.time == nil ? .default : .link)
                                            .onHover { inside in
                                                if inside {
                                                    hoveredLine = line.id
                                                } else if hoveredLine == line.id {
                                                    hoveredLine = nil
                                                }
                                            }
                                            .onTapGesture {
                                                if line.time != nil {
                                                    suspended = false
                                                    store.seek(to: line)
                                                }
                                            }
                                            .help(line.time == nil ? "Untimed lyric" : "Play from this line")
                                            .id(line.id)
                                    }
                                }.padding(.horizontal, store.settings.value.padding)
                                    .padding(
                                        .vertical,
                                        !suspended && store.settings.value.followPlayback
                                            && store.playback.lines.contains(where: { $0.time != nil })
                                            ? geometry.size.height / 2 : 12)
                            }
                            .scrollIndicators(.hidden)
                            .onScrollPhaseChange { _, phase in
                                if phase == .interacting { suspended = true }
                            }
                            .onChange(of: store.playback.recenter) { _, _ in
                                if store.settings.value.followPlayback, !suspended, let id = store.playback.active {
                                    proxy.scrollTo(id, anchor: .center)
                                }
                            }
                            .onChange(of: store.settings.value) { _, _ in
                                if store.settings.value.followPlayback, !suspended, let id = store.playback.active {
                                    proxy.scrollTo(id, anchor: .center)
                                }
                            }
                            .overlay(alignment: .bottom) {
                                if suspended && store.settings.value.followPlayback && store.playback.active != nil {
                                    Button("Back to current line") {
                                        suspended = false
                                        if let id = store.playback.active { proxy.scrollTo(id, anchor: .center) }
                                    }.buttonStyle(.bordered).controlSize(.small).padding(.bottom, 10)
                                }
                            }
                            .onChange(of: store.playback.active) { _, id in
                                guard store.settings.value.followPlayback, !suspended, let id else { return }
                                withAnimation(
                                    reduceMotion || !store.playback.animateLine ? nil : .easeInOut(duration: 0.3)
                                ) { proxy.scrollTo(id, anchor: .center) }
                            }
                            .onChange(of: geometry.size) { _, _ in
                                if store.settings.value.followPlayback, !suspended, let id = store.playback.active {
                                    proxy.scrollTo(id, anchor: .center)
                                }
                            }
                            .onAppear {
                                if store.settings.value.followPlayback, let id = store.playback.active {
                                    proxy.scrollTo(id, anchor: .center)
                                }
                            }
                            .mask(
                                LinearGradient(
                                    stops: [
                                        .init(color: .clear, location: 0),
                                        .init(color: .black, location: 0.16),
                                        .init(color: .black, location: 0.84),
                                        .init(color: .clear, location: 1),
                                    ], startPoint: .top, endPoint: .bottom))
                        }
                    }
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: headerCollapsed)
        }
        .overlay(alignment: .topLeading) {
            HStack(spacing: 6) {
                Button {
                    PanelController.current?.toggle()
                } label: {
                    Image(systemName: "xmark").font(.system(size: 7, weight: .bold)).foregroundStyle(
                        .black.opacity(0.65)
                    )
                    .frame(width: 13, height: 13).background(
                        Color(red: 1, green: 0.37, blue: 0.34), in: Circle())
                }.help("Hide Lyricise")
                Button {
                    store.quickSettingsPresented.toggle()
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 9, weight: .bold))
                        .frame(width: 13, height: 13).contentShape(Rectangle())
                }.help("Quick settings")
                    .popover(
                        isPresented: Binding(
                            get: { store.quickSettingsPresented }, set: { store.quickSettingsPresented = $0 }),
                        arrowEdge: .top
                    ) {
                        QuickSettingsView(store: store)
                    }
            }.buttonStyle(.plain).padding(5)
                .background(Color(hex: store.settings.value.background).opacity(0.95), in: Capsule())
                .padding(5)
                .opacity(store.hoveringControls ? 1 : 0)
                .allowsHitTesting(store.hoveringControls)
                .accessibilityHidden(!store.hoveringControls)
        }
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 9))
                .accessibilityLabel("Resize window")
                .foregroundStyle(Color(hex: store.settings.value.mutedText)).opacity(hovering ? 0.8 : 0.25)
                .frame(width: 22, height: 22).contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { value in
                        guard let panel = PanelController.current?.panel else { return }
                        if resizeStart == nil { resizeStart = panel.frame }
                        guard let start = resizeStart else { return }
                        let width = max(panel.minSize.width, start.width + value.translation.width)
                        let height = max(panel.minSize.height, start.height + value.translation.height)
                        panel.setFrame(
                            NSRect(x: start.minX, y: start.maxY - height, width: width, height: height),
                            display: true)
                    }.onEnded { _ in resizeStart = nil }
                )
                .padding(3)
        }
        .contextMenu { commonSettings }
        .onChange(of: store.playback.trackID) { _, _ in
            suspended = false
            hoveredLine = nil
        }.contentShape(Rectangle()).gesture(WindowDragGesture()).allowsWindowActivationEvents()
        .ignoresSafeArea().foregroundStyle(Color(hex: store.settings.value.text)).clipShape(
            RoundedRectangle(cornerRadius: store.settings.value.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: store.settings.value.cornerRadius)
                .strokeBorder(Color(hex: store.settings.value.borderColor), lineWidth: store.settings.value.borderWidth)
                .allowsHitTesting(false)
        }
    }
    @ViewBuilder private var commonSettings: some View {
        Button("Quick Settings…") { store.quickSettingsPresented = true }
        Divider()
        Toggle("Always on Top", isOn: setting(\.alwaysOnTop))
        Toggle("Show on All Spaces", isOn: setting(\.allSpaces))
        Divider()
        Picker(
            "Blur Intensity",
            selection: Binding(get: { store.settings.value.blurRadius }, set: { store.settings.set(\.blurRadius, to: $0) })
        ) {
            Text("Off").tag(0)
            Text("Light · 10").tag(10)
            Text("Medium · 20").tag(20)
            Text("Strong · 40").tag(40)
            Text("Heavy · 60").tag(60)
            if ![0, 10, 20, 40, 60].contains(store.settings.value.blurRadius) {
                Text("Custom · \(store.settings.value.blurRadius)").tag(store.settings.value.blurRadius)
            }
        }
        VisibilityPicker(title: "Song details", selection: setting(\.trackTitleVisibility))
        VisibilityPicker(title: "Album cover", selection: setting(\.artworkVisibility))
        Toggle("Follow Current Lyric", isOn: setting(\.followPlayback))
        Divider()
        Button("Open Config…") { store.openConfig() }
        Button("Hide Window") { PanelController.current?.toggle() }
    }
}
