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
                Button("close", action: setup.close).buttonStyle(.plain).foregroundStyle(Color.link)
            }
            .font(.detail).foregroundStyle(Color.dim)
            .padding(.horizontal, 18)
            .frame(height: geometry.notchHeight)
            .padding(.bottom, 8)

            if setup.checks.isEmpty {
                Text("running checks…").font(.body).foregroundStyle(Color.dim).padding(.horizontal, 18)
            }
            ForEach(setup.checks) { check in
                SetupRow(check: check, setup: setup)
            }
        }
        .padding(.bottom, 14)
        .frame(width: Self.width)
    }

    private var headline: String {
        guard setup.hasRun else { return "setup" }
        return setup.blocking == 0 ? "setup done" : "\(setup.blocking) to set up"
    }
}

private struct SetupRow: View {
    let check: SetupCheck
    @ObservedObject var setup: SetupModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Dot(color: color, size: 8).offset(y: 1)
            VStack(alignment: .leading, spacing: 1) {
                // Passing and switched-off rows step back, like "CI ✓": only what needs a look stays white.
                Text(check.title).font(check.status == .fail ? .bodyStrong : .body)
                    .foregroundStyle(check.status == .pass || check.status == .off ? Color.dim : .white)
                if let detail = check.detail {
                    Text(detail).font(.detail).foregroundStyle(Color.dim).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The row text reads as one element and the fix stays a separate, pressable button.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([check.title, statusWord, check.detail].compactMap { $0 }.joined(separator: ", "))
            if let fix = check.fix { FixLink(fix: fix, setup: setup) }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 18)
        .overlay(alignment: .top) { Rectangle().fill(Color.rule).frame(height: 1).padding(.horizontal, 18) }
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
        .foregroundStyle(shown == nil ? Color.link : Color.dim)
    }
}
