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
            HStack {
                Text(headline)
                Spacer()
                Text(setup.running ? "checking…" : "rechecks every \(Int(SetupModel.recheckInterval))s")
            }
            .font(.detail).foregroundStyle(Color.dim)
            .padding(.horizontal, 18)
            .frame(height: geometry.notchHeight)
            .padding(.bottom, 8)

            if setup.checks.isEmpty {
                Text("running checks…").font(.body).foregroundStyle(Color.dim).padding(.horizontal, 18)
            }
            ForEach(setup.checks) { check in
                row(check)
            }
            if setup.blocking == 0, setup.hasRun {
                HStack {
                    Text("all required checks pass").foregroundStyle(Color.dim)
                    Spacer()
                    Button("done") { setup.pinned = false }.buttonStyle(.plain).foregroundStyle(Color.link)
                }
                .font(.detail)
                .padding(.horizontal, 18).padding(.top, 10)
            }
        }
        .padding(.bottom, 14)
        .frame(width: Self.width)
    }

    private var headline: String {
        let passing = setup.required.filter { $0.status == .pass }.count
        return "setup · \(passing) of \(setup.required.count) required passing"
    }

    private func row(_ check: SetupCheck) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Dot(color: color(check.status), size: 8).offset(y: 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(check.title).font(check.status == .fail ? .bodyStrong : .body)
                if let detail = check.detail {
                    Text(detail).font(.detail).foregroundStyle(Color.dim).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let fix = check.fix {
                Button(fix.label) { setup.apply(fix) }
                    .buttonStyle(.plain)
                    .font(.detail)
                    .foregroundStyle(Color.link)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 18)
        .overlay(alignment: .top) { Rectangle().fill(Color.rule).frame(height: 1).padding(.horizontal, 18) }
    }

    private func color(_ status: SetupCheck.Status) -> Color {
        switch status {
        case .pass: return .good
        case .fail: return .bad
        case .warn: return .warn
        case .off: return .standby
        }
    }
}
