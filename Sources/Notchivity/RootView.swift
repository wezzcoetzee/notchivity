import NotchivityKit
import SwiftUI

/// Picks the view for the current state and draws the black shape that extends the notch.
struct RootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var geometry: NotchGeometry
    @ObservedObject private var setup: SetupModel

    init(model: AppModel, geometry: NotchGeometry) {
        self.model = model
        self.geometry = geometry
        setup = model.setup
    }

    var body: some View {
        content
            // Content fades in only after the black shape has finished growing, and vanishes
            // at once on the way back, so text never sits over a half-sized background.
            // `.id` makes the switch branch a real insertion; a transition on the bare switch never fires.
            .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.12).delay(0.2)), removal: .identity))
            .id(geometry.state)
            .foregroundStyle(.white)
            .background(UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius).fill(.black))
            .contextMenu { menu }
            .fixedSize(horizontal: false, vertical: true)
            .onHover { geometry.onHover($0) }
            .animation(.easeOut(duration: 0.22), value: geometry.state)
            .frame(width: NotchWindowController.windowSize.width, height: NotchWindowController.windowSize.height, alignment: .top)
    }

    @ViewBuilder private var content: some View {
        switch geometry.state {
        case .collapsed: CollapsedView(model: model, geometry: geometry, setup: setup)
        case .peek: PeekView(event: model.peek, geometry: geometry)
        case .expanded where setup.visible: SetupView(setup: setup, geometry: geometry)
        case .expanded: ExpandedView(model: model, geometry: geometry)
        }
    }

    private var radius: CGFloat { geometry.state == .collapsed ? 12 : 22 }

    @ViewBuilder private var menu: some View {
        Button("Refresh now") { model.refreshAll() }
        if model.peek != nil { Button("Dismiss peek") { model.dismissPeek() } }
        Button("Setup check") { setup.pinned = true; Task { await setup.run() } }
        Button("Settings…") { SettingsWindowController.shared.show(model: model) }
        Divider()
        Button("Quit Notchivity") { NSApp.terminate(nil) }
    }
}

/// The collapsed state. On a hardware notch the shape matches the notch exactly, so nothing
/// shows and nothing overlaps the menu bar; the one exception is "N to set up", which hangs
/// below the notch while first-run setup is incomplete. On other screens the black tab
/// carries the usage underline and PR indicator, each switchable in Displays settings.
struct CollapsedView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var geometry: NotchGeometry
    @ObservedObject var setup: SetupModel
    @ObservedObject private var settings = Settings.shared

    private static let setupLineHeight: CGFloat = 18
    /// Required checks still failing on first run. Silent once setup has passed, so a later
    /// outage stays on the dashboard's inline error line instead of hanging off the notch.
    private var outstanding: Int { setup.everPassed ? 0 : setup.blocking }
    private var setupLine: Bool { outstanding > 0 && !geometry.isFake }
    private var setupLabel: some View { Text("\(outstanding) to set up").foregroundStyle(Color.warn) }

    var body: some View {
        // A ZStack keeps its frame with no children; a Group would collapse to nothing on a hardware notch.
        ZStack {
            if setupLine {
                setupLabel
                    .font(.detail)
                    .frame(height: Self.setupLineHeight)
                    .padding(.top, geometry.notchHeight)
            } else if geometry.isFake {
                HStack(spacing: 10) {
                    if settings.collapsedUsage {
                        let pct = model.underlineAccount?.primaryPct
                        if let pct { Text("\(Int(pct))%").foregroundStyle(Color.usage(pct)) }
                        Bar(pct: pct, height: 2)
                    } else {
                        Spacer(minLength: 0)
                    }
                    indicator
                }
                .font(.detail)
                .padding(.horizontal, 14)
            }
        }
        .frame(width: geometry.notchWidth, height: geometry.notchHeight + (setupLine ? Self.setupLineHeight : 0))
    }

    @ViewBuilder private var indicator: some View {
        let failing = model.count(.failing), action = model.count(.needsAction)
        if outstanding > 0 {
            setupLabel.fixedSize()
        } else if model.prError != nil {
            Dot(color: .warn, size: 5)
        } else {
            switch settings.indicator {
            case .counts:
                HStack(spacing: 6) {
                    if failing > 0 { Text("\(failing)").foregroundStyle(Color.bad) }
                    if action > 0 { Text("\(action)").foregroundStyle(Color.warn) }
                    if model.prs.isEmpty, model.lastPRsAt != nil { Dot(color: .good, size: 5) }
                }
            case .dots:
                HStack(spacing: 3) {
                    ForEach(model.orderedPRs.prefix(8)) { Dot(color: .tone(for: $0.category), size: 5) }
                }
            case .none:
                EmptyView()
            }
        }
    }
}

/// A one-line drop-down for a fresh event, shown for a few seconds without hover.
struct PeekView: View {
    let event: Event?
    @ObservedObject var geometry: NotchGeometry

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Dot(color: Color(event?.tone ?? .dim), size: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(event?.headline ?? "").font(.title).lineLimit(1)
                if let detail = event?.detail {
                    Text(detail).font(.detail).foregroundStyle(Color.dim).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, geometry.notchHeight + 6)
        .padding(.bottom, 12)
        .frame(width: 440)
        .contentShape(Rectangle())
        .onTapGesture { if let url = event?.url { NSWorkspace.shared.open(url) } }
    }
}
