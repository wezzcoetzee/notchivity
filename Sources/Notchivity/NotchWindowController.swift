import AppKit
import Carbon.HIToolbox
import Combine
import NotchivityKit
import SwiftUI

enum NotchState: Equatable { case collapsed, peek, expanded }

/// Geometry of one screen's notch plus that panel's state, shared with its views.
@MainActor
final class NotchGeometry: ObservableObject {
    @Published var state: NotchState = .collapsed
    @Published var notchWidth: CGFloat = 200
    @Published var notchHeight: CGFloat = 37
    @Published var hovering = false
    /// True on screens without a hardware notch, where the collapsed tab is visible.
    @Published var isFake = false
    /// The visible height of this panel's screen, which bounds how far "view all" may grow.
    @Published var screenHeight: CGFloat = 900
    var onHover: (Bool) -> Void = { _ in }
    /// Called when a peek is clicked, after it has opened its URL.
    var onPeekTap: () -> Void = {}

    static let fallbackWidth: CGFloat = 200
}

/// One panel per screen. Rebuilt when screens change or the external-display setting flips.
@MainActor
final class NotchPanels {
    private let model: AppModel
    private var controllers: [NotchWindowController] = []
    private var cancellables: Set<AnyCancellable> = []
    private var hotKey: HotKey?

    init(model: AppModel) {
        self.model = model
        Settings.shared.objectWillChange
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildIfNeeded()
                self?.updateHotKey()
            }
            .store(in: &cancellables)
    }

    func show() {
        rebuild()
        updateHotKey()
    }

    private func updateHotKey() {
        if !Settings.shared.keyboardShortcut {
            hotKey = nil
        } else if hotKey == nil {
            hotKey = HotKey.controlOptionN { [weak self] in self?.toggleFromKeyboard() }
        }
    }

    /// Opens the notch on the screen under the pointer, the one being looked at.
    private func toggleFromKeyboard() {
        let mouse = NSEvent.mouseLocation
        (controllers.first { $0.screenFrame.contains(mouse) } ?? controllers.first)?.toggleFromKeyboard()
    }

    func relayout() { rebuild() }

    private var wantedScreens: [NSScreen] {
        let notched = NSScreen.screens.filter { $0.auxiliaryTopLeftArea != nil }
        if Settings.shared.externalDisplays { return NSScreen.screens }
        return notched.isEmpty ? Array(NSScreen.screens.prefix(1)) : notched
    }

    private func rebuildIfNeeded() {
        let wanted = wantedScreens.map(\.frame)
        if controllers.map(\.screenFrame) != wanted { rebuild() }
    }

    private func rebuild() {
        controllers.forEach { $0.close() }
        controllers = wantedScreens.map { NotchWindowController(model: model, screen: $0) }
        controllers.forEach { $0.show() }
    }
}

/// A borderless, non-activating, transparent panel centred on one screen's notch. The
/// window is always the size of the largest state; the black shape inside animates between
/// states so it grows out from the centre. Clicks on transparent pixels fall through.
@MainActor
final class NotchWindowController {
    private let model: AppModel
    private let screen: NSScreen
    private let geometry = NotchGeometry()
    private let panel: NotchPanel
    private var cancellables: Set<AnyCancellable> = []
    private var hoverTask: Task<Void, Never>?

    static let hoverOutDelay: Duration = .milliseconds(250)
    /// Hovering a peek waits this long before expanding, so a click on the peek lands first.
    static let peekHoverDelay = 600
    static let windowSize = NSSize(width: ExpandedView.width + 40, height: 900)

    var screenFrame: NSRect { screen.frame }

    init(model: AppModel, screen: NSScreen) {
        self.model = model
        self.screen = screen
        panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let host = NotchHostingView(rootView: RootView(model: model, geometry: geometry))
        panel.contentView = host
        host.onKey = { [weak self] event in self?.handleKey(event) ?? false }
        host.onRightClick = { [weak self] in self?.model.noteGesture(.rightClick) }
        NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification, object: panel)
            .sink { [weak self] _ in self?.keyboardLost() }
            .store(in: &cancellables)

        geometry.onHover = { [weak self] inside in self?.hoverChanged(inside) }
        // The click that opened a peek also started a hover; it should not then expand the panel.
        geometry.onPeekTap = { [weak self] in
            self?.hoverTask?.cancel()
            self?.model.dismissPeek()
        }
        model.$peek.sink { [weak self] peek in self?.peekChanged(peek) }.store(in: &cancellables)
    }

    func show() {
        layout()
        panel.orderFrontRegardless()
        if let forced = Self.forcedState {
            if forced == .peek { model.showSamplePeek() }
            geometry.state = forced
        }
    }

    func close() { panel.close() }

    /// `NOTCHIVITY_STATE=expanded|peek` pins the panel open for screenshots.
    private static var forcedState: NotchState? {
        switch ProcessInfo.processInfo.environment["NOTCHIVITY_STATE"] {
        case "expanded": return .expanded
        case "peek": return .peek
        default: return nil
        }
    }

    private func layout() {
        let centerX: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            geometry.notchWidth = right.minX - left.maxX
            geometry.notchHeight = left.height
            geometry.isFake = false
            centerX = (left.maxX + right.minX) / 2
        } else {
            geometry.notchWidth = NotchGeometry.fallbackWidth
            geometry.notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
            geometry.isFake = true
            centerX = screen.frame.midX
        }
        geometry.screenHeight = screen.visibleFrame.height
        let size = Self.windowSize
        panel.setFrame(
            NSRect(
                x: centerX - size.width / 2, y: screen.frame.maxY - size.height,
                width: size.width, height: size.height), display: true)
    }

    private func hoverChanged(_ inside: Bool) {
        guard Self.forcedState == nil else { return }
        hoverTask?.cancel()
        let inDelay = geometry.state == .peek ? max(Settings.shared.hoverDelayMs, Self.peekHoverDelay) : Settings.shared.hoverDelayMs
        let delay: Duration = inside ? .milliseconds(inDelay) : Self.hoverOutDelay
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            geometry.hovering = inside
            // The keyboard opened it, so the pointer passing through does not close it.
            if !inside, panel.acceptsKey { return }
            if inside {
                // A peek the user hovered into has been seen; replaying it on the way out would repeat it.
                if geometry.state == .peek { model.dismissPeek() }
                if geometry.state != .expanded { model.panelOpened(byKeyboard: false) }
                geometry.state = .expanded
                model.refreshIfStale()
            } else {
                collapse()
            }
        }
    }

    // MARK: Keyboard

    /// ⌃⌥N: expand and take the keyboard, or hand it back and collapse.
    func toggleFromKeyboard() {
        if panel.acceptsKey { return collapse() }
        hoverTask?.cancel()
        if geometry.state == .peek { model.dismissPeek() }
        model.panelOpened(byKeyboard: true)
        geometry.state = .expanded
        model.refreshIfStale()
        panel.acceptsKey = true
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(panel.contentView)
        if model.setup.visible { model.setup.moveFocus(by: 0) } else { model.moveFocus(by: 0) }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        // The checklist over the dashboard takes the arrows, Return and Esc for its own rows.
        if model.setup.visible {
            switch Int(event.keyCode) {
            case kVK_DownArrow: model.setup.moveFocus(by: 1)
            case kVK_UpArrow: model.setup.moveFocus(by: -1)
            case kVK_Return, kVK_ANSI_KeypadEnter: model.setup.applyFocused()
            case kVK_Escape: model.setup.close()
            default: return false
            }
            return true
        }
        switch Int(event.keyCode) {
        // Esc first cancels a keyboard ask still in its undo window, then closes.
        case kVK_Escape: if !model.undoAsk() { collapse() }
        case kVK_DownArrow: model.moveFocus(by: 1)
        case kVK_UpArrow: model.moveFocus(by: -1)
        case kVK_Return, kVK_ANSI_KeypadEnter: model.openFocused()
        case kVK_Space: model.toggleFocusedSelection()
        case kVK_ANSI_A: model.askFromKeyboard()
        case kVK_ANSI_R: model.refreshAll()
        case kVK_ANSI_F: if let fix = model.firstFix { _ = model.setup.apply(fix) }
        case kVK_ANSI_M: showFocusedMenu()
        case kVK_ANSI_S: model.setup.pin()
        case kVK_ANSI_V: model.toggleViewAll()
        case kVK_ANSI_C: model.clearSelection()
        // ⌘, as everywhere on macOS; a bare comma works too.
        case kVK_ANSI_Comma: SettingsWindowController.shared.show(model: model)
        default: return false
        }
        return true
    }

    /// "m": the highlighted PR's right-click menu, popped up under the header beside the list.
    private func showFocusedMenu() {
        guard let items = model.focusedMenu, let view = panel.contentView else { return }
        model.noteGesture(.rightClick)
        let menu = NSMenu()
        for item in items { menu.addItem(item.map { ClosureMenuItem($0.title, $0.action) } ?? .separator()) }
        let y = geometry.notchHeight + 60
        menu.popUp(positioning: nil, at: NSPoint(x: view.bounds.midX, y: view.isFlipped ? y : view.bounds.height - y), in: view)
    }

    /// Clicking another app ends the keyboard session. Return opens PRs without activating the
    /// browser, so it does not.
    private func keyboardLost() {
        guard panel.acceptsKey else { return }
        panel.acceptsKey = false
        if !geometry.hovering { collapse() }
    }

    /// Shared by hover-out, Esc, the shortcut and losing key status.
    private func collapse() {
        // A hover queued during a keyboard session must not reopen what Esc just closed.
        hoverTask?.cancel()
        geometry.hovering = false
        if panel.acceptsKey {
            panel.acceptsKey = false
            // Ordering the key panel out returns the keyboard to the frontmost app; it comes
            // straight back as the plain, unkeyable notch.
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
        // A brush past the notch that never opened it must not cancel a pinned checklist.
        if geometry.state == .expanded { model.setup.pinned = false }
        showPeekOrCollapse(model.peek)
        model.panelClosed()
    }

    /// `$peek` publishes in willSet, so the new value comes from the sink, not from `model.peek`.
    private func peekChanged(_ peek: Event?) {
        guard !geometry.hovering, !panel.acceptsKey, Self.forcedState == nil else { return }
        showPeekOrCollapse(peek)
    }

    /// A peek's clock only starts once it is actually on screen, so one that arrives
    /// mid-hover plays when the hover ends instead of expiring unseen.
    private func showPeekOrCollapse(_ peek: Event?) {
        let wasPeeking = geometry.state == .peek
        geometry.state = peek == nil ? .collapsed : .peek
        if peek != nil { model.peekShown(restart: !wasPeeking) }
    }
}

/// Borderless panels refuse key status. This one takes it only while the keyboard has opened
/// it, so a click on the notch never pulls typing away from the frontmost app.
final class NotchPanel: NSPanel {
    var acceptsKey = false
    override var canBecomeKey: Bool { acceptsKey }
}

/// Accepts the first click without activating the app, and offers keys to the panel first.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    var onKey: (NSEvent) -> Bool = { _ in false }
    /// Told before the context menu opens, so the first-hover hint stops teaching right-click.
    var onRightClick: () -> Void = {}

    override func rightMouseDown(with event: NSEvent) {
        onRightClick()
        super.rightMouseDown(with: event)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if !onKey(event) { super.keyDown(with: event) }
    }
}

/// A menu item that runs a closure, for menus built from the shared PR actions.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, _ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func run() { handler() }
}
