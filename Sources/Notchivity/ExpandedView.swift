import NotchivityKit
import SwiftUI

/// Hover state: accounts on the left, open PRs on the right.
struct ExpandedView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var geometry: NotchGeometry
    @ObservedObject private var settings = Settings.shared

    static let width: CGFloat = 720
    static let rowHeight: CGFloat = 43
    /// How far row hover and selection fills reach past the text column, so text never touches their edge.
    static let rowInset: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            // Top-leading so a short column (loading, empty, error) stays where the full one would be.
            HStack(alignment: .top, spacing: 22) {
                usage.frame(width: 230, alignment: .topLeading)
                prs.frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
        }
        .frame(width: Self.width)
    }

    /// Faults live here, once, so the columns stay readings; "fix" opens the setup checklist,
    /// which carries each fault's own fix.
    /// The header shares its band with the hardware notch, so each side is capped at its half of
    /// the panel minus the notch; on a notch-less screen there is nothing to clear. A fault takes
    /// the freshness text's place, and truncates before the links do.
    private var header: some View {
        let side = geometry.isFake ? .infinity : (Self.width - 36 - geometry.notchWidth) / 2 - 8
        return HStack(spacing: 0) {
            // The first-seen slot carries state, not identity: the worst thing right now in its
            // lamp colour, empty when calm. The login is the slot's tooltip.
            Text(model.worstItem?.text ?? "")
                .foregroundStyle(model.worstItem.map { Color($0.tone) } ?? Color.dim)
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: side, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .help(model.me.isEmpty ? "" : "signed in to GitHub as \(model.me)")
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                if let notice = model.notice {
                    Text(notice + " · ").lineLimit(1)
                } else if model.faultSummary == nil, !model.freshness.isEmpty {
                    Text(model.freshness + " · ").lineLimit(1)
                }
                if let faults = model.faultSummary {
                    Text(faults).foregroundStyle(.white).lineLimit(1).truncationMode(.tail)
                    Text(" · ")
                    headerLink("fix", action: model.setup.pin).layoutPriority(1)
                } else {
                    headerLink("setup", action: model.setup.pin).layoutPriority(1)
                }
                Text(" · ")
                headerLink("settings") { SettingsWindowController.shared.show(model: model) }.layoutPriority(1)
            }
            .frame(maxWidth: side, alignment: .trailing)
        }
        .font(.detail)
        .foregroundStyle(Color.dim)
        .padding(.horizontal, 18)
        .frame(height: geometry.notchHeight)
        .padding(.bottom, 8)
    }

    /// A 24pt-tall hit area around 11pt text: the panel is a moving target at the screen edge.
    private func headerLink(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).frame(minHeight: 24).padding(.horizontal, 2).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(Color.link).padding(.horizontal, -2)
    }

    // MARK: Usage

    /// Spacing 0 like the PR column, so empty-state lines and first rows line up across columns.
    private var usage: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Usage")
            if model.accounts.isEmpty {
                HStack(spacing: 6) {
                    Text(model.lastUsageAt == nil ? "loading…" : "no accounts found").font(.body).foregroundStyle(Color.dim)
                    if model.lastUsageAt != nil { headerLink("setup", action: model.setup.pin).font(.detail) }
                }
            }
            ForEach(model.panelAccounts) { account in
                accountRow(account)
            }
        }
    }

    private typealias Reading = (window: AccountUsage.Window, pct: Double?)

    /// One account: its name and lead percentage on one line, the lead window's bar under them
    /// at full column width with any other window as a thin line beneath, then the summary.
    /// The lead is the session unless another window has reached amber and is fuller.
    private func accountRow(_ account: AccountUsage) -> some View {
        let readings: [Reading] = account.windows.map { ($0, model.displayPct(account, $0)) }
        let leadWindow = model.leadWindow(account)
        let lead = readings.first { $0.window == leadWindow } ?? readings[0]
        // At 75% or more the reset is the answer, so it moves up beside the name at body size.
        let urgent = (lead.pct ?? 0) >= 75
        let resetUp = urgent ? reset(account, lead.window).map { (lead.window == .session ? "" : "\(lead.window.label) ") + "resets \($0)" } : nil
        // The reset moves up only if it fits whole beside the name; otherwise it stays on the
        // line below, rather than either one being cut to nothing.
        return ViewThatFits(in: .horizontal) {
            accountBlock(account, readings: readings, lead: lead, resetUp: resetUp)
            if resetUp != nil { accountBlock(account, readings: readings, lead: lead, resetUp: nil) }
        }
        // The first label sits level with the first PR title beside it.
        .padding(.top, 6)
        .padding(.bottom, 6)
        .help(([accountName(account)] + readings.map { describe(account, $0) }).joined(separator: "\n"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            ([accountName(account)] + readings.map { describe(account, $0, spoken: true) }
                + [model.usageWarning(account) ?? model.staleness(account)].compactMap { $0 }).joined(separator: ", "))
    }

    private func accountBlock(_ account: AccountUsage, readings: [Reading], lead: Reading, resetUp: String?) -> some View {
        let old = model.isOld(account)
        let rest = readings.filter { $0.window != lead.window }
        let unread = readings.allSatisfy { $0.pct == nil }
        let warning = model.usageWarning(account)
        let reason = warning ?? model.staleness(account)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(account.displayLabel).lineLimit(1).truncationMode(.tail)
                // Two accounts with one name ("Codex", "Codex") need telling apart at a glance.
                if let twin = model.twin(account) { Text("· \(twin)").font(.detail).foregroundStyle(Color.dim) }
                if let resetUp { Text("· \(resetUp)").fontWeight(.regular).lineLimit(1) }
                Spacer(minLength: 8)
                Text(lead.pct.map { "\(Int($0))%" } ?? "?")
                    .foregroundStyle(lead.pct.map { Color.usage($0, old: old) } ?? .dim)
                    // The reading never gives way to the name or the reset.
                    .fixedSize()
            }
            .font(.body)
            // No reading at all: no bar, which an empty track would make read as 0%.
            if !unread {
                VStack(spacing: 3) {
                    Bar(pct: lead.pct, old: old)
                    ForEach(rest, id: \.window) { Bar(pct: $0.pct, height: 2, old: old, quiet: true) }
                }
            }
            // An account with nothing to read only needs the reason.
            if !unread, let line = summary(account, lead: lead, rest: rest, old: old, withReset: resetUp == nil) { subLine(line) }
            if let reason {
                HStack(spacing: 4) {
                    subLine(Text(warning != nil && account.fix != nil ? reason + " ·" : reason)).help(account.failure?.description ?? reason)
                    if warning != nil, let fix = account.fix { FixLink(fix: fix, setup: model.setup) }
                }
            }
        }
    }

    /// "resets 2h 14m · week 61%". A non-session lead names itself; another window turns amber or
    /// red here once its line does.
    private func summary(_ account: AccountUsage, lead: Reading, rest: [Reading], old: Bool, withReset: Bool) -> Text? {
        var parts =
            withReset
            ? [lead.window == .session ? nil : lead.window.label, reset(account, lead.window).map { "resets \($0)" }].compactMap { $0 }.map { Text($0) }
            : []
        parts += rest.map { reading in
            let text = Text("\(reading.window.label) \(reading.pct.map { "\(Int($0))%" } ?? "?")")
            guard let pct = reading.pct, pct >= 75 else { return text }
            return text.foregroundStyle(Color.usage(pct, old: old))
        }
        guard let first = parts.first else { return nil }
        return parts.dropFirst().reduce(first) { $0 + Text(" · ") + $1 }
    }

    private func reset(_ account: AccountUsage, _ window: AccountUsage.Window) -> String? {
        window == .session ? model.countdown(account.resetsAt(window)) : model.resetDay(account.resetsAt(window))
    }

    /// A renamed account keeps its provider in the tooltip and VoiceOver, so "Work" still says what it is.
    private func accountName(_ account: AccountUsage) -> String {
        account.customLabel == nil ? account.displayLabel : "\(account.displayLabel) (\(account.provider.name))"
    }

    /// "week 61% used · resets Sat 16:06" for the tooltip, or its spoken form for VoiceOver.
    private func describe(_ account: AccountUsage, _ reading: Reading, spoken: Bool = false) -> String {
        let used = reading.pct.map { spoken ? "\(Int($0)) percent used" : "\(Int($0))% used" } ?? "unknown"
        let reset = reset(account, reading.window).map { "resets \($0)" }
        return ["\(reading.window.label) \(used)", reset].compactMap { $0 }.joined(separator: spoken ? ", " : " · ")
    }

    private func subLine(_ text: Text) -> some View {
        text.font(.detail).foregroundStyle(Color.dim).lineLimit(2).fixedSize(horizontal: false, vertical: true)
    }

    // MARK: PRs

    private var prs: some View {
        let all = model.orderedPRs
        let limit = settings.rowsBeforeOverflow
        let overflowing = all.count > limit
        let slack = model.slackConfigured
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                SectionTitle("Open PRs")
                // Only a real, non-zero count: before the first fetch or beside an error "0" would be
                // a false reading, and an empty list already says "nothing open".
                if model.lastPRsAt != nil, !all.isEmpty {
                    Text(model.prs.count >= PRFetcher.pageSize ? "\(all.count)+" : "\(all.count)").font(.label).foregroundStyle(Color.dim)
                }
                // The last refresh failed, so these rows are as old as the last good one.
                if model.prError != nil, !all.isEmpty, let at = model.lastPRsAt {
                    Text("· as of \(model.age(at)) ago ·").font(.detail).foregroundStyle(Color.dim)
                    if let fix = model.prFix { FixLink(fix: fix, setup: model.setup) }
                }
            }
            if all.isEmpty {
                if let error = model.prError {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(error + " ·").font(.body).foregroundStyle(Color.dim)
                        if let fix = model.prFix { FixLink(fix: fix, setup: model.setup) }
                    }
                } else {
                    Text(model.lastPRsAt == nil ? "loading…" : "nothing open").font(.body).foregroundStyle(Color.dim)
                }
            }
            switch settings.overflow {
            case .scroll where overflowing:
                scrollingRows(all, visible: limit, slack: slack)
            case .viewAll where overflowing && !model.showAllPRs:
                rows(Array(all.prefix(limit)), slack: slack)
                viewAllLine(hidden: Array(all.dropFirst(limit)))
            case .viewAll where overflowing:
                if all.count > rowsThatFit { scrollingRows(all, visible: rowsThatFit, slack: slack) } else { rows(all, slack: slack) }
                Button("show less", action: model.showLess)
                    .buttonStyle(.plain).modifier(LinkStyle())
            default:
                rows(all, slack: slack)
            }
            if let pending = model.pendingAsk {
                HStack(spacing: 4) {
                    Text("asking for review of \(pending.count == 1 ? pending[0].shortRef : plural(pending.count, "PR")) ·").foregroundStyle(Color.dim)
                    Button("undo") { model.undoAsk() }.buttonStyle(.plain)
                }
                .modifier(LinkStyle())
            } else if let status = model.slackStatus {
                HStack(spacing: 6) {
                    Text(status.text).foregroundStyle(status.failed ? Color.white : Color.dim)
                    if let fix = status.fix { FixLink(fix: fix, setup: model.setup) }
                }
                .modifier(LinkStyle())
            }
            // Kept under a failure so a retry is one click away; hidden only while posting. One
            // hairline covers both lines.
            if !model.selectedPRs.isEmpty, model.slackStatus?.posting != true, model.pendingAsk == nil {
                selectionLine.modifier(LinkStyle(rule: model.slackStatus == nil))
            }
            if model.focusFromKeyboard {
                keyLegend
            } else if model.gestureHint {
                gestureHint
            }
        }
    }

    /// The keys that do something right now, while the arrow keys drive; the pointer never
    /// sees it. Slack keys only with Slack set up, "c" only with a selection, "v" only when the
    /// list overflows.
    private var keyLegend: some View {
        let slack = model.slackConfigured ? ["space select", "a ask"] + (model.selectedPRs.isEmpty ? [] : ["c clear"]) : []
        let overflow =
            model.showAllPRs ? ["v show less"] : model.orderedPRs.count > settings.rowsBeforeOverflow ? ["v view all"] : []
        let fix = model.firstFix == nil ? [] : ["f fix"]
        let keys = ["↑↓ ↩ open", "m menu"] + slack + fix + ["r refresh", "s setup"] + overflow + ["⌘, settings", "esc"]
        return Text(keys.joined(separator: " · "))
            .font(.detail).foregroundStyle(Color.dim)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)
    }

    /// The ways in that a hover never shows: on the first few hover opens only.
    private var gestureHint: some View {
        let ways = model.unlearnedGestures.map { gesture in
            switch gesture {
            case .cmdClick: return "⌘-click select"
            case .rightClick: return "right-click for more"
            case .keyboard: return "⌃⌥N for the keyboard"
            }
        }
        return Text(ways.joined(separator: " · ")).font(.detail).foregroundStyle(Color.dim).padding(.top, 8)
    }

    private var selectionLine: some View {
        HStack(spacing: 4) {
            Button("ask for review in Slack") { model.askForReviewOfSelection() }.buttonStyle(.plain)
            Text("· \(model.selectedPRs.count) selected ·").foregroundStyle(Color.dim)
            Button("clear") { model.clearSelection() }.buttonStyle(.plain)
        }
    }

    /// Half a row peeks out at the bottom so the list reads as scrollable; a hairline closes it
    /// instead of a fade. The inset keeps row fills from being clipped by the scroll view.
    private func scrollingRows(_ prs: [PullRequest], visible: Int, slack: Bool) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) { rows(prs, slack: slack) }.padding(.horizontal, Self.rowInset)
            }
            // On appear too: the arrow key that opens "view all" sets the target in the same tick.
            .onAppear { if let id = model.scrollTarget { proxy.scrollTo(id) } }
            .onChange(of: model.scrollTarget) { _, id in if let id { proxy.scrollTo(id) } }
        }
        .padding(.horizontal, -Self.rowInset)
        .frame(height: (CGFloat(visible) + 0.5) * Self.rowHeight)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.rule).frame(height: 1) }
    }

    /// "view all" shows at most this many rows before it scrolls, however tall the screen.
    static let viewAllCap = 12

    /// How many rows "view all" can show before the list would run off the fixed window
    /// or past 60% of the screen; beyond that it scrolls.
    private var rowsThatFit: Int {
        let screen = geometry.screenHeight * 0.6
        let window = NotchWindowController.windowSize.height - 140
        return min(Self.viewAllCap, Int(min(screen, window) / Self.rowHeight))
    }

    private func rows(_ prs: [PullRequest], slack: Bool) -> some View {
        ForEach(prs) { pr in
            PRRow(
                pr: pr, age: settings.showAge ? model.age(pr.updatedAt) : nil, slack: slack,
                selected: model.selectedPRs.contains(pr.id), focused: model.focusedPR == pr.id, keyboard: model.focusFromKeyboard,
                hover: { model.hoverFocus(pr, $0) },
                menu: model.menu(for: pr), toggleSelection: { model.toggleSelection(pr) },
                cmdClicked: { model.noteGesture(.cmdClick) })
        }
    }

    private func viewAllLine(hidden: [PullRequest]) -> some View {
        let summary = settings.categoryOrder
            .map { category in (category, hidden.filter { $0.category == category }.count) }
            .filter { $0.1 > 0 }
            .map { "\($0.1) \($0.0.title.lowercased())" }
            .joined(separator: ", ")
        return HStack(spacing: 4) {
            Button("view all \(hidden.count + settings.rowsBeforeOverflow)") { model.showAllPRs = true }.buttonStyle(.plain)
            Text("· \(summary) hidden").foregroundStyle(Color.dim)
        }
        .modifier(LinkStyle())
    }
}

struct LinkStyle: ViewModifier {
    var rule = true

    func body(content: Content) -> some View {
        content
            .font(.detail)
            .foregroundStyle(Color.link)
            .padding(.top, rule ? 8 : 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { if rule { Rectangle().fill(Color.rule).frame(height: 1) } }
    }
}

/// The row highlight shared by PR rows and setup rows: Hover Grey (Stroke Grey when also
/// selected, Track Grey when only selected), and a 2px white leading edge when the arrow keys
/// put it there, since Hover Grey alone is about 1.2:1 on black. White, never a lamp colour.
struct RowHighlight: ViewModifier {
    let focused: Bool
    var keyboard = true
    var selected = false

    func body(content: Content) -> some View {
        content
            .background(focused ? (selected ? Color.stroke : Color.hover) : selected ? Color.track : .clear)
            .overlay(alignment: .leading) { if focused && keyboard { Rectangle().fill(Color.white).frame(width: 2) } }
    }
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.label).kerning(0.4)
            .foregroundStyle(Color.dim)
            .padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
    }
}

struct PRRow: View {
    let pr: PullRequest
    let age: String?
    /// Selection only exists to batch a Slack ask, so it is offered only when Slack is set up.
    let slack: Bool
    let selected: Bool
    /// Hovered or reached with the arrow keys; the model keeps one highlight for both.
    let focused: Bool
    /// The focus came from the arrow keys: the fill alone is too faint to follow, so it gets an edge.
    let keyboard: Bool
    let hover: (Bool) -> Void
    /// The right-click menu, shared with the "m" key; nil is a divider.
    let menu: [(title: String, action: () -> Void)?]
    let toggleSelection: () -> Void
    /// Cmd-click was used, so the first-hover hint stops teaching it.
    let cmdClicked: () -> Void

    /// The right-hand column holds the two most urgent flags and counts the rest ("+3"), so a PR
    /// with every flag set still leaves room for its title. The tooltip lists them all.
    private static let shownFlags = 2

    var body: some View {
        let shown = pr.flags.prefix(Self.shownFlags)
        let hidden = pr.flags.count - shown.count
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Dot(color: .tone(for: pr.category), size: 8)
                // Selection is marked on the dot, not only by a fill a few percent off the hover one.
                .overlay { if selected { Circle().strokeBorder(Color.white, lineWidth: 1.5).frame(width: 15, height: 15) } }
                .offset(y: 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(pr.title).font(.bodyStrong).lineLimit(1).truncationMode(.tail)
                Text(pr.shortRef).font(.detail).foregroundStyle(Color.dim).lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 8)
            HStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.offset) { index, flag in
                    if index > 0 { Text(" · ").foregroundStyle(Color.dim) }
                    Text(flag.text).foregroundStyle(Color(flag.tone))
                }
                if hidden > 0 { Text(" · +\(hidden)").foregroundStyle(Color.dim) }
                if let age { Text(shown.isEmpty ? age : " · \(age)").foregroundStyle(Color.dim) }
            }
            .font(.detail)
            .fixedSize()
        }
        .padding(.vertical, 5)
        .padding(.horizontal, ExpandedView.rowInset)
        .frame(height: ExpandedView.rowHeight)
        .modifier(RowHighlight(focused: focused, keyboard: keyboard, selected: selected))
        .overlay(alignment: .top) { Rectangle().fill(Color.rule).frame(height: 1).padding(.horizontal, ExpandedView.rowInset) }
        .padding(.horizontal, -ExpandedView.rowInset)
        .contentShape(Rectangle())
        .onHover(perform: hover)
        .help(hint)
        .onTapGesture {
            if slack, NSEvent.modifierFlags.contains(.command) {
                toggleSelection()
                cmdClicked()
            } else {
                open()
            }
        }
        .contextMenu {
            ForEach(Array(menu.enumerated()), id: \.offset) { _, item in
                if let item { Button(item.title, action: item.action) } else { Divider() }
            }
        }
        .accessibilityElement(children: .ignore)
        // The flags say what the dot means; the category name only fills in when there are none.
        .accessibilityLabel(([pr.title, pr.shortRef] + (pr.flags.isEmpty ? [pr.category.title] : pr.flags.map(\.text))).joined(separator: ", "))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, open)
        .accessibilityAction(named: "Copy URL", copyURL)
    }

    /// The full title, then the gestures that are otherwise invisible. Only appears after the
    /// system tooltip delay, so a passing glance never sees it.
    private var hint: String {
        let gestures = ["click to open"] + (slack ? ["cmd-click to select"] : []) + ["right-click for more"]
        let flags = pr.flags.isEmpty ? [] : [pr.flags.map(\.text).joined(separator: " · ")]
        return ([pr.title] + flags + [gestures.joined(separator: " · ")]).joined(separator: "\n")
    }

    private func open() { NSWorkspace.shared.open(pr.url) }

    private func copyURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pr.url.absoluteString, forType: .string)
    }
}
