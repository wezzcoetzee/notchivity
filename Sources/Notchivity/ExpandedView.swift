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

    private var header: some View {
        HStack(spacing: 12) {
            Text(model.me.isEmpty ? "notchivity" : model.me)
            Spacer()
            // With PRs on screen the error has nowhere else to go; an empty list shows it inline instead.
            if let error = model.prError, !model.orderedPRs.isEmpty {
                Text(error).foregroundStyle(Color.warn)
                if let fix = model.prFix { FixLink(fix: fix, setup: model.setup) }
            }
            Text(model.freshness)
            Button {
                SettingsWindowController.shared.show(model: model)
            } label: {
                Image(systemName: "gearshape").font(.system(size: 12))
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, -6)
            .help("Settings")
            .accessibilityLabel("Settings")
        }
        .font(.detail)
        .foregroundStyle(Color.dim)
        .padding(.horizontal, 18)
        .frame(height: geometry.notchHeight)
        .padding(.bottom, 8)
    }

    // MARK: Usage

    /// Spacing 0 like the PR column, so empty-state lines and first rows line up across columns.
    private var usage: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Usage")
            if model.accounts.isEmpty {
                Text(model.lastUsageAt == nil ? "loading…" : "no accounts found").font(.body).foregroundStyle(Color.dim)
            }
            ForEach(Array(model.accounts.enumerated()), id: \.element.id) { index, account in
                if index > 0 { Spacer().frame(height: 10) }
                accountRows(account)
            }
        }
    }

    @ViewBuilder private func accountRows(_ account: AccountUsage) -> some View {
        let warning = model.usageWarning(account)
        let stale = model.staleness(account)
        if let warning, account.windows.allSatisfy({ account.pct($0) == nil }) {
            // Nothing to read, so one row says why instead of empty bars per window.
            usageRow(account, label: account.displayLabel, pct: nil, sub: "")
            fixableWarning(warning, account)
        } else {
            ForEach(account.windows, id: \.self) { window in
                let reset = window == .session ? model.countdown(account.resetsAt(window)) : model.resetDay(account.resetsAt(window))
                usageRow(
                    account, label: window == account.windows.first ? account.displayLabel : "",
                    pct: model.displayPct(account, window), sub: reset.map { "\(window.label) · resets \($0)" } ?? window.label,
                    old: model.isOld(account))
            }
            if let warning {
                fixableWarning(warning, account)
            } else if let stale {
                subLine(stale, color: .dim)
            }
        }
    }

    /// `old` greys the percentage of a reading that failed to refresh or was recorded long ago,
    /// unless it is in the red, which still matters at any age.
    private func usageRow(
        _ account: AccountUsage, label: String, pct: Double?, sub: String, old: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(label).lineLimit(1).truncationMode(.tail).frame(width: 52, alignment: .leading).help(label)
                Bar(pct: pct, old: old)
                Text(pct.map { "\(Int($0))%" } ?? "?")
                    .foregroundStyle(pct.map { Color.usage($0, old: old) } ?? .dim)
                    .frame(width: 40, alignment: .trailing)
            }
            .font(.body)
            if !sub.isEmpty { subLine(sub, color: .dim) }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([account.displayLabel, pct.map { "\(Int($0)) percent" } ?? "unknown", sub].filter { !$0.isEmpty }.joined(separator: ", "))
    }

    /// The amber reason under an account, with the setup fix as a blue link on the line below
    /// when there is one, so the fix is where the problem is.
    @ViewBuilder private func fixableWarning(_ warning: String, _ account: AccountUsage) -> some View {
        subLine(warning, color: .warn).help(account.failure?.description ?? warning)
        if let fix = account.fix {
            FixLink(fix: fix, setup: model.setup).padding(.leading, 60)
        }
    }

    /// Detail line under a usage row, indented to the bar column. Long errors wrap to two lines
    /// and keep their full text in the tooltip.
    private func subLine(_ text: String, color: Color) -> some View {
        Text(text).font(.detail).foregroundStyle(color).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 60).help(text)
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
                    Text("\(all.count)").font(.label).foregroundStyle(Color.dim)
                }
            }
            if all.isEmpty {
                if let error = model.prError {
                    Text(error).font(.body).foregroundStyle(Color.warn)
                    if let fix = model.prFix { FixLink(fix: fix, setup: model.setup).padding(.top, 2) }
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
                if all.count > Self.rowsThatFit { scrollingRows(all, visible: Self.rowsThatFit, slack: slack) } else { rows(all, slack: slack) }
                Button("show less") {
                    model.showAllPRs = false
                    model.selectedPRs.formIntersection(all.prefix(limit).map(\.id))
                }
                .buttonStyle(.plain).modifier(LinkStyle())
            default:
                rows(all, slack: slack)
            }
            if let status = model.slackStatus {
                Text(status.text).foregroundStyle(status.failed ? Color.warn : Color.dim).modifier(LinkStyle())
            }
            // Kept under a failure so a retry is one click away; hidden only while posting. One
            // hairline covers both lines.
            if !model.selectedPRs.isEmpty, model.slackStatus?.posting != true {
                selectionLine.modifier(LinkStyle(rule: model.slackStatus == nil))
            }
        }
    }

    private var selectionLine: some View {
        HStack(spacing: 4) {
            Button("ask for review in Slack") { model.askForReviewOfSelection() }.buttonStyle(.plain)
            Text("· \(model.selectedPRs.count) selected ·").foregroundStyle(Color.dim)
            Button("clear") { model.selectedPRs = [] }.buttonStyle(.plain)
        }
    }

    /// Half a row peeks out at the bottom so the list reads as scrollable; a hairline closes it
    /// instead of a fade. The inset keeps row fills from being clipped by the scroll view.
    private func scrollingRows(_ prs: [PullRequest], visible: Int, slack: Bool) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 0) { rows(prs, slack: slack) }.padding(.horizontal, Self.rowInset)
        }
        .padding(.horizontal, -Self.rowInset)
        .frame(height: (CGFloat(visible) + 0.5) * Self.rowHeight)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.rule).frame(height: 1) }
    }

    /// How many rows "view all" can show before the list would run off the fixed window
    /// or past 60% of the screen; beyond that it scrolls.
    private static var rowsThatFit: Int {
        let screen = (NSScreen.main?.visibleFrame.height ?? NotchWindowController.windowSize.height) * 0.6
        let window = NotchWindowController.windowSize.height - 140
        return Int(min(screen, window) / rowHeight)
    }

    private func rows(_ prs: [PullRequest], slack: Bool) -> some View {
        ForEach(prs) { pr in
            PRRow(
                pr: pr, age: settings.showAge ? model.age(pr.updatedAt) : nil, slack: slack,
                selected: model.selectedPRs.contains(pr.id),
                askForReview: { model.askForReview(pr) }, toggleSelection: { model.toggleSelection(pr) })
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
    let askForReview: () -> Void
    let toggleSelection: () -> Void
    @State private var hovering = false

    /// The right-hand column holds the two most urgent flags; the rest ride on the ref line,
    /// so a PR with every flag set still leaves room for its title.
    private static let shownFlags = 2

    var body: some View {
        let shown = pr.flags.prefix(Self.shownFlags)
        let rest = pr.flags.dropFirst(Self.shownFlags).map(\.text)
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Dot(color: .tone(for: pr.category), size: 8).offset(y: 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(pr.title).font(.bodyStrong).lineLimit(1).truncationMode(.tail).help(pr.title)
                Text(([pr.shortRef] + rest).joined(separator: " · ")).font(.detail).foregroundStyle(Color.dim).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 8)
            HStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.offset) { index, flag in
                    if index > 0 { Text(" · ").foregroundStyle(Color.dim) }
                    Text(flag.text).foregroundStyle(Color(flag.tone))
                }
                if let age { Text(" · \(age)").foregroundStyle(Color.dim) }
            }
            .font(.detail)
            .fixedSize()
        }
        .padding(.vertical, 5)
        .padding(.horizontal, ExpandedView.rowInset)
        .frame(height: ExpandedView.rowHeight)
        .background(selected ? Color.track : hovering ? Color.hover : .clear)
        .overlay(alignment: .top) { Rectangle().fill(Color.rule).frame(height: 1).padding(.horizontal, ExpandedView.rowInset) }
        .padding(.horizontal, -ExpandedView.rowInset)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            if slack, NSEvent.modifierFlags.contains(.command) { toggleSelection() } else { open() }
        }
        .contextMenu {
            Button("Open on GitHub", action: open)
            Button("Copy URL", action: copyURL)
            if slack {
                Divider()
                Button("Ask for Review in Slack", action: askForReview)
                Button(selected ? "Deselect" : "Select for One Slack Ask", action: toggleSelection)
            }
        }
        .accessibilityElement(children: .ignore)
        // The flags say what the dot means; the category name only fills in when there are none.
        .accessibilityLabel(([pr.title, pr.shortRef] + (pr.flags.isEmpty ? [pr.category.title] : pr.flags.map(\.text))).joined(separator: ", "))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, open)
        .accessibilityAction(named: "Copy URL", copyURL)
    }

    private func open() { NSWorkspace.shared.open(pr.url) }

    private func copyURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pr.url.absoluteString, forType: .string)
    }
}
