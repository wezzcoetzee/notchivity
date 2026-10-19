import AppKit
import NotchivityKit
import SwiftUI

/// The Settings window. Opened from the gear in the notch, Cmd-, or the right-click menu.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show(model: AppModel) {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: SettingsView.width, height: 460),
                                  styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "Notchivity Settings"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.backgroundColor = .black
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// House-style settings: black, a tab strip, plain rows separated by hairlines.
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var loginItem = LoginItemManager.shared
    @State private var tab: Tab = .general
    @State private var slack = Config.load()
    /// Transient "Saved" or "save failed" in place of the Save link.
    @State private var slackSaveStatus: String?
    @State private var newThreshold = ""

    static let width: CGFloat = 560

    enum Tab: String, CaseIterable { case general = "General", prs = "PRs", usage = "Usage", notifications = "Notifications", displays = "Displays" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabs
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch tab {
                    case .general: general
                    case .prs: prs
                    case .usage: usage
                    case .notifications: notifications
                    case .displays: displays
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
        .frame(width: Self.width, height: 460)
        .background(Color.black)
        .foregroundStyle(.white)
        .font(.bodyStrong)
        .preferredColorScheme(.dark)
    }

    private var tabs: some View {
        HStack(spacing: 18) {
            ForEach(Tab.allCases, id: \.self) { item in
                Button { tab = item } label: {
                    Text(item.rawValue)
                        .font(.body)
                        .foregroundStyle(tab == item ? .white : Color.dim)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 34)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.track).frame(height: 1) }
    }

    // MARK: Rows

    private func row<Control: View>(_ title: String, detail: String? = nil, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let detail { Text(detail).font(.detail).foregroundStyle(Color.dim) }
            }
            Spacer()
            control()
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.rule).frame(height: 1) }
    }

    private func toggle(_ title: String, detail: String? = nil, _ binding: Binding<Bool>, disabled: Bool = false) -> some View {
        row(title, detail: detail) {
            Toggle("", isOn: binding).toggleStyle(.switch).labelsHidden().controlSize(.small).tint(.white).disabled(disabled)
        }
    }

    private func segmented<Value: Hashable>(_ title: String, detail: String? = nil, _ binding: Binding<Value>,
                                            options: [(Value, String)]) -> some View {
        row(title, detail: detail) {
            HStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    Button { binding.wrappedValue = option.0 } label: {
                        Text(option.1)
                            .font(.detail)
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .background(binding.wrappedValue == option.0 ? Color.white : .clear)
                            .foregroundStyle(binding.wrappedValue == option.0 ? .black : Color.dim)
                    }
                    .buttonStyle(.plain)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.stroke))
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
    }

    private func chip<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 6, content: content)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.stroke))
            .fixedSize()
    }

    private func section(_ title: String) -> some View {
        SectionTitle(title).padding(.top, 18)
    }

    private func link(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action).buttonStyle(.plain).foregroundStyle(Color.link).font(.detail)
    }

    private func field(_ title: String, detail: String? = nil, placeholder: String, _ binding: Binding<String>, secure: Bool = false) -> some View {
        row(title, detail: detail) {
            chip {
                Group {
                    if secure { SecureField(placeholder, text: binding) } else { TextField(placeholder, text: binding) }
                }
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .frame(width: 260)
            }
        }
    }

    // MARK: General

    private var inApplications: Bool { Bundle.main.bundleURL.path.hasPrefix("/Applications/") }

    private var general: some View {
        VStack(alignment: .leading, spacing: 0) {
            toggle("Launch at login", detail: inApplications ? nil : "move the app to /Applications first",
                   Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) }), disabled: !inApplications)
            section("Slack review nudges")
            field("Channel ID", placeholder: "C0123456789", Binding(get: { slack.slackChannel ?? "" }, set: { slack.slackChannel = $0 }))
            field("Bot token", detail: "optional, falls back to claude -p", placeholder: "xoxb-…",
                  Binding(get: { slack.slackBotToken ?? "" }, set: { slack.slackBotToken = $0 }), secure: true)
            HStack {
                Spacer()
                link(slackSaveStatus ?? "Save") {
                    do { try slack.save(); slackSaveStatus = "Saved" } catch { slackSaveStatus = "save failed" }
                    Task { try? await Task.sleep(for: .seconds(2)); slackSaveStatus = nil }
                }
            }
            .padding(.top, 10)
            section("About")
            row("Setup check") { link("Run") { model.setup.pinned = true; Task { await model.setup.run() } } }
            row("Version") { Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev").foregroundStyle(Color.dim) }
            row("Quit Notchivity", detail: "removes the panel from the notch until you open the app again") {
                link("Quit") { NSApp.terminate(nil) }
            }
        }
    }

    // MARK: PRs

    private var prs: some View {
        VStack(alignment: .leading, spacing: 0) {
            row("Category order", detail: "drag to reorder, leftmost is listed first") { EmptyView() }
            CategoryOrderView(order: Binding(get: { settings.categoryOrder }, set: { settings.categoryOrder = $0 }))
            segmented("When the list is long", Binding(get: { settings.overflow }, set: { settings.overflow = $0 }),
                      options: [(.viewAll, "view all"), (.scroll, "scroll")])
            segmented("Rows before overflow", $settings.rowsBeforeOverflow, options: [4, 6, 8, 10, 12].map { ($0, "\($0)") })
            toggle("Hide drafts", $settings.hideDrafts)
            toggle("Show age", $settings.showAge)
        }
    }

    // MARK: Usage

    private var usage: some View {
        VStack(alignment: .leading, spacing: 0) {
            segmented("Account for the tab underline", $settings.underlineAccount,
                      options: [("", "first")] + model.accounts.map { ($0.id, $0.displayLabel) })
            if !model.accounts.isEmpty {
                section("Names")
                ForEach(model.accounts) { account in
                    field(account.label, detail: account.provider.name, placeholder: account.label, accountName(account.id))
                }
            }
            segmented("Poll interval", $settings.usageInterval, options: [120.0, 180.0, 300.0, 600.0].map { ($0, "\(Int($0 / 60)) min") })
            row("Notify when usage crosses", detail: "percentages, applies to session and week") { EmptyView() }
            HStack(spacing: 6) {
                ForEach(settings.thresholds, id: \.self) { value in
                    chip {
                        Text("\(Int(value))%").font(.detail)
                        Button { settings.thresholds.removeAll { $0 == value } } label: {
                            Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Color.dim)
                        }
                        .buttonStyle(.plain)
                    }
                }
                chip {
                    TextField("%", text: $newThreshold)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .font(.detail)
                        .frame(width: 34)
                        .onChange(of: newThreshold) { _, text in newThreshold = String(text.filter(\.isNumber).prefix(3)) }
                        .onSubmit(addThreshold)
                }
                Button(action: addThreshold) {
                    Image(systemName: "plus").font(.system(size: 10, weight: .bold)).frame(width: 18, height: 18)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.stroke))
                }
                .buttonStyle(.plain)
                .foregroundStyle(pendingThreshold == nil ? Color.dim : .white)
                .disabled(pendingThreshold == nil)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.rule).frame(height: 1) }
        }
    }

    /// Writes straight through so the notch shows the new name as it is typed; blank
    /// falls back to the name discovered from the sign-in.
    private func accountName(_ id: String) -> Binding<String> {
        Binding(get: { settings.accountNames[id] ?? "" },
                set: { settings.accountNames[id] = $0; model.applyAccountNames() })
    }

    /// The typed threshold, if it is a new percentage in 1...100.
    private var pendingThreshold: Double? {
        guard let value = Double(newThreshold), (1...100).contains(value), !settings.thresholds.contains(value) else { return nil }
        return value
    }

    private func addThreshold() {
        guard let value = pendingThreshold else { return }
        settings.thresholds = (settings.thresholds + [value]).sorted()
        newThreshold = ""
    }

    // MARK: Notifications

    private var notifications: some View {
        VStack(alignment: .leading, spacing: 0) {
            toggle("Peek in the notch on events", $settings.peekEnabled)
            segmented("Peek duration", $settings.peekDuration, options: [2.0, 3.0, 5.0, 8.0].map { ($0, "\(Int($0)) s") })
            section("Notification Center")
            if !Notifier.shared.available {
                Text("needs the .app bundle from make-app.sh").font(.detail).foregroundStyle(Color.dim)
            }
            ForEach(Event.Kind.allCases, id: \.self) { kind in
                toggle(kind.title, Binding(get: { settings.notifies(kind) }, set: { settings.setNotifies(kind, $0) }),
                       disabled: !Notifier.shared.available)
            }
        }
    }

    // MARK: Displays

    private var displays: some View {
        VStack(alignment: .leading, spacing: 0) {
            toggle("Show on external displays too", detail: "screens without a notch get a black tab at the top centre", $settings.externalDisplays)
            section("In the tab")
            toggle("Usage", detail: "session % and underline for the chosen account", $settings.collapsedUsage)
            segmented("PRs", Binding(get: { settings.indicator }, set: { settings.indicator = $0 }),
                      options: [(.counts, "counts"), (.dots, "dots"), (.none, "nothing")])
            segmented("Hover delay", $settings.hoverDelayMs, options: [0, 120, 250, 500].map { ($0, "\($0) ms") })
        }
    }
}

/// Drag-to-reorder chips for the PR categories. One drag gesture on the whole row (a
/// per-chip gesture dies when the reorder rebuilds the chip). Slot positions are derived
/// from measured chip widths, so the target index never flickers while frames animate.
struct CategoryOrderView: View {
    @Binding var order: [PRCategory]
    @State private var widths: [PRCategory: CGFloat] = [:]
    @State private var drag: (category: PRCategory, grabX: CGFloat)?
    @State private var pointerX: CGFloat = 0

    private let spacing: CGFloat = 6

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(order, id: \.self) { category in
                HStack(spacing: 6) {
                    Dot(color: .tone(for: category), size: 7)
                    Text(category.title).font(.detail)
                }
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Color.black)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(drag?.category == category ? Color(white: 0.5) : .stroke))
                .background(GeometryReader { geo in Color.clear.preference(key: ChipWidths.self, value: [category: geo.size.width]) })
                .offset(x: offset(for: category))
                .zIndex(drag?.category == category ? 1 : 0)
                .transaction { if drag?.category == category { $0.animation = nil } }
            }
        }
        .animation(.easeOut(duration: 0.15), value: order)
        .onPreferenceChange(ChipWidths.self) { widths = $0 }
        .contentShape(Rectangle())
        .gesture(gesture)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.rule).frame(height: 1) }
    }

    private var gesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if drag == nil {
                    guard let hit = order.first(where: { slot(of: $0).contains(value.startLocation.x) }) else { return }
                    drag = (hit, value.startLocation.x - slot(of: hit).mid)
                }
                guard let drag, let from = order.firstIndex(of: drag.category) else { return }
                pointerX = value.location.x
                let mid = pointerX - drag.grabX
                let to = order.filter { $0 != drag.category && slot(of: $0).mid < mid }.count
                if from != to { order.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to) }
            }
            .onEnded { _ in withAnimation(.easeOut(duration: 0.15)) { drag = nil } }
    }

    /// Where a chip rests in the row for the current order, from measured widths.
    private func slot(of category: PRCategory) -> (mid: CGFloat, contains: (CGFloat) -> Bool) {
        var x: CGFloat = 0
        for item in order {
            let width = widths[item] ?? 0
            if item == category { return (x + width / 2, { $0 >= x && $0 <= x + width }) }
            x += width + spacing
        }
        return (0, { _ in false })
    }

    private func offset(for category: PRCategory) -> CGFloat {
        guard let drag, drag.category == category else { return 0 }
        return pointerX - drag.grabX - slot(of: category).mid
    }
}

private struct ChipWidths: PreferenceKey {
    static let defaultValue: [PRCategory: CGFloat] = [:]
    static func reduce(value: inout [PRCategory: CGFloat], nextValue: () -> [PRCategory: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
