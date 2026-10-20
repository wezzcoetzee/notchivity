import NotchivityKit
import SwiftUI

/// Hover state: accounts on the left, open PRs on the right.
struct ExpandedView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var geometry: NotchGeometry
    @ObservedObject private var settings = Settings.shared

    static let width: CGFloat = 720
    static let rowHeight: CGFloat = 43

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            HStack(alignment: .top, spacing: 22) {
                usage.frame(width: 230)
                prs.frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
            footer
        }
        .frame(width: Self.width)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(model.me.isEmpty ? "notchivity" : "\(model.me) · \(model.prs.count) open")
            Spacer()
            Text(model.freshness)
            Button { SettingsWindowController.shared.show(model: model) } label: {
                Image(systemName: "gearshape").font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .font(.detail)
        .foregroundStyle(Color.dim)
        .padding(.horizontal, 18)
        .frame(height: geometry.notchHeight)
        .padding(.bottom, 8)
    }

    private var usage: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle("Usage")
            if model.accounts.isEmpty {
                Text(model.lastUsageAt == nil ? "loading…" : "no Claude sign-in found").font(.body).foregroundStyle(Color.dim)
            }
            ForEach(Array(model.accounts.enumerated()), id: \.element.id) { index, account in
                if index > 0 { Spacer().frame(height: 10) }
                ForEach(account.windows, id: \.self) { window in
                    let reset = window == .session
                        ? model.countdown(account.resetsAt(window))
                        : model.resetDay(account.resetsAt(window))
                    usageRow(label: window == account.windows.first ? account.displayLabel : "",
                             pct: account.pct(window),
                             sub: reset.map { "\(window.label) · resets \($0)" } ?? window.label)
                }
                if let warning = model.usageWarning(account) {
                    Text(warning).font(.detail).foregroundStyle(Color.warn).lineLimit(2)
                } else if let staleness = model.staleness(account) {
                    Text(staleness).font(.detail).foregroundStyle(Color.dim).padding(.leading, 60)
                }
            }
        }
    }

    private func usageRow(label: String, pct: Double?, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(label).frame(width: 52, alignment: .leading)
                Bar(pct: pct)
                Text(pct.map { "\(Int($0))%" } ?? "—").frame(width: 40, alignment: .trailing)
            }
            .font(.body)
            Text(sub).font(.detail).foregroundStyle(Color.dim).padding(.leading, 60)
        }
        .padding(.vertical, 2)
    }

    // MARK: PRs

    private var prs: some View {
        let all = model.orderedPRs
        let limit = settings.rowsBeforeOverflow
        let overflowing = all.count > limit
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                SectionTitle("Open PRs")
                Text("\(all.count)").font(.detail).foregroundStyle(Color.dim)
            }
            if let error = model.prError, all.isEmpty {
                Text(error).font(.detail).foregroundStyle(Color.warn)
            } else if all.isEmpty {
                Text(model.lastPRsAt == nil ? "loading…" : "nothing open").font(.body).foregroundStyle(Color.dim)
            }
            switch settings.overflow {
            case .scroll where overflowing:
                scrollingRows(all, visible: limit)
            case .viewAll where overflowing && !model.showAllPRs:
                rows(Array(all.prefix(limit)))
                viewAllLine(hidden: Array(all.dropFirst(limit)))
            case .viewAll where overflowing:
                if all.count > Self.rowsThatFit { scrollingRows(all, visible: Self.rowsThatFit) } else { rows(all) }
                Button("show less") { model.showAllPRs = false }.buttonStyle(.plain).modifier(LinkStyle())
            default:
                rows(all)
            }
            if !model.selectedPRs.isEmpty { selectionLine }
        }
    }

    private var selectionLine: some View {
        HStack(spacing: 4) {
            if model.slackConfigured {
                Button("ask for review in Slack") { model.askForReviewOfSelection() }.buttonStyle(.plain)
                Text("·").foregroundStyle(Color.dim)
            }
            Text("\(model.selectedPRs.count) selected").foregroundStyle(Color.dim)
            Text("·").foregroundStyle(Color.dim)
            Button("clear") { model.selectedPRs = [] }.buttonStyle(.plain)
        }
        .modifier(LinkStyle())
    }

    /// A hairline closes the list instead of a fade, so the last row stays readable.
    private func scrollingRows(_ prs: [PullRequest], visible: Int) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 0) { rows(prs) }
        }
        .frame(height: CGFloat(visible) * Self.rowHeight)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.rule).frame(height: 1) }
    }

    /// How many rows "view all" can show before the list would run off the fixed window
    /// or past 60% of the screen; beyond that it scrolls.
    private static var rowsThatFit: Int {
        let screen = (NSScreen.main?.visibleFrame.height ?? NotchWindowController.windowSize.height) * 0.6
        let window = NotchWindowController.windowSize.height - 140
        return Int(min(screen, window) / rowHeight)
    }

    private func rows(_ prs: [PullRequest]) -> some View {
        ForEach(prs) { pr in
            PRRow(pr: pr, age: settings.showAge ? model.age(pr.updatedAt) : nil, slack: model.slackConfigured,
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

    @ViewBuilder private var footer: some View {
        if let status = model.slackStatus {
            Text(status)
                .font(.detail).foregroundStyle(Color.dim)
                .padding(.horizontal, 18).padding(.bottom, 10)
        }
    }
}

struct LinkStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.detail)
            .foregroundStyle(Color.link)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Rectangle().fill(Color.rule).frame(height: 1) }
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
    }
}

struct PRRow: View {
    let pr: PullRequest
    let age: String?
    let slack: Bool
    let selected: Bool
    let askForReview: () -> Void
    let toggleSelection: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Dot(color: .tone(for: pr.category), size: 8).offset(y: 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(pr.title).font(.bodyStrong).lineLimit(1).truncationMode(.tail)
                Text(pr.shortRef).font(.detail).foregroundStyle(Color.dim)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 8)
            HStack(spacing: 0) {
                ForEach(Array(pr.flags.enumerated()), id: \.offset) { index, flag in
                    if index > 0 { Text(" · ").foregroundStyle(Color.dim) }
                    Text(flag.text).foregroundStyle(flag.tone == .dim ? Color.dim : Color(flag.tone))
                }
                if let age { Text(" · \(age)").foregroundStyle(Color.dim) }
            }
            .font(.detail)
            .fixedSize()
        }
        .padding(.vertical, 5)
        .frame(height: ExpandedView.rowHeight)
        .overlay(alignment: .top) { Rectangle().fill(Color.rule).frame(height: 1) }
        .background(selected ? Color.track : hovering ? Color.hover : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.command) { toggleSelection() } else { NSWorkspace.shared.open(pr.url) }
        }
        .contextMenu {
            Button("Open on GitHub") { NSWorkspace.shared.open(pr.url) }
            Button("Copy URL") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(pr.url.absoluteString, forType: .string)
            }
            Button(selected ? "Deselect" : "Select") { toggleSelection() }
            if slack { Button("Ask for review in Slack") { askForReview() } }
        }
    }
}
