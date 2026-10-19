import Foundation

/// Something that changed between two fetches and deserves a peek or a notification.
public struct Event: Equatable, Identifiable {
    public enum Kind: String, CaseIterable, Codable {
        case ciFailed, conflicts, changesRequested, newThreads, approved, ready, merged
        case usageThreshold, limitReset, fetchBroken

        public var title: String {
            switch self {
            case .ciFailed: return "CI failed"
            case .conflicts: return "Merge conflicts"
            case .changesRequested: return "Changes requested"
            case .newThreads: return "New review comments"
            case .approved: return "Approved"
            case .ready: return "Ready to merge"
            case .merged: return "Merged"
            case .usageThreshold: return "Usage threshold"
            case .limitReset: return "Limit reset"
            case .fetchBroken: return "Fetch failing"
            }
        }

        /// Kinds that also post to Notification Center out of the box. Everything peeks.
        public var notifiesByDefault: Bool {
            switch self {
            case .ciFailed, .conflicts, .changesRequested, .approved, .ready, .usageThreshold: return true
            case .newThreads, .merged, .limitReset, .fetchBroken: return false
            }
        }
    }

    public let id = UUID()
    public let kind: Kind
    public let headline: String
    public let detail: String?
    public let tone: Tone
    public let url: URL?

    public init(kind: Kind, headline: String, detail: String? = nil, tone: Tone, url: URL? = nil) {
        self.kind = kind
        self.headline = headline
        self.detail = detail
        self.tone = tone
        self.url = url
    }

    public static func == (a: Event, b: Event) -> Bool {
        a.kind == b.kind && a.headline == b.headline && a.detail == b.detail
    }
}

public enum EventDiff {
    public static let defaultThresholds: [Double] = [50, 75, 90, 100]

    public static func prs(old: [PullRequest], new: [PullRequest]) -> [Event] {
        var events: [Event] = []
        let before = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })
        for pr in new {
            guard let was = before[pr.id] else { continue }
            if pr.ci == .failure && was.ci != .failure {
                events.append(.init(kind: .ciFailed, headline: "CI failed on \(pr.shortRef)", detail: pr.title, tone: .bad, url: pr.url))
            }
            if pr.conflicts && !was.conflicts {
                events.append(.init(kind: .conflicts, headline: "\(pr.shortRef) has conflicts", detail: pr.title, tone: .bad, url: pr.url))
            }
            if pr.changesRequested && !was.changesRequested {
                events.append(.init(kind: .changesRequested, headline: "changes requested on \(pr.shortRef)", detail: pr.title, tone: .warn, url: pr.url))
            }
            if pr.unresolvedThreads > was.unresolvedThreads {
                let n = pr.unresolvedThreads - was.unresolvedThreads
                events.append(.init(kind: .newThreads, headline: "\(plural(n, "new comment")) on \(pr.shortRef)", detail: pr.title, tone: .warn, url: pr.url))
            }
            if pr.approvals > 0 && was.approvals == 0 {
                events.append(.init(kind: .approved, headline: "\(pr.shortRef) approved", detail: pr.title, tone: .good, url: pr.url))
            }
            if pr.category == .ready && was.category != .ready {
                events.append(.init(kind: .ready, headline: "\(pr.shortRef) is ready to merge", detail: pr.title, tone: .good, url: pr.url))
            }
        }
        return events
    }

    /// PRs present before and gone now. The caller decides merged vs closed.
    public static func departed(old: [PullRequest], new: [PullRequest]) -> [PullRequest] {
        let ids = Set(new.map(\.id))
        return old.filter { !ids.contains($0.id) }
    }

    public static func merged(_ pr: PullRequest) -> Event {
        .init(kind: .merged, headline: "\(pr.shortRef) merged", detail: pr.title, tone: .info, url: pr.url)
    }

    public static func usage(old: [AccountUsage], new: [AccountUsage], thresholds: [Double] = defaultThresholds) -> [Event] {
        var events: [Event] = []
        let before = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })
        for account in new where account.error == nil {
            guard let was = before[account.id], was.error == nil else { continue }
            for window in AccountUsage.Window.allCases {
                guard let now = account.pct(window), let then = was.pct(window) else { continue }
                let spare = new.first { $0.id != account.id && ($0.pct(window) ?? 100) < 50 }
                if let crossed = thresholds.sorted().last(where: { then < $0 && now >= $0 }) {
                    let reset = account.resetsAt(window).map { TimeFormatting.countdown(secondsRemaining: Int($0 - Date().timeIntervalSince1970)) }
                    var detail = [reset.map { "resets \($0)" }, spare.map { "\($0.displayLabel) has \(100 - Int($0.pct(window) ?? 0))% free" }]
                        .compactMap { $0 }.joined(separator: " · ")
                    if detail.isEmpty { detail = window.rawValue }
                    events.append(.init(kind: .usageThreshold,
                                        headline: "\(account.displayLabel) \(window.rawValue) at \(Int(crossed))%",
                                        detail: detail, tone: crossed >= 90 ? .bad : crossed >= 75 ? .warn : .dim))
                }
                if then >= 20 && now < then - 15 {
                    events.append(.init(kind: .limitReset, headline: "\(account.displayLabel) \(window.rawValue) window reset",
                                        detail: "\(Int(then))% → \(Int(now))%", tone: .info))
                }
            }
        }
        return events
    }
}
