import NotchivityKit
import SwiftUI

extension Color {
    static let bad = Color(red: 0.97, green: 0.32, blue: 0.29)
    static let warn = Color(red: 0.82, green: 0.60, blue: 0.13)
    static let good = Color(red: 0.25, green: 0.73, blue: 0.31)
    static let info = Color(red: 0.74, green: 0.55, blue: 1.0)
    static let link = Color(red: 0.35, green: 0.65, blue: 1.0)
    static let dim = Color(white: 0.47)
    static let standby = Color(white: 0.25)
    static let stroke = Color(white: 0.2)
    static let track = Color(white: 0.13)
    static let rule = Color(white: 0.09)
    static let hover = Color(white: 0.06)

    init(_ tone: Tone) {
        switch tone {
        case .bad: self = .bad
        case .warn: self = .warn
        case .good: self = .good
        case .dim: self = .dim
        case .info: self = .info
        }
    }

    static func tone(for category: PRCategory) -> Color {
        switch category {
        case .failing: return .bad
        case .needsAction: return .warn
        case .ready: return .good
        case .awaitingReview: return .link
        }
    }

    /// White under 75%, amber to 90%, red above.
    static func usage(_ pct: Double) -> Color {
        pct >= 90 ? .bad : pct >= 75 ? .warn : .white
    }
}

/// The five sizes the app uses. Every value that ticks goes through these, so digits stay steady.
/// `title` and `body` deliberately shadow SwiftUI's statics of the same name inside this module:
/// the 28pt system title has no place in the notch.
extension Font {
    /// Peek headline only.
    static let title = Font.system(size: 13, weight: .semibold).monospacedDigit()
    /// PR titles, failing check titles, Settings body.
    static let bodyStrong = Font.system(size: 12.5, weight: .semibold).monospacedDigit()
    /// Usage labels and percentages, empty-state lines, Settings tabs.
    static let body = Font.system(size: 12, weight: .medium).monospacedDigit()
    /// Refs, flags, ages, sub-labels, links, chips.
    static let detail = Font.system(size: 11).monospacedDigit()
    /// Uppercase tracked section titles.
    static let label = Font.system(size: 10.5, weight: .semibold).monospacedDigit()
}

struct Bar: View {
    let pct: Double?
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.track)
                if let pct {
                    Capsule().fill(Color.usage(pct)).frame(width: max(height, proxy.size.width * CGFloat(min(pct, 100) / 100)))
                }
            }
        }
        .frame(height: height)
    }
}

struct Dot: View {
    let color: Color
    var size: CGFloat = 7
    var body: some View { Circle().fill(color).frame(width: size, height: size) }
}
