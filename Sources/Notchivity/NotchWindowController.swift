import AppKit
import Combine
import NotchivityKit
import SwiftUI

/// The three sizes the notch panel can take.
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
    /// Called by the views when the pointer enters or leaves the black shape.
    var onHover: (Bool) -> Void = { _ in }

    static let fallbackWidth: CGFloat = 200
}

/// One panel per screen. Rebuilt when screens change or the external-display setting flips.
@MainActor
final class NotchPanels {
    private let model: AppModel
    private var controllers: [NotchWindowController] = []
    private var cancellables: Set<AnyCancellable> = []

    init(model: AppModel) {
        self.model = model
        Settings.shared.objectWillChange
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildIfNeeded() }
            .store(in: &cancellables)
    }

    func show() { rebuild() }

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
    private let panel: NSPanel
    private var cancellables: Set<AnyCancellable> = []
    private var hoverTask: Task<Void, Never>?

    static let hoverOutDelay: Duration = .milliseconds(250)
    static let windowSize = NSSize(width: ExpandedView.width + 40, height: 900)

    var screenFrame: NSRect { screen.frame }

    init(model: AppModel, screen: NSScreen) {
        self.model = model
        self.screen = screen
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NotchHostingView(rootView: RootView(model: model, geometry: geometry))

        geometry.onHover = { [weak self] inside in self?.hoverChanged(inside) }
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
        let size = Self.windowSize
        panel.setFrame(NSRect(x: centerX - size.width / 2, y: screen.frame.maxY - size.height,
                              width: size.width, height: size.height), display: true)
    }

    private func hoverChanged(_ inside: Bool) {
        guard Self.forcedState == nil else { return }
        hoverTask?.cancel()
        let delay: Duration = inside ? .milliseconds(Settings.shared.hoverDelayMs) : Self.hoverOutDelay
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            geometry.hovering = inside
            if inside {
                geometry.state = .expanded
                model.refreshIfStale()
            } else {
                showPeekOrCollapse()
                model.showAllPRs = false
                model.selectedPRs = []
            }
        }
    }

    private func peekChanged(_ peek: Event?) {
        guard !geometry.hovering, Self.forcedState == nil else { return }
        showPeekOrCollapse()
    }

    /// A peek's clock only starts once it is actually on screen, so one that arrives
    /// mid-hover plays when the hover ends instead of expiring unseen.
    private func showPeekOrCollapse() {
        geometry.state = model.peek == nil ? .collapsed : .peek
        if geometry.state == .peek { model.peekShown() }
    }
}

/// Accepts the first click without activating the app.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
