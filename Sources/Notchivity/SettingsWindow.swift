import AppKit
import NotchivityKit
import SwiftUI

/// The Settings window. Opened from the gear in the notch or the right-click menu. (Cmd-, only
/// works once it is open: the app is an accessory and the notch panel never activates it.)
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?
    private let navigation = SettingsNavigation()

    /// `tab` jumps to a tab (the setup check's Slack fix lands on General); nil keeps the last one.
    func show(model: AppModel, tab: SettingsView.Tab? = nil) {
        if let tab { navigation.tab = tab }
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: SettingsView.width, height: SettingsView.height),
                styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "Notchivity Settings"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.backgroundColor = .black
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(model: model, navigation: navigation))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// The selected tab, outside the view so callers can open Settings on a given tab.
@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var tab: SettingsView.Tab
    init(tab: SettingsView.Tab = .general) { self.tab = tab }
}

/// House-style settings: black, a tab strip, plain rows separated by hairlines. Every control
/// but the Slack fields writes through; those save on Return, tab switch, window close or quit.
/// There is no Save, and closing never loses an edit.
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var setup: SetupModel
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var loginItem = LoginItemManager.shared
    @ObservedObject private var navigation: SettingsNavigation
    @State private var slack = Config.load()
    @State private var slackSaveFailed = false
    /// Typed but not yet written; saved on Return, window close or quit.
    @State private var slackDirty = false
    @State private var newThreshold = ""
    @State private var proxyURL = Config.load().cliProxyURL ?? ""
    @State private var showingProxyConnection = false

    static let width: CGFloat = 560
    static let height: CGFloat = 580

    enum Tab: String, CaseIterable { case general = "General", prs = "PRs", usage = "Usage", notifications = "Notifications", displays = "Displays" }

    init(model: AppModel, navigation: SettingsNavigation) {
        self.model = model
        setup = model.setup
        self.navigation = navigation
    }

    private var tab: Tab { navigation.tab }

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
        .frame(width: Self.width, height: Self.height)
        .background(Color.black)
        .foregroundStyle(.white)
        .font(.bodyStrong)
        .preferredColorScheme(.dark)
        // At the root, not on the General tab, so they fire whichever tab is showing.
        .onChange(of: navigation.tab) { saveSlack() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in saveSlack() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in saveSlack() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            if !slackDirty { slack = Config.load() }
        }
        .sheet(isPresented: $showingProxyConnection) {
            CLIProxyConnectionView { savedURL in
                proxyURL = savedURL
                Task { await model.usageConfigurationChanged() }
            }
        }
    }

    /// Cmd-1 to Cmd-5 switch tabs, matching macOS Settings windows.
    private var tabs: some View {
        HStack(spacing: 18) {
            ForEach(Array(Tab.allCases.enumerated()), id: \.element) { index, item in
                Button {
                    navigation.tab = item
                } label: {
                    Text(item.rawValue)
                        .font(.body)
                        .foregroundStyle(tab == item ? .white : Color.dim)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                .accessibilityAddTraits(tab == item ? .isSelected : [])
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 34)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.track).frame(height: 1) }
    }

    // MARK: Rows

    /// A disabled row dims its title too, so switches that cannot change do not read as live.
    /// `rule: false` for a title row whose control is the chip row below it, so one hairline closes the pair.
    private func row<Control: View>(
        _ title: String, detail: String? = nil, detailColor: Color = .dim, disabled: Bool = false, rule: Bool = true,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).foregroundStyle(disabled ? Color.dim : .white)
                if let detail { Text(detail).font(.detail).foregroundStyle(detailColor) }
            }
            Spacer()
            control().disabled(disabled)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { if rule { Rectangle().fill(Color.rule).frame(height: 1) } }
    }

    private func toggle(_ title: String, detail: String? = nil, _ binding: Binding<Bool>, disabled: Bool = false) -> some View {
        row(title, detail: detail, disabled: disabled) {
            Toggle(title, isOn: binding).toggleStyle(.switch).labelsHidden().controlSize(.small).tint(.white)
        }
    }

    private func segmented<Value: Hashable>(
        _ title: String, detail: String? = nil, _ binding: Binding<Value>,
        options: [(Value, String)], disabled: Bool = false
    ) -> some View {
        row(title, detail: detail, disabled: disabled) {
            HStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    let selected = binding.wrappedValue == option.0
                    Button {
                        binding.wrappedValue = option.0
                    } label: {
                        Text(option.1)
                            .font(.detail)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .background(selected ? Color.white : .clear)
                            .foregroundStyle(selected ? .black : Color.dim)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title): \(option.1)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.stroke))
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
    }

    /// For choices whose count depends on the data (accounts), where a segmented control would overflow.
    private func menu<Value: Hashable>(
        _ title: String, detail: String? = nil, _ binding: Binding<Value>, options: [(Value, String)], disabled: Bool = false
    ) -> some View {
        row(title, detail: detail, disabled: disabled) {
            Menu {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    Button(option.1) { binding.wrappedValue = option.0 }
                }
            } label: {
                chip {
                    Text(options.first { $0.0 == binding.wrappedValue }?.1 ?? options.first?.1 ?? "").font(.detail)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(Color.dim)
                }
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(title)
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

    private func field(
        _ title: String, detail: String? = nil, detailColor: Color = .dim, placeholder: String, _ binding: Binding<String>,
        secure: Bool = false, width: CGFloat = 260
    ) -> some View {
        row(title, detail: detail, detailColor: detailColor) {
            chip {
                Group {
                    if secure { SecureField(placeholder, text: binding) } else { TextField(placeholder, text: binding) }
                }
                .textFieldStyle(.plain)
                .font(.body)
                .multilineTextAlignment(.trailing)
                .frame(width: width)
                .accessibilityLabel(title)
            }
        }
    }

    // MARK: General

    private var inApplications: Bool { LoginItemManager.inApplications }

    private var general: some View {
        VStack(alignment: .leading, spacing: 0) {
            if inApplications || !Notifier.shared.available {
                toggle(
                    "Launch at login", detail: inApplications ? nil : "needs the .app bundle from make-app.sh",
                    Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) }), disabled: !inApplications)
            } else {
                // The same one-click fix the setup checklist offers.
                row("Launch at login", detail: "needs the app in /Applications") {
                    FixLink(fix: .moveToApplications, setup: setup)
                }
            }
            section("Slack review nudges")
            Group {
                field("Channel ID", placeholder: "C0123456789", slackField(\.slackChannel))
                field("Bot token", detail: "optional · falls back to claude -p", placeholder: "xoxb-…", slackField(\.slackBotToken), secure: true)
            }
            .onSubmit(saveSlack)
            if slackSaveFailed {
                Text("could not update ~/.config/notchivity/config.json").font(.detail).foregroundStyle(Color.warn).padding(.top, 6)
            }
            section("About")
            row("Setup check", detail: setupSummary, detailColor: setup.blocking > 0 ? .warn : .dim) {
                if setup.pinned {
                    Text("on next hover").font(.detail).foregroundStyle(Color.dim)
                } else {
                    link("show on next hover") {
                        setup.pinned = true
                        Task { await setup.run() }
                    }
                }
            }
            row("Version") { Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev").foregroundStyle(Color.dim) }
            row("Quit Notchivity") {
                link("quit") { NSApp.terminate(nil) }
            }
        }
    }

    private var setupSummary: String {
        if !setup.hasRun { return "not run yet" }
        return setup.blocking == 0 ? "done" : "\(setup.blocking) to set up"
    }

    private func slackField(_ key: WritableKeyPath<Config, String?>) -> Binding<String> {
        Binding(
            get: { slack[keyPath: key] ?? "" },
            set: {
                slack[keyPath: key] = $0
                slackDirty = true
            })
    }

    /// Writes both Slack fields over the file as it is now. `slack` is re-read whenever the
    /// window comes forward, so a hand edit to config.json (README documents it) is not undone.
    private func saveSlack() {
        guard slackDirty else { return }
        func trimmed(_ value: String?) -> String? {
            let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? nil : text
        }
        do {
            var config = try Config.loadForUpdate()
            config.slackChannel = trimmed(slack.slackChannel)
            config.slackBotToken = trimmed(slack.slackBotToken)
            try config.save()
            slackDirty = false
            slackSaveFailed = false
        } catch {
            slackSaveFailed = true
        }
        model.reloadConfig()
    }

    // MARK: PRs

    private var prs: some View {
        VStack(alignment: .leading, spacing: 0) {
            row("Category order", detail: "drag to reorder, leftmost is listed first", rule: false) { EmptyView() }
            CategoryOrderView(order: Binding(get: { settings.categoryOrder }, set: { settings.categoryOrder = $0 }))
            segmented(
                "When the list is long", Binding(get: { settings.overflow }, set: { settings.overflow = $0 }),
                options: [(.viewAll, "view all"), (.scroll, "scroll")])
            segmented("Rows before overflow", $settings.rowsBeforeOverflow, options: [4, 6, 8, 10, 12].map { ($0, "\($0)") })
            toggle("Hide drafts", $settings.hideDrafts)
            toggle("Show age", $settings.showAge)
        }
    }

    // MARK: Usage

    private var usage: some View {
        VStack(alignment: .leading, spacing: 0) {
            row("Quota source", detail: proxyURL.isEmpty ? "local account discovery" : "CLI proxy · \(URL(string: proxyURL)?.host ?? proxyURL)") {
                link("configure…") { showingProxyConnection = true }
            }
            segmented("Poll interval", $settings.usageInterval, options: [120.0, 180.0, 300.0, 600.0].map { ($0, "\(Int($0 / 60)) min") })
            row("Notify when usage crosses", detail: "percentages, applies to every usage window", rule: false) { EmptyView() }
            HStack(spacing: 6) {
                ForEach(settings.thresholds, id: \.self) { value in
                    chip {
                        Text("\(Int(value))%").font(.detail)
                        Button {
                            settings.thresholds.removeAll { $0 == value }
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Color.dim)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(Int(value)) percent")
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
                        .accessibilityLabel("New threshold percent")
                }
                Button(action: addThreshold) {
                    Image(systemName: "plus").font(.system(size: 10, weight: .bold)).frame(width: 18, height: 18)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.stroke))
                }
                .buttonStyle(.plain)
                .foregroundStyle(pendingThreshold == nil ? Color.dim : .white)
                .disabled(pendingThreshold == nil)
                .accessibilityLabel("Add threshold")
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.rule).frame(height: 1) }
            // Last, like "In the tab" on Displays, so the rows above do not read as part of it.
            if !model.accounts.isEmpty {
                section("Names")
                ForEach(model.accounts) { account in
                    field(account.label, detail: nameDetail(account), placeholder: "rename", accountName(account.id), width: 160)
                }
            }
        }
    }

    /// Provider (when the name does not already say it) and sign-in folder, which tell apart two
    /// accounts the discovery labelled the same (two gmail sign-ins are both "gmail").
    private func nameDetail(_ account: AccountUsage) -> String? {
        let parts = [
            account.provider.name == account.label ? nil : account.provider.name,
            account.configDirectory.map { URL(fileURLWithPath: $0).lastPathComponent },
        ]
        let detail = parts.compactMap { $0 }.joined(separator: " · ")
        return detail.isEmpty ? nil : detail
    }

    /// Writes straight through so the notch shows the new name as it is typed; blank
    /// falls back to the name discovered from the sign-in, which is the row's title.
    private func accountName(_ id: String) -> Binding<String> {
        Binding(
            get: { settings.accountNames[id] ?? "" },
            set: {
                settings.accountNames[id] = $0; model.applyAccountNames()
            })
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
            segmented(
                "Peek duration", $settings.peekDuration, options: [2.0, 3.0, 5.0, 8.0].map { ($0, "\(Int($0)) s") },
                disabled: !settings.peekEnabled)
            section("Notification Center")
            // When unavailable, the reason rides on the first row rather than a subtitle under the heading.
            ForEach(Event.Kind.allCases, id: \.self) { kind in
                toggle(
                    kind.title,
                    detail: !Notifier.shared.available && kind == Event.Kind.allCases.first ? "needs the .app bundle from make-app.sh" : nil,
                    Binding(get: { settings.notifies(kind) }, set: { settings.setNotifies(kind, $0) }),
                    disabled: !Notifier.shared.available)
            }
        }
    }

    // MARK: Displays

    /// Whether any screen shows the tab: every notch-less Mac does, a notched one only with external displays on.
    private var tabShown: Bool {
        settings.externalDisplays || !NSScreen.screens.contains { $0.auxiliaryTopLeftArea != nil }
    }

    private var displays: some View {
        VStack(alignment: .leading, spacing: 0) {
            segmented("Hover delay", detail: "before the panel expands", $settings.hoverDelayMs, options: [0, 120, 250, 500].map { ($0, "\($0) ms") })
            toggle("Show on external displays too", detail: "screens without a notch get a black tab at the top centre", $settings.externalDisplays)
            section("In the tab")
            toggle("Usage", detail: "usage % and underline for one account", $settings.collapsedUsage, disabled: !tabShown)
            menu(
                "Account", $settings.underlineAccount,
                options: [("", "first listed")] + model.accounts.map { ($0.id, $0.displayLabel) },
                disabled: !tabShown || !settings.collapsedUsage)
            segmented(
                "PRs", Binding(get: { settings.indicator }, set: { settings.indicator = $0 }),
                options: [(.counts, "counts"), (.dots, "dots"), (.none, "nothing")], disabled: !tabShown)
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
                // Dragging is mouse-only; these give the same reorder to the context menu and VoiceOver.
                .contextMenu {
                    Button("Move Left") { move(category, by: -1) }.disabled(order.first == category)
                    Button("Move Right") { move(category, by: 1) }.disabled(order.last == category)
                }
                .accessibilityElement(children: .combine)
                .accessibilityHint("position \((order.firstIndex(of: category) ?? 0) + 1) of \(order.count)")
                .accessibilityAction(named: "Move Left") { move(category, by: -1) }
                .accessibilityAction(named: "Move Right") { move(category, by: 1) }
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

    private func move(_ category: PRCategory, by step: Int) {
        guard let from = order.firstIndex(of: category), order.indices.contains(from + step) else { return }
        order.swapAt(from, from + step)
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
