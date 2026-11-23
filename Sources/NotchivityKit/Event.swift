import Foundation

/// Something that changed between two fetches and deserves a peek or a notification.
public struct Event: Equatable, Identifiable {
    public enum Kind: String, CaseIterable {
        case ciFailed, conflicts, changesRequested, newThreads, approved, ready, merged
        case usageThreshold, limitReset, spendThreshold, fetchBroken
        /// The one-time "ready" peek the first time setup passes. Never a notification.
        case welcome

        public static var configurable: [Kind] { allCases.filter { $0 != .welcome } }

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
            case .limitReset: return "Usage reset"
            case .spendThreshold: return "Spend alert"
            case .fetchBroken: return "PR fetch failing"
            case .welcome: return "Setup done"
            }
        }

        /// Kinds that also post to Notification Center out of the box. Everything peeks.
        public var notifiesByDefault: Bool {
            switch self {
            case .ciFailed, .conflicts, .changesRequested, .approved, .ready, .usageThreshold, .spendThreshold: return true
            case .newThreads, .merged, .limitReset, .fetchBroken, .welcome: return false
            }
        }

        /// How a burst summary names the events it stands in for, counted only past one.
        func counted(_ n: Int) -> String {
            let label: String
            switch self {
            case .ciFailed: label = "CI failed"
            case .conflicts: label = "conflicts"
            case .changesRequested: label = "changes requested"
            case .newThreads: label = "new comments"
            case .approved: label = "approved"
            case .ready: label = "ready to merge"
            case .merged: label = "merged"
            case .usageThreshold: label = n > 1 ? "usage alerts" : "usage alert"
            case .limitReset: label = n > 1 ? "usage resets" : "usage reset"
            case .spendThreshold: label = n > 1 ? "spend alerts" : "spend alert"
            case .fetchBroken: label = "PR fetch failing"
            case .welcome: label = "setup done"
            }
            return n > 1 ? "\(n) \(label)" : label
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
        // Last one wins: a duplicate id must not crash the poll.
        let before = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        for pr in new {
            guard let was = before[pr.id] else { continue }
            if pr.ci == .failure && was.ci != .failure {
                events.append(.init(kind: .ciFailed, headline: "CI failed · \(pr.shortRef)", detail: pr.title, tone: .bad, url: pr.url))
            }
            if pr.conflicts && !was.conflicts {
                events.append(.init(kind: .conflicts, headline: "conflicts · \(pr.shortRef)", detail: pr.title, tone: .bad, url: pr.url))
            }
            if pr.changesRequested && !was.changesRequested {
                events.append(.init(kind: .changesRequested, headline: "changes requested · \(pr.shortRef)", detail: pr.title, tone: .warn, url: pr.url))
            }
            if pr.unresolvedThreads > was.unresolvedThreads {
                let n = pr.unresolvedThreads - was.unresolvedThreads
                events.append(.init(kind: .newThreads, headline: "\(plural(n, "new comment")) · \(pr.shortRef)", detail: pr.title, tone: .warn, url: pr.url))
            }
            if pr.approvals > 0 && was.approvals == 0 {
                events.append(.init(kind: .approved, headline: "approved · \(pr.shortRef)", detail: pr.title, tone: .good, url: pr.url))
            }
            if pr.category == .ready && was.category != .ready {
                events.append(.init(kind: .ready, headline: "ready to merge · \(pr.shortRef)", detail: pr.title, tone: .good, url: pr.url))
            }
        }
        return events
    }

    /// One peek standing in for a burst: the most urgent event leads ("CI failed · web#322 ·
    /// 3 more") and the rest are counted by kind in arrival order ("new comments · 2 approved"),
    /// rather than naming one of them as if it were the only other.
    public static func summary(_ events: [Event]) -> Event {
        let worst = events.max { $0.tone.severity < $1.tone.severity } ?? events[0]
        let rest = events.filter { $0.id != worst.id }
        var kinds: [Event.Kind] = []
        for event in rest where !kinds.contains(event.kind) { kinds.append(event.kind) }
        let detail = kinds.map { kind in kind.counted(rest.filter { $0.kind == kind }.count) }.joined(separator: " · ")
        return Event(kind: worst.kind, headline: "\(worst.headline) · \(rest.count) more", detail: detail, tone: worst.tone, url: worst.url)
    }

    /// PRs present before and gone now. The caller decides merged vs closed.
    public static func departed(old: [PullRequest], new: [PullRequest]) -> [PullRequest] {
        let ids = Set(new.map(\.id))
        return old.filter { !ids.contains($0.id) }
    }

    public static func merged(_ pr: PullRequest) -> Event {
        .init(kind: .merged, headline: "merged · \(pr.shortRef)", detail: pr.title, tone: .info, url: pr.url)
    }

    public static func usage(old: [AccountUsage], new: [AccountUsage], thresholds: [Double] = defaultThresholds) -> [Event] {
        var events: [Event] = []
        // Last one wins: a duplicate id must not crash the poll.
        let before = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        for account in new where account.error == nil {
            guard let was = before[account.id], was.error == nil else { continue }
            for window in AccountUsage.Window.allCases {
                guard let now = account.pct(window), let then = was.pct(window) else { continue }
                if let crossed = thresholds.sorted().last(where: { then < $0 && now >= $0 }) {
                    // Near the limit, name another account of the same provider that has room.
                    let spare =
                        crossed < 90
                        ? nil
                        : new.first {
                            $0.id != account.id && $0.provider == account.provider && $0.failure == nil && ($0.pct(window) ?? 100) < 50
                        }
                    let reset = account.resetsAt(window).map { TimeFormatting.countdown(secondsRemaining: Int($0 - Date().timeIntervalSince1970)) }
                    let detail = [reset.map { "resets \($0)" }, spare.map { "\($0.displayLabel) has \(100 - Int($0.pct(window) ?? 0))% free" }]
                        .compactMap { $0 }.joined(separator: " · ")
                    events.append(
                        .init(
                            kind: .usageThreshold,
                            headline: "\(window.rawValue) at \(Int(now))% · \(account.displayLabel)",
                            detail: detail.isEmpty ? nil : detail, tone: crossed >= 90 ? .bad : crossed >= 75 ? .warn : .dim))
                }
                if then >= 20 && now < then - 15 {
                    events.append(
                        .init(
                            kind: .limitReset, headline: "\(window.rawValue) reset · \(account.displayLabel)",
                            detail: "\(Int(then))% → \(Int(now))%", tone: .info))
                }
            }
        }
        return events
    }

    public static let defaultSpendThresholds: [Double] = [75, 100]

    /// Today's and this week's spend crossing a percentage of its limit. A limit of 0 is off.
    /// A new day or week starts from $0, so the first read after midnight can cross too.
    public static func spend(
        old: Spend, new: Spend, dailyLimit: Double, weeklyLimit: Double, thresholds: [Double] = defaultSpendThresholds
    ) -> [Event] {
        let sameWeek = old.weekStart == new.weekStart
        let periods = [
            (name: "today", then: sameWeek && old.today == new.today ? old.todayCost : 0, now: new.todayCost, limit: dailyLimit),
            (name: "this week", then: sameWeek ? old.weekCost : 0, now: new.weekCost, limit: weeklyLimit),
        ]
        return periods.compactMap { period in
            guard period.limit > 0,
                let crossed = thresholds.sorted().last(where: { period.then < period.limit * $0 / 100 && period.now >= period.limit * $0 / 100 })
            else { return nil }
            let pct = Int(period.now / period.limit * 100)
            let detail =
                period.name == "today"
                ? "week \(Spend.money(new.weekCost))" + (weeklyLimit > 0 ? " of \(Spend.limit(weeklyLimit))" : "")
                : "today \(Spend.money(new.todayCost)) · resets Mon"
            return Event(
                kind: .spendThreshold, headline: "spend at \(pct)% \(period.name) · \(Spend.money(period.now)) of \(Spend.limit(period.limit))",
                detail: detail, tone: crossed >= 90 ? .bad : crossed >= 75 ? .warn : .dim)
        }
    }
}
