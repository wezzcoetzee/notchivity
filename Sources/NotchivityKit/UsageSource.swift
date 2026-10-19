import Foundation

/// Which coding subscription a reading came from. Readings are otherwise interchangeable:
/// both providers expose a short session window and a weekly one.
public enum UsageProvider: String, Codable, CaseIterable, Sendable {
    case claude, codex

    public var name: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }
}

/// One place to read usage from. A source returns no readings at all when its tool is not
/// installed or signed in, so the dashboard only shows providers the user actually uses.
public protocol UsageSource: Sendable {
    var provider: UsageProvider { get }
    /// `previous` lets a source keep its last good reading when this poll fails.
    func fetch(previous: [AccountUsage]) async -> [AccountUsage]
}
