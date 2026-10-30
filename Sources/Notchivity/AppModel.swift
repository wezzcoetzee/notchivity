import AppKit
import NotchivityKit

/// Owns both data sources, diffs each fetch against the last, and fans events out to the
/// peek queue and Notification Center.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var accounts: [AccountUsage] = []
    @Published private(set) var prs: [PullRequest] = []
    @Published private(set) var me = ""
    @Published private(set) var prFailure: Error?
    @Published private(set) var lastUsageAt: Date?
    @Published private(set) var lastPRsAt: Date?
    @Published private(set) var peek: Event?
    @Published private(set) var slackStatus: String?
    /// "view all" toggled in the expanded PR list; reset when the panel collapses.
    @Published var showAllPRs = false
    /// PR ids picked with Cmd-click or "Select" for one batched Slack ask; reset when the panel collapses.
    @Published var selectedPRs: Set<String> = []
    /// Bumped on a timer so countdowns and "updated Ns ago" re-render.
    @Published private(set) var now = Date()

    static let prInterval: TimeInterval = 60
    static let rateLimitRetry: TimeInterval = 30

    let setup = SetupModel()
    /// Claude first, so the collapsed underline and `primary` stay on a Claude account.
    private let usageSources: [any UsageSource] = [UsageFetcher(), CodexUsageSource(), GrokUsageSource()]
    private let prFetcher = PRFetcher()
    private let settings = Settings.shared
    private var peekQueue: [Event] = []
    private var peekTask: Task<Void, Never>?
    private var prRefresh: Task<Void, Never>?
    private var lastPRAttemptAt: Date?
    private var consecutivePRFailures = 0

    func start() {
        setup.usageProvider = { [weak self] in
            guard let self else { return [] }
            if usageIsStale { await refreshUsage() }
            return accounts
        }
        setup.prsProvider = { [weak self] in
            guard let self else { return nil }
            if prsAreStale { await refreshPRs() }
            return prFailure.map { .failure($0) } ?? .success((me: me, prs: prs))
        }
        Task {
            await setup.run()
            setup.startRechecking()
        }
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(settings.usageInterval))
                if usageIsStale { await refreshUsage() }
            }
        }
        Task { await loop(every: Self.prInterval) { await self.refreshPRs() } }
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                now = Date()
            }
        }
    }

    private func loop(every interval: TimeInterval, _ work: @escaping () async -> Void) async {
        while !Task.isCancelled {
            await work()
            try? await Task.sleep(for: .seconds(interval))
        }
    }

    func refreshAll() {
        Task { await refreshUsage() }
        Task { await refreshPRs() }
    }

    /// Called when the panel opens. PRs refetch if more than a few seconds old; usage only
    /// when its full interval has passed, so hovering never adds usage endpoint calls.
    func refreshIfStale() {
        if usageIsStale { Task { await refreshUsage() } }
        if prsAreStale { Task { await refreshPRs() } }
    }

    private var usageIsStale: Bool {
        lastUsageAt.map { Date().timeIntervalSince($0) >= settings.usageInterval - 1 } ?? true
    }

    /// Measured from the last attempt, so a failing fetch is not retried on every hover.
    private var prsAreStale: Bool {
        lastPRAttemptAt.map { Date().timeIntervalSince($0) > 20 } ?? true
    }

    /// A 429 keeps the last reading; the warning only shows once that reading is old.
    func usageWarning(_ account: AccountUsage) -> String? {
        guard let failure = account.failure else { return nil }
        if failure == .http(429), let lastGood = lastGoodUsageAt,
           Date().timeIntervalSince(lastGood) < settings.usageInterval * 2 { return nil }
        return failure.description
    }

    private var lastGoodUsageAt: Date?
    private var rateLimitRetryScheduled = false

    func refreshUsage() async {
        let previous = accounts
        var fresh: [AccountUsage] = []
        for source in usageSources { fresh += await source.fetch(previous: previous).map(named) }
        if !previous.isEmpty { dispatch(EventDiff.usage(old: previous, new: fresh, thresholds: settings.thresholds)) }
        accounts = fresh
        lastUsageAt = Date()
        now = Date()
        if fresh.contains(where: { $0.failure == nil }) { lastGoodUsageAt = Date() }
        if fresh.contains(where: { $0.failure == .http(429) }), !rateLimitRetryScheduled {
            rateLimitRetryScheduled = true
            Task {
                try? await Task.sleep(for: .seconds(Self.rateLimitRetry))
                rateLimitRetryScheduled = false
                await refreshUsage()
            }
        }
    }

    /// Concurrent callers (poll loop, hover, setup check) share one in-flight fetch.
    func refreshPRs() async {
        if let inflight = prRefresh { return await inflight.value }
        let task = Task { await fetchPRs() }
        prRefresh = task
        await task.value
        prRefresh = nil
    }

    private func fetchPRs() async {
        defer { lastPRAttemptAt = Date() }
        do {
            let (login, fresh) = try await prFetcher.fetch()
            let previous = prs
            let hadData = lastPRsAt != nil
            me = login
            prs = fresh
            selectedPRs.formIntersection(fresh.map(\.id))
            prFailure = nil
            consecutivePRFailures = 0
            lastPRsAt = Date()
            now = Date()
            guard hadData else { return }
            dispatch(EventDiff.prs(old: previous, new: fresh))
            for gone in EventDiff.departed(old: previous, new: fresh) where await prFetcher.wasMerged(gone) {
                dispatch([EventDiff.merged(gone)])
            }
        } catch {
            prFailure = error
            consecutivePRFailures += 1
            if consecutivePRFailures == 3 {
                dispatch([Event(kind: .fetchBroken, headline: "PR fetch failing", detail: prError, tone: .warn)])
            }
        }
    }

    private func dispatch(_ events: [Event]) {
        for event in events {
            if settings.notifies(event.kind) { Notifier.shared.post(event) }
            if settings.peekEnabled { peekQueue.append(event) }
        }
        showNextPeek()
    }

    private func showNextPeek() {
        guard peek == nil, !peekQueue.isEmpty else { return }
        peek = peekQueue.removeFirst()
    }

    /// The window reports when the peek is actually on screen; only then does its clock
    /// start, so an event that lands mid-hover waits until the hover ends.
    func peekShown() {
        peekTask?.cancel()
        peekTask = Task {
            try? await Task.sleep(for: .seconds(settings.peekDuration))
            guard !Task.isCancelled else { return }
            dismissPeek()
        }
    }

    /// Withdraws the current peek and moves on to the next queued one after a short gap.
    func dismissPeek() {
        peekTask?.cancel()
        peek = nil
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            showNextPeek()
        }
    }

    /// Screenshot aid for `NOTCHIVITY_STATE=peek`.
    func showSamplePeek() {
        peek = Event(kind: .ready, headline: "vello-pet-owner-profile#666 is ready to merge",
                     detail: "approved · CI ✓", tone: .good)
    }

    /// Fills the model with fixed sample data for `--screenshots`, bypassing every fetch.
    func loadDemo(me: String, accounts: [AccountUsage], prs: [PullRequest], peek: Event) {
        self.me = me
        self.accounts = accounts
        self.prs = prs
        self.peek = peek
        lastUsageAt = now.addingTimeInterval(-12)
        lastPRsAt = lastUsageAt
    }

    func toggleSelection(_ pr: PullRequest) {
        if selectedPRs.remove(pr.id) == nil { selectedPRs.insert(pr.id) }
    }

    func askForReview(_ pr: PullRequest) { askForReview([pr]) }

    /// Sends every selected PR in one Slack message and clears the selection on success.
    func askForReviewOfSelection() {
        askForReview(orderedPRs.filter { selectedPRs.contains($0.id) })
    }

    private func askForReview(_ batch: [PullRequest]) {
        guard let first = batch.first else { return }
        let what = batch.count == 1 ? first.shortRef : plural(batch.count, "PR")
        slackStatus = "posting \(what) to Slack…"
        Task {
            do {
                let outcome = try await SlackNudger().askForReview(batch)
                slackStatus = outcome == .nudged ? "nudged \(what) in its thread" : "posted \(what) to Slack"
                selectedPRs.subtract(batch.map(\.id))
            } catch {
                slackStatus = "slack post failed"
            }
            try? await Task.sleep(for: .seconds(5))
            slackStatus = nil
        }
    }

    // MARK: - Derived

    var primary: AccountUsage? { accounts.first }

    /// One lowercase line for the PR column when the last fetch failed.
    var prError: String? { prFailure.map { Shell.summary($0, fallback: "pr fetch failed") } }

    /// How old a disk-read reading is, for sources that only move when their tool runs.
    /// Nil while it is recent enough that saying so would be noise.
    func staleness(_ account: AccountUsage) -> String? {
        guard let observedAt = account.observedAt else { return nil }
        let date = Date(timeIntervalSince1970: observedAt)
        guard now.timeIntervalSince(date) > 15 * 60 else { return nil }
        return "as of \(age(date)) ago"
    }

    /// Re-applies the names typed in Settings to the readings already on screen.
    func applyAccountNames() { accounts = accounts.map(named) }

    /// Overlays the user's name for an account, if they gave it one.
    private func named(_ account: AccountUsage) -> AccountUsage {
        var named = account
        let custom = settings.accountNames[account.id]?.trimmingCharacters(in: .whitespaces)
        named.customLabel = custom?.isEmpty == false ? custom : nil
        return named
    }

    /// The account behind the collapsed underline, per settings.
    var underlineAccount: AccountUsage? {
        accounts.first { $0.id == settings.underlineAccount } ?? primary
    }

    /// PRs in the user's category order, drafts removed if asked.
    var orderedPRs: [PullRequest] {
        let visible = settings.hideDrafts ? prs.filter { !$0.draft } : prs
        return settings.categoryOrder.flatMap { category in visible.filter { $0.category == category } }
    }
    var slackConfigured: Bool { Config.load().slackConfigured }

    func count(_ category: PRCategory) -> Int { prs.filter { $0.category == category }.count }

    var freshness: String {
        let stamps = [lastUsageAt, lastPRsAt].compactMap { $0 }
        guard let oldest = stamps.min() else { return "loading…" }
        return TimeFormatting.freshness(secondsAgo: Int(now.timeIntervalSince(oldest)))
    }

    func countdown(_ epoch: Double?) -> String? {
        epoch.map { TimeFormatting.countdown(secondsRemaining: Int($0 - now.timeIntervalSince1970)) }
    }

    /// Weekly resets are days away, so a weekday and time reads better than a countdown.
    func resetDay(_ epoch: Double?) -> String? {
        guard let epoch else { return nil }
        let date = Date(timeIntervalSince1970: epoch)
        let formatter = DateFormatter()
        formatter.dateFormat = date.timeIntervalSince(now) < 86_400 ? "HH:mm" : "EEE HH:mm"
        return formatter.string(from: date)
    }

    func age(_ date: Date) -> String {
        let s = Int(now.timeIntervalSince(date))
        if s < 3600 { return "\(max(1, s / 60))m" }
        if s < 86_400 { return "\(s / 3600)h" }
        return "\(s / 86_400)d"
    }
}
