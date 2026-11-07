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
    /// The transient line under the PR list after a Slack ask.
    @Published private(set) var slackStatus: SlackStatus?
    /// "view all" toggled in the expanded PR list; reset when the panel collapses.
    @Published var showAllPRs = false
    /// PR ids picked with Cmd-click or "Select" for one batched Slack ask; reset when the panel collapses.
    @Published var selectedPRs: Set<String> = []
    /// Bumped on a timer so countdowns and "updated Ns ago" re-render.
    @Published private(set) var now = Date()

    static let prInterval: TimeInterval = 60

    let setup = SetupModel()
    private let usageReader = UsageReader()
    private let prFetcher = PRFetcher()
    private let settings = Settings.shared
    private var peekQueue: [Event] = []
    private var peekTask: Task<Void, Never>?
    private var prRefresh: Task<Void, Never>?
    private var usageRefresh: Task<Void, Never>?
    private var lastPRAttemptAt: Date?
    private var consecutivePRFailures = 0
    private var slackStatusClear: Task<Void, Never>?

    struct SlackStatus {
        let text: String
        var failed = false
        var posting = false
    }

    func start() {
        setup.usageProvider = { [weak self] in
            guard let self else { return [] }
            if usageIsStale { await refreshUsage() }
            return accounts
        }
        setup.openSettings = { [weak self] in
            guard let self else { return }
            SettingsWindowController.shared.show(model: self, tab: .general)
        }
        // A fix (open Claude Code, retry) earns a fresh round of quick retries to pick it up.
        setup.fixApplied = { [weak self] in self?.transientStreak = 0 }
        setup.refresh = { [weak self] in
            guard let self else { return }
            async let usage: Void = refreshUsage()
            async let prs: Void = refreshPRs()
            _ = await (usage, prs)
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
        Task { await loop(every: Self.prInterval) { await self.refreshPRs() } }
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                now = Date()
                // The one usage poll: the interval, the quick retry for a transient failure, and a
                // passed reset all come through here, so none of them waits for a hover. Not
                // awaited, so a slow fetch never freezes the countdowns.
                if usageIsStale || resetPassedSinceLastRead { Task { await refreshUsage() } }
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
        reloadConfig()
        transientStreak = 0
        if usageIsStale { Task { await refreshUsage() } }
        if prsAreStale { Task { await refreshPRs() } }
    }

    /// A window's reset time fell between the last read and now, so the reading is known to be old.
    private var resetPassedSinceLastRead: Bool {
        guard let last = lastUsageAt?.timeIntervalSince1970 else { return false }
        let now = now.timeIntervalSince1970
        return accounts.contains { account in
            account.windows.contains { window in account.resetsAt(window).map { $0 > last && $0 <= now } ?? false }
        }
    }

    /// A transient failure (expired token, network) retries after a minute, so its fix shows up
    /// without waiting out the full interval. Persistent states (no Grok snapshot yet, a rate
    /// limit, the keychain prompt) wait the interval like everything else.
    private var usageIsStale: Bool {
        guard let last = lastUsageAt else { return true }
        // Every retry refetches every account, so it stops after a few tries and never runs while
        // any account is rate limited. Setup "retry" and Refresh Now stay available by hand.
        let quick =
            transientStreak < 4 && accounts.contains { $0.failure?.isTransient == true }
            && !accounts.contains { $0.failure == .http(429) }
        return Date().timeIntervalSince(last) >= (quick ? min(60, settings.usageInterval) : settings.usageInterval) - 1
    }

    /// Measured from the last attempt, so a failing fetch is not retried on every hover.
    private var prsAreStale: Bool {
        lastPRAttemptAt.map { Date().timeIntervalSince($0) > 20 } ?? true
    }

    /// A 429 keeps the last reading; the warning only shows once that reading is old, or at
    /// once when there is no reading to keep.
    func usageWarning(_ account: AccountUsage) -> String? {
        guard let failure = account.failure else { return nil }
        if failure == .http(429), account.primaryPct != nil, let lastGood = lastGoodUsageAt[account.id],
            Date().timeIntervalSince(lastGood) < settings.usageInterval * 2
        {
            return nil
        }
        return failure.short
    }

    /// The reading behind a usage figure is in doubt: its refresh failed, or it was recorded long ago.
    func isOld(_ account: AccountUsage) -> Bool { usageWarning(account) != nil || staleness(account) != nil }

    /// The percentage to show for one window. An old reading whose window has since reset says
    /// nothing about now, so it becomes unknown; the panel and the collapsed tab share this.
    func displayPct(_ account: AccountUsage, _ window: AccountUsage.Window) -> Double? {
        if isOld(account), let reset = account.resetsAt(window), reset <= now.timeIntervalSince1970 { return nil }
        return account.pct(window)
    }

    /// Consecutive fetches that came back with a transient failure; caps the quick retry. Reset
    /// by a hover or an applied fix, so the user's own action is always picked up quickly.
    private var transientStreak = 0

    /// Per account, so one account reading fine cannot hide another's long-running rate limit.
    private var lastGoodUsageAt: [String: Date] = [:]

    func refreshUsage() async {
        if let inflight = usageRefresh { return await inflight.value }
        let task = Task {
            await fetchUsage()
            usageRefresh = nil
        }
        usageRefresh = task
        await task.value
    }

    func usageConfigurationChanged() async {
        if let inflight = usageRefresh { await inflight.value }
        accounts = []
        lastUsageAt = nil
        lastGoodUsageAt = [:]
        await refreshUsage()
        await setup.run()
    }

    private func fetchUsage() async {
        let previous = accounts
        let fresh = await usageReader.fetch(previous: previous).map(named)
        if !previous.isEmpty { dispatch(EventDiff.usage(old: previous, new: fresh, thresholds: settings.thresholds)) }
        accounts = fresh
        lastUsageAt = Date()
        now = Date()
        for account in fresh where account.failure == nil { lastGoodUsageAt[account.id] = Date() }
        transientStreak = fresh.contains { $0.failure?.isTransient == true } ? transientStreak + 1 : 0
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

    /// An approval that makes a PR ready raises both events; "ready to merge" stands for both
    /// unless its notification is switched off, so the per-kind toggles still mean what they say.
    private func dispatch(_ events: [Event]) {
        let ready = Set(events.filter { $0.kind == .ready }.compactMap(\.url))
        for event in events {
            let covered = event.kind == .approved && event.url.map(ready.contains) == true
            if settings.notifies(event.kind), !(covered && settings.notifies(.ready)) { Notifier.shared.post(event) }
            if settings.peekEnabled, !covered { peekQueue.append(event) }
        }
        showNextPeek()
    }

    /// A burst (a CI storm, waking from sleep) becomes one summary peek instead of a queue
    /// of three-second peeks that would hold the notch for half a minute.
    private func showNextPeek() {
        guard peek == nil, !peekQueue.isEmpty else { return }
        if peekQueue.count > 2 {
            peek = EventDiff.summary(peekQueue)
            peekQueue = []
        } else {
            peek = peekQueue.removeFirst()
        }
    }

    /// The window reports when the peek is actually on screen; only then does its clock
    /// start, so an event that lands mid-hover waits until the hover ends.
    /// `restart: false` keeps a running clock, so brushing past a peek does not extend it.
    func peekShown(restart: Bool = true) {
        guard restart || peekTask == nil else { return }
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
        peekTask = nil
        peek = nil
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            showNextPeek()
        }
    }

    /// Screenshot aid for `NOTCHIVITY_STATE=peek`.
    func showSamplePeek() {
        peek = Event(
            kind: .ready, headline: "vello-pet-owner-profile#666 ready to merge",
            detail: "feat: pet owner profile photos", tone: .good)
    }

    /// Fills the model with fixed sample data for `--screenshots`, bypassing every fetch.
    func loadDemo(me: String, accounts: [AccountUsage], prs: [PullRequest], peek: Event, prFailure: Error? = nil) {
        self.me = me
        self.accounts = accounts
        self.prs = prs
        self.peek = peek
        self.prFailure = prFailure
        lastUsageAt = now.addingTimeInterval(-12)
        lastPRsAt = prFailure == nil ? lastUsageAt : nil
    }

    /// Screenshot aid: the transient Slack line under the dashboard.
    func loadDemoStatus(slack: String, failed: Bool = false) { slackStatus = SlackStatus(text: slack, failed: failed) }

    func toggleSelection(_ pr: PullRequest) {
        if selectedPRs.remove(pr.id) == nil { selectedPRs.insert(pr.id) }
    }

    func askForReview(_ pr: PullRequest) { askForReview([pr]) }

    /// Sends every selected PR in one Slack message and clears the selection on success.
    func askForReviewOfSelection() {
        askForReview(orderedPRs.filter { selectedPRs.contains($0.id) })
    }

    /// One ask at a time, so a double click cannot post twice.
    private func askForReview(_ batch: [PullRequest]) {
        guard let first = batch.first, slackStatus?.posting != true else { return }
        let what = batch.count == 1 ? first.shortRef : plural(batch.count, "PR")
        slackStatusClear?.cancel()
        slackStatus = SlackStatus(text: "posting \(what) to Slack…", posting: true)
        Task {
            do {
                let outcome = try await SlackNudger().askForReview(batch)
                showSlackStatus(SlackStatus(text: outcome == .nudged ? "nudged \(what) in its thread" : "posted \(what) to Slack"))
                selectedPRs.subtract(batch.map(\.id))
            } catch {
                showSlackStatus(SlackStatus(text: SlackNudger.failureSummary(error), failed: true))
            }
        }
    }

    private func showSlackStatus(_ status: SlackStatus) {
        slackStatus = status
        slackStatusClear = Task {
            try? await Task.sleep(for: .seconds(status.failed ? 8 : 5))
            guard !Task.isCancelled else { return }
            slackStatus = nil
        }
    }

    // MARK: - Derived

    var primary: AccountUsage? { accounts.first }

    /// One lowercase line for the PR column when the last fetch failed.
    var prError: String? { prFailure.map { Shell.summary($0, fallback: "PR fetch failed") } }

    /// The setup fix for the PR error, shown under it like a usage error's fix.
    var prFix: SetupCheck.Fix? {
        guard let prError else { return nil }
        return prError == Shell.signedOut ? .copy("gh auth login") : .retry
    }

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
    /// Cached so rows do not re-read the config file on every render; Settings calls
    /// `reloadConfig()` after it writes.
    @Published private(set) var slackConfigured = Config.load().slackConfigured

    func reloadConfig() { slackConfigured = Config.load().slackConfigured }

    func count(_ category: PRCategory) -> Int { orderedPRs.filter { $0.category == category }.count }

    var freshness: String {
        // Names the source when only usage has read, so "updated 12s ago" never vouches for PRs that never loaded.
        switch (lastUsageAt, lastPRsAt) {
        case let (usage?, prs?): return TimeFormatting.freshness(secondsAgo: Int(now.timeIntervalSince(min(usage, prs))))
        case let (usage?, nil): return "usage " + TimeFormatting.freshness(secondsAgo: Int(now.timeIntervalSince(usage)))
        default: return ""
        }
    }

    func countdown(_ epoch: Double?) -> String? {
        epoch.map { TimeFormatting.countdown(secondsRemaining: Int($0 - now.timeIntervalSince1970)) }
    }

    /// Weekly resets are days away, so a weekday and time reads better than a countdown. A
    /// weekday is only unambiguous inside the coming week; a monthly reset further out gets a
    /// date ("26 Nov"), or "Fri" would read as this Friday.
    func resetDay(_ epoch: Double?) -> String? {
        guard let epoch else { return nil }
        let date = Date(timeIntervalSince1970: epoch)
        guard date > now else { return "now" }
        let ahead = date.timeIntervalSince(now)
        let formatter = DateFormatter()
        // A bare time only for today; tomorrow 08:36 would read as a time already past.
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : ahead < 6 * 86_400 ? "EEE HH:mm" : "d MMM"
        return formatter.string(from: date)
    }

    func age(_ date: Date) -> String {
        let s = Int(now.timeIntervalSince(date))
        if s < 3600 { return "\(max(1, s / 60))m" }
        if s < 86_400 { return "\(s / 3600)h" }
        return "\(s / 86_400)d"
    }
}
