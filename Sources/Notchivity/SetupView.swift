import NotchivityKit
import SwiftUI

/// The in-notch checklist shown while required checks fail, or when pinned from the menu.
struct SetupView: View {
    @ObservedObject var setup: SetupModel
    @ObservedObject var geometry: NotchGeometry

    /// Same width as the dashboard so the swap between the two never resizes the shape.
    static let width = ExpandedView.width

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                // Amber like the same label under the notch, so the two counts read as one number.
                Text(headline).foregroundStyle(setup.blocking > 0 ? Color.warn : Color.dim)
                Spacer()
                // The dashboard is always one click away, whatever the results.
                // "skip" while required checks fail, so it is clear the checks are being set aside.
                Button(setup.blocking > 0 ? "skip for now" : "close", action: setup.close).buttonStyle(.plain).foregroundStyle(Color.link)
            }
            .font(.detail).foregroundStyle(Color.dim)
            .padding(.horizontal, 18)
            .frame(height: geometry.notchHeight)
            .padding(.bottom, 8)

            if setup.checks.isEmpty {
                Text("running checks…").font(.body).foregroundStyle(Color.dim).padding(.horizontal, 18)
            }
            ForEach(setup.requiredToDo) { check in
                SetupRow(check: check, setup: setup)
            }
            if !setup.passed.isEmpty { passedRow }
            if setup.showPassed {
                ForEach(setup.passed) { check in
                    SetupRow(check: check, setup: setup, optional: !check.required)
                }
            }
            if !setup.optionalToDo.isEmpty {
                SectionTitle("Optional").padding(.horizontal, 18).padding(.top, 12)
                ForEach(setup.optionalToDo) { check in
                    SetupRow(check: check, setup: setup, optional: true)
                }
            }
            // Only once the arrow keys are on a row, like the dashboard's legend.
            if setup.focusedCheck != nil {
                Text("↑↓ move · ↩ fix · esc back").font(.detail).foregroundStyle(Color.dim)
                    .padding(.horizontal, 18).padding(.top, 8)
            }
        }
        .padding(.bottom, 14)
        .frame(width: Self.width)
    }

    /// Passing checks fold into one line so the rows that need a look lead; "show" lists them.
    private var passedRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Dot(color: .good, size: 8).offset(y: 1)
            Text("\(setup.passed.count) passed").font(.body).foregroundStyle(Color.dim)
            Spacer()
            Button(setup.showPassed ? "hide" : "show") { setup.showPassed.toggle() }
                .buttonStyle(.plain).font(.detail).foregroundStyle(Color.link)
        }
        .frame(minHeight: ExpandedView.rowHeight)
        .padding(.horizontal, 18)
        .overlay(alignment: .top) { Rectangle().fill(Color.rule).frame(height: 1).padding(.horizontal, 18) }
    }

    private var headline: String {
        guard setup.hasRun else { return "setup" }
        return setup.blocking == 0 ? "setup done" : "\(setup.blocking) to set up"
    }
}

private struct SetupRow: View {
    let check: SetupCheck
    @ObservedObject var setup: SetupModel
    /// Under the "Optional" label, which already says it, so the detail drops its own "optional ·".
    var optional = false

    private var detail: String? {
        guard optional, let detail = check.detail else { return check.detail }
        if detail == "optional" { return nil }
        return detail.hasPrefix("optional · ") ? String(detail.dropFirst("optional · ".count)) : detail
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Dot(color: color, size: 8).offset(y: 1)
            VStack(alignment: .leading, spacing: 1) {
                // Passing and switched-off rows step back: only what needs a look stays white.
                Text(check.title).font(check.status == .fail ? .bodyStrong : .body)
                    .foregroundStyle(check.status == .pass || check.status == .off ? Color.dim : .white)
                if let detail {
                    Text(detail).font(.detail).foregroundStyle(Color.dim).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The row text reads as one element and the fix stays a separate, pressable button.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([check.title, statusWord, check.detail].compactMap { $0 }.joined(separator: ", "))
            if let fix = check.fix { FixLink(fix: fix, setup: setup, quiet: optional) }
        }
        .padding(.vertical, 5)
        // The dashboard's 43pt row, so the checklist and the PR list share one rhythm.
        .frame(minHeight: ExpandedView.rowHeight)
        // The highlight reaches past the text by the same inset as a PR row's.
        .padding(.horizontal, ExpandedView.rowInset)
        .modifier(RowHighlight(focused: setup.focusedCheck == check.id))
        .overlay(alignment: .top) { Rectangle().fill(Color.rule).frame(height: 1).padding(.horizontal, ExpandedView.rowInset) }
        .padding(.horizontal, 18 - ExpandedView.rowInset)
        .accessibilityElement(children: .contain)
    }

    private var color: Color {
        switch check.status {
        case .pass: return .good
        case .fail: return .bad
        case .warn: return .warn
        case .off: return .standby
        }
    }

    private var statusWord: String {
        switch check.status {
        case .pass: return "passing"
        case .fail: return "failing"
        case .warn: return "warning"
        case .off: return "off"
        }
    }
}

/// A setup fix as a plain blue link, in the checklist and under a dashboard error. When the
/// click has no other visible effect the link says so: "checking…" for as long as a retry runs,
/// or the feedback `apply` returns ("copied") for a moment.
struct FixLink: View {
    let fix: SetupCheck.Fix
    @ObservedObject var setup: SetupModel
    /// An optional fix: Dimmed Grey until hovered, so required fixes lead the eye.
    var quiet = false
    @State private var hovering = false
    @State private var feedback: String?
    @State private var clear: Task<Void, Never>?

    private var shown: String? { fix == .retry && setup.retrying ? "checking…" : feedback }

    var body: some View {
        Button(shown ?? fix.label) {
            guard let said = setup.apply(fix) else { return }
            feedback = said
            clear?.cancel()
            clear = Task {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                feedback = nil
            }
        }
        .buttonStyle(.plain)
        .font(.detail)
        .foregroundStyle(shown == nil && (!quiet || hovering) ? Color.link : Color.dim)
        .onHover { hovering = $0 }
    }
}
