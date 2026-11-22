import AppKit
import NotchivityKit
import SwiftUI

/// `Notchivity --screenshots <dir>` renders the store images into `<dir>/raw` (the bare views)
/// and `<dir>/framed` (headline and background at 2880×1800, the Mac App Store size);
/// `--gallery <dir>` renders every UI state (setup, errors, empty, collapsed tabs, Settings tabs)
/// for design review. Both use fixed sample data, so no real accounts or PRs appear. See
/// "Screenshots" in README.md.
@MainActor
enum Screenshots {
    static func render(to dir: URL) {
        let expanded = geometry(.expanded)
        let nudge = demoModel()
        nudge.selectedPRs = Set(nudge.orderedPRs.filter { [9, 1204].contains($0.number) }.map(\.id))
        let setup = SetupModel()
        setup.loadDemo(setupChecks)

        let shots: [(name: String, view: AnyView, headline: String, subtitle: String, width: CGFloat)] = [
            (
                "expanded", AnyView(panel(ExpandedView(model: demoModel(), geometry: expanded))),
                "Your limits and PRs, in the notch", "Claude, Codex and Grok usage beside every open pull request", 880
            ),
            (
                "peek", AnyView(peekStack(peeks)),
                "Know the moment it changes", "CI failures, approvals and usage thresholds drop out of the notch", 576
            ),
            (
                "nudge", AnyView(panel(ExpandedView(model: nudge, geometry: expanded))),
                "Ask for review from the notch", "Pick the PRs that are waiting and ask for review in Slack", 880
            ),
            (
                "tab", AnyView(storeTabs()),
                "No notch? You get a tab", "Usage and the PRs that need you, on any external display", 420
            ),
            (
                "setup", AnyView(panel(SetupView(setup: setup, geometry: expanded))),
                "Every problem comes with its fix", "First-run checks for each account, GitHub and Slack", 880
            ),
        ]
        for shot in shots {
            saveStoreImage(shot.view, shot.name, dir.appendingPathComponent("raw"))
            saveFramed(
                shot.view, shot.headline, shot.subtitle, width: shot.width, shot.name, dir.appendingPathComponent("framed"))
        }
    }

    static func gallery(to dir: URL) {
        let expanded = geometry(.expanded)

        save(panel(ExpandedView(model: demoModel(), geometry: expanded)), "expanded", dir)

        let overflow = demoModel(prs: prs(now: Date()) + extraPRs(now: Date()))
        save(panel(ExpandedView(model: overflow, geometry: expanded)), "expanded-overflow", dir)

        let selecting = demoModel()
        selecting.selectedPRs = Set(selecting.orderedPRs.suffix(2).map(\.id))
        save(panel(ExpandedView(model: selecting, geometry: expanded)), "expanded-selection", dir)

        let posted = demoModel()
        posted.loadDemoStatus(slack: "posted 2 PRs to Slack")
        save(panel(ExpandedView(model: posted, geometry: expanded)), "expanded-slack-status", dir)

        let retry = demoModel()
        retry.selectedPRs = Set(retry.orderedPRs.suffix(2).map(\.id))
        let rejected = SampleError(description: "slack: invalid_auth")
        retry.loadDemoStatus(slack: SlackNudger.failureSummary(rejected), failed: true, fix: SlackNudger.failureFix(rejected))
        save(panel(ExpandedView(model: retry, geometry: expanded)), "expanded-slack-failed", dir)

        let loading = AppModel()
        save(panel(ExpandedView(model: loading, geometry: expanded)), "expanded-loading", dir)

        let empty = demoModel(prs: [])
        save(panel(ExpandedView(model: empty, geometry: expanded)), "expanded-empty", dir)

        let firstHover = demoModel()
        firstHover.loadDemoGestureHint()
        save(panel(ExpandedView(model: firstHover, geometry: expanded)), "expanded-first-hover", dir)

        let stale = demoModel()
        stale.loadDemoStalePRs(fetchedAgo: 14 * 60, failure: URLError(.timedOut))
        save(panel(ExpandedView(model: stale, geometry: expanded)), "expanded-stale", dir)

        let failing = demoModel(accounts: troubledAccounts(now: Date()), prs: [], prFailure: URLError(.notConnectedToInternet))
        save(panel(ExpandedView(model: failing, geometry: expanded)), "expanded-errors", dir)

        // Stress states for hardening: long and non-Latin text, every flag, every fault, and a crowd.
        let extremes = demoModel(accounts: extremeAccounts(now: Date()), prs: extremePRs(now: Date()))
        extremes.loadDemoLogin("a-rather-long-github-username-for-testing")
        extremes.selectedPRs = [extremes.orderedPRs[1].id]
        extremes.moveFocus(by: 1)
        extremes.moveFocus(by: 1)
        let notInChannel = SampleError(description: "slack: not_in_channel")
        extremes.loadDemoStatus(
            slack: SlackNudger.failureSummary(notInChannel), failed: true, fix: SlackNudger.failureFix(notInChannel, channel: "C0123456789"))
        save(panel(ExpandedView(model: extremes, geometry: expanded)), "expanded-extremes", dir)

        let crowd = demoModel(
            accounts: (accounts(now: Date()) + extremeAccounts(now: Date())),
            prs: (0..<50).map { i in pr("repo\(i % 7)", 100 + i, "chore: routine change number \(i)", now: Date(), minutesAgo: Double(i * 37), ci: .success) })
        crowd.showAllPRs = true
        save(panel(ExpandedView(model: crowd, geometry: expanded)), "expanded-crowd", dir)

        let setup = SetupModel()
        setup.loadDemo(setupChecks)
        save(panel(SetupView(setup: setup, geometry: expanded)), "setup", dir)

        let setupKeys = SetupModel()
        setupKeys.loadDemo(setupChecks)
        setupKeys.moveFocus(by: 0)
        save(panel(SetupView(setup: setupKeys, geometry: expanded)), "setup-keyboard", dir)

        save(collapsedTabs(), "collapsed", dir)
        save(peekStack(peeks + extraPeeks), "peek", dir)

        for tab in SettingsView.Tab.allCases {
            save(SettingsView(model: demoModel(), navigation: SettingsNavigation(tab: tab)), "settings-\(tab.rawValue.lowercased())", dir)
        }
    }

    // MARK: Composition

    private static func geometry(_ state: NotchState, fake: Bool = false) -> NotchGeometry {
        let geometry = NotchGeometry()
        geometry.state = state
        geometry.isFake = fake
        return geometry
    }

    private static func demoModel(
        accounts: [AccountUsage]? = nil, prs: [PullRequest]? = nil, prFailure: Error? = nil
    ) -> AppModel {
        let model = AppModel()
        model.loadDemo(
            me: "wezzcoetzee", accounts: accounts ?? Self.accounts(now: model.now), prs: prs ?? Self.prs(now: model.now),
            peek: peeks[2], prFailure: prFailure)
        return model
    }

    /// The black notch shape RootView draws behind every state.
    private static func panel(_ view: some View, radius: CGFloat = 22) -> some View {
        view.foregroundStyle(.white)
            .background(UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius).fill(.black))
    }

    private static func peekStack(_ events: [Event]) -> some View {
        let geometry = NotchGeometry()
        geometry.notchHeight = 0
        return VStack(spacing: 24) {
            ForEach(events) { panel(PeekView(event: $0, geometry: geometry)) }
        }
    }

    private static func storeTabs() -> some View {
        let model = demoModel()
        let fake = geometry(.collapsed, fake: true)
        let done = SetupModel()
        done.loadDemo([])
        return VStack(spacing: 24) {
            ForEach([Settings.Indicator.counts, .dots], id: \.self) { indicator in
                panel(CollapsedView(model: model, geometry: fake, setup: done, indicator: indicator), radius: 12)
            }
        }
    }

    private static func collapsedTabs() -> some View {
        let model = demoModel()
        let fake = geometry(.collapsed, fake: true)
        let done = SetupModel()
        done.loadDemo([])
        let pending = SetupModel()
        pending.loadDemo(setupChecks)
        let hardware = geometry(.collapsed)
        return VStack(alignment: .leading, spacing: 24) {
            ForEach(Settings.Indicator.allCases, id: \.self) { indicator in
                HStack(spacing: 16) {
                    panel(CollapsedView(model: model, geometry: fake, setup: done, indicator: indicator), radius: 12)
                    Text(indicator.rawValue).font(.detail).foregroundStyle(Color.dim)
                }
            }
            HStack(spacing: 16) {
                panel(CollapsedView(model: model, geometry: hardware, setup: pending), radius: 12)
                Text("hardware notch, setup pending").font(.detail).foregroundStyle(Color.dim)
            }
        }
    }

    /// Centers `content` under a headline on a 16:10 canvas `width` points wide, saved at 2880×1800.
    /// A narrower canvas shows `content` larger.
    private static func saveFramed(
        _ content: some View, _ headline: String, _ subtitle: String, width: CGFloat, _ name: String, _ dir: URL
    ) {
        let canvas = VStack(spacing: width * 0.012) {
            Text(headline).font(.system(size: width * 0.05, weight: .bold))
            Text(subtitle).font(.system(size: width * 0.023, weight: .medium)).foregroundStyle(Color(white: 0.75))
            content.padding(.top, width * 0.02).frame(maxHeight: .infinity)
        }
        .foregroundStyle(.white)
        .padding(.vertical, width * 0.03)
        .frame(width: width, height: width / 1.6)
        .background(LinearGradient(colors: [Color(white: 0.1), Color(white: 0.045)], startPoint: .top, endPoint: .bottom))
        saveStoreImage(canvas, name, dir, scale: 2880 / width)
    }

    // MARK: Rendering

    /// Store images through ImageRenderer (the notch views have no AppKit controls), transparent
    /// unless the view draws its own background.
    private static func saveStoreImage(_ view: some View, _ name: String, _ dir: URL, scale: CGFloat = 3) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        renderer.scale = scale
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
            let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else {
            print("✗ \(name)")
            return
        }
        try? png.write(to: dir.appendingPathComponent("\(name).png"))
        print("✓ \(name).png")
    }

    /// Gallery images: a real NSHostingView rather than ImageRenderer, which cannot draw
    /// AppKit-backed controls (toggles, text fields) in the Settings tabs, on a grey backdrop
    /// so the black shape's edge shows.
    private static func save(_ view: some View, _ name: String, _ dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let host = NSHostingView(
            rootView: view.padding(24).background(Color(white: 0.11)).environment(\.colorScheme, .dark).fixedSize())
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            print("✗ \(name)")
            return
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            print("✗ \(name)")
            return
        }
        try? png.write(to: dir.appendingPathComponent("\(name).png"))
        print("✓ \(name).png")
    }

    // MARK: Sample data

    private struct SampleError: Error, CustomStringConvertible { let description: String }

    private static let peeks = [
        Event(kind: .ciFailed, headline: "CI failed · web#318", detail: "fix(web): checkout total rounds twice", tone: .bad),
        Event(kind: .usageThreshold, headline: "session at 88% · Work", detail: "resets 47m", tone: .warn),
        Event(kind: .ready, headline: "ready to merge · notchivity#42", detail: "feat: monitor Grok Build usage", tone: .good),
    ]

    private static let extraPeeks = [
        Event(kind: .merged, headline: "merged · api#1190", detail: "feat(api): idempotent webhooks", tone: .info),
        Event(kind: .fetchBroken, headline: "PR fetch failing", detail: "GitHub unreachable", tone: .warn),
        EventDiff.summary([
            Event(kind: .approved, headline: "approved · api#1204", tone: .good),
            Event(kind: .ciFailed, headline: "CI failed · web#322", tone: .bad),
            Event(kind: .newThreads, headline: "2 new comments · mobile#80", tone: .warn),
            Event(kind: .merged, headline: "merged · infra#11", tone: .info),
        ]),
    ]

    private static let setupChecks = [
        SetupCheck(id: "accounts", title: "2 Claude accounts found", status: .pass, detail: "Claude, Work"),
        SetupCheck(id: "usage.claude", title: "usage for Claude", status: .pass, detail: "session 42% · week 61%"),
        SetupCheck(
            id: "usage.claude-work", title: "usage for Work", status: .fail,
            detail: UsageError.http(401).short, fix: .openClaudeCode()),
        SetupCheck(id: "usage.codex", title: "usage for Codex", status: .pass, detail: "optional · session 12% · week 27%", required: false),
        SetupCheck(id: "gh", title: "GitHub CLI not signed in", status: .fail, fix: .copy("gh auth login")),
        SetupCheck(
            id: "notifications", title: "notifications not yet allowed", status: .off,
            detail: "optional · peeks still work", required: false, fix: .allowNotifications),
        SetupCheck(id: "login", title: "launch at login", status: .off, detail: "optional", required: false, fix: .enableLoginItem),
        SetupCheck(id: "slack", title: "Slack review asks", status: .off, detail: "optional", required: false, fix: .openSlackSettings),
    ]

    private static func accounts(now: Date) -> [AccountUsage] {
        let t = now.timeIntervalSince1970
        return [
            AccountUsage(
                id: "claude", label: "Claude", sessionPct: 42, weeklyPct: 61,
                sessionResetsAt: t + 2 * 3600 + 14 * 60, weeklyResetsAt: t + 3 * 86_400),
            AccountUsage(
                id: "claude-work", label: "Work", sessionPct: 88, weeklyPct: 34,
                sessionResetsAt: t + 47 * 60, weeklyResetsAt: t + 5 * 86_400),
            AccountUsage(
                id: "codex", label: "Codex", provider: .codex, sessionPct: 12, weeklyPct: 27,
                sessionResetsAt: t + 4 * 3600, weeklyResetsAt: t + 2 * 86_400, observedAt: t - 60),
            AccountUsage(
                id: "grok", label: "Grok", provider: .grok, observedAt: t - 120,
                monthlyPct: 18, monthlyResetsAt: t + 19 * 86_400),
        ]
    }

    /// One expired token, one red-zone account, one stale disk reading.
    private static func troubledAccounts(now: Date) -> [AccountUsage] {
        let t = now.timeIntervalSince1970
        return [
            AccountUsage(
                id: "claude", label: "Claude", sessionPct: 96, weeklyPct: 79,
                sessionResetsAt: t + 22 * 60, weeklyResetsAt: t + 86_400 + 3600),
            AccountUsage(id: "claude-work", label: "Work", failure: .http(401)),
            AccountUsage(
                id: "codex", label: "Codex", provider: .codex, sessionPct: 12, weeklyPct: 27,
                sessionResetsAt: t + 4 * 3600, weeklyResetsAt: t + 2 * 86_400, observedAt: t - 3 * 3600),
        ]
    }

    /// A week leading the session, a rate limit over a good reading, a long renamed account, a
    /// session-only reading with no reset, and non-Latin names.
    private static func extremeAccounts(now: Date) -> [AccountUsage] {
        let t = now.timeIntervalSince1970
        var renamed = AccountUsage(
            id: "claude-personal", label: "Claude", sessionPct: 30, weeklyPct: 92,
            sessionResetsAt: t + 3 * 3600, weeklyResetsAt: t + 86_400 + 7200)
        renamed.customLabel = "personal-gmail-account"
        return [
            renamed,
            AccountUsage(
                id: "claude-ratelimited", label: "Throttled", sessionPct: 100, weeklyPct: 100,
                sessionResetsAt: t + 30, weeklyResetsAt: t + 6 * 86_400, failure: .http(429)),
            AccountUsage(id: "codex-sessiononly", label: "Codex", provider: .codex, sessionPct: 3),
            AccountUsage(id: "claude-emoji", label: "🚀 東京チーム", sessionPct: 55, weeklyPct: 74, sessionResetsAt: t + 59, weeklyResetsAt: t + 40 * 86_400),
            AccountUsage(id: "grok-keychain", label: "Grok", provider: .grok, failure: .keychain),
        ]
    }

    /// Every flag at once, very long, emoji, CJK and RTL titles, a long repo and ref, and old ages.
    private static func extremePRs(now: Date) -> [PullRequest] {
        [
            pr(
                "web", 318, "fix(web): everything at once", now: now, minutesAgo: 3, ci: .failure, draft: true, conflicts: true,
                threads: 14, approvals: 3, changesRequested: true, human: true),
            pr(
                "a-very-long-repository-name-in-the-monorepo", 123_456,
                "refactor(checkout): move the entire pricing, discount, tax and rounding pipeline into a single typed reducer with exhaustive tests",
                now: now, minutesAgo: 60 * 24 * 400, ci: .success, threads: 1, human: true),
            pr("i18n", 7, "feat: 日本語のローカライズを追加する 🎌 and العربية support for right-to-left layouts", now: now, minutesAgo: 59, ci: .pending),
            pr("emoji", 8, "🐛🔥💥 fix crash when title is only emoji 🎉🎉🎉🎉🎉🎉🎉🎉", now: now, minutesAgo: 1, ci: .success, approvals: 1),
            pr("docs", 9, "x", now: now, minutesAgo: 0, ci: .none, draft: true),
        ]
    }

    private static func pr(
        _ repo: String, _ number: Int, _ title: String, now: Date, minutesAgo: Double, ci: CIState, draft: Bool = false,
        conflicts: Bool = false, threads: Int = 0, approvals: Int = 0, changesRequested: Bool = false, human: Bool = false
    ) -> PullRequest {
        PullRequest(
            repo: "acme/\(repo)", number: number, title: title,
            url: URL(string: "https://github.com/acme/\(repo)/pull/\(number)")!, branch: "feature", draft: draft,
            updatedAt: now.addingTimeInterval(-minutesAgo * 60), ci: ci, conflicts: conflicts,
            unresolvedThreads: threads, approvals: approvals, changesRequested: changesRequested, reviewedByHuman: human)
    }

    private static func prs(now: Date) -> [PullRequest] {
        [
            pr("web", 318, "fix(web): checkout total rounds twice", now: now, minutesAgo: 8, ci: .failure),
            pr("api", 1204, "feat(api): rate limit per workspace", now: now, minutesAgo: 95, ci: .success, threads: 2, human: true),
            pr("notchivity", 42, "feat: monitor Grok Build usage", now: now, minutesAgo: 22, ci: .success, approvals: 2),
            pr("mobile", 77, "chore: bump Expo to 55", now: now, minutesAgo: 300, ci: .success, approvals: 1),
            pr("infra", 9, "feat: preview environments per PR", now: now, minutesAgo: 40, ci: .pending),
        ]
    }

    private static func extraPRs(now: Date) -> [PullRequest] {
        [
            pr("web", 322, "refactor(web): move checkout state into a reducer with typed actions", now: now, minutesAgo: 600, ci: .success, conflicts: true),
            pr("api", 1211, "fix(api): webhook retries", now: now, minutesAgo: 1500, ci: .success, changesRequested: true, human: true),
            pr("docs", 14, "docs: onboarding guide", now: now, minutesAgo: 4000, ci: .none, draft: true),
            pr("mobile", 80, "feat(mobile): offline queue", now: now, minutesAgo: 70, ci: .success),
            pr("infra", 11, "chore: pin terraform providers", now: now, minutesAgo: 12_000, ci: .success),
        ]
    }
}
