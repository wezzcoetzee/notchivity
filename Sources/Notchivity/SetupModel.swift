import AppKit
import NotchivityKit
import UserNotifications

/// Runs the setup checklist on launch and every few seconds while it is on screen.
/// The expanded panel shows the checklist instead of the dashboard until every required
/// check has passed once; later failures surface inline on the dashboard instead. The
/// right-click menu can bring the checklist back any time.
@MainActor
final class SetupModel: ObservableObject {
    @Published private(set) var checks: [SetupCheck] = []
    @Published private(set) var running = false
    /// A "retry" click is refetching and rechecking; its link reads "checking…" until done.
    @Published private(set) var retrying = false
    /// User asked for the checklist even though nothing is blocking.
    @Published var pinned = false
    /// Every required check passed at least once, so the dashboard owns the panel from here on.
    @Published private(set) var everPassed = false
    /// Closed while still failing, for setups that never pass (no `gh`, Codex only). Lasts until
    /// relaunch; failures still show inline on the dashboard and as "N to set up" under the notch.
    @Published var skipped = false

    static let recheckInterval: TimeInterval = 10

    var blocking: Int { checks.filter(\.blocking).count }
    var required: [SetupCheck] { checks.filter(\.required) }
    var hasRun: Bool { !checks.isEmpty }
    /// Show the checklist while first-run setup is incomplete, or on request.
    var visible: Bool { pinned || (hasRun && blocking > 0 && !everPassed && !skipped) }

    func close() {
        pinned = false
        skipped = true
    }

    /// Supply the app's latest readings so the checks do not poll the APIs on their own.
    var usageProvider: () async -> [AccountUsage] = { [] }
    var prsProvider: () async -> SetupDoctor.PRResult? = { nil }
    var openSettings: () -> Void = {}
    /// Refetches usage and PRs regardless of their intervals, so "retry" means retry.
    var refresh: () async -> Void = {}
    var fixApplied: () -> Void = {}

    /// A run requested mid-run queues one more and waits for it, so a "retry" sees its own result.
    func run() async {
        if let current {
            rerun = true
            return await current.value
        }
        let task = Task {
            running = true
            repeat {
                rerun = false
                checks = await SetupDoctor().run(usage: await usageProvider(), prs: await prsProvider(), extra: await appChecks())
            } while rerun
            // An offline first launch (a warn, not a failure) must not latch: the network may be
            // masking a sign-in problem. Other warnings (a rate limit, a stale proxy) do not hold it.
            if blocking == 0, !checks.contains(where: \.inconclusive) { everPassed = true }
            running = false
        }
        current = task
        await task.value
        current = nil
    }

    private var current: Task<Void, Never>?
    private var rerun = false

    /// Fixed checklist for `--gallery`, bypassing every check.
    func loadDemo(_ checks: [SetupCheck]) {
        self.checks = checks
        everPassed = blocking == 0
    }

    /// Keep rechecking while visible so fixes show up on their own. Until a clean pass has
    /// latched (skipped while failing, or an offline start with only warnings) it rechecks every
    /// minute, so "N to set up" clears and the latch lands once things recover.
    func startRechecking() {
        Task {
            var lastRun = Date.distantPast
            while !Task.isCancelled {
                if visible || (hasRun && !everPassed && Date().timeIntervalSince(lastRun) >= 60) {
                    await run()
                    lastRun = Date()
                }
                try? await Task.sleep(for: .seconds(Self.recheckInterval))
            }
        }
    }

    private func appChecks() async -> [SetupCheck] {
        var checks: [SetupCheck] = []
        if Notifier.shared.available {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                checks.append(SetupCheck(id: "notifications", title: "notifications allowed", status: .pass, required: false))
            case .denied:
                checks.append(
                    SetupCheck(
                        id: "notifications", title: "notifications denied", status: .warn,
                        detail: "optional · peeks still work", required: false, fix: .openNotificationSettings))
            default:
                checks.append(
                    SetupCheck(
                        id: "notifications", title: "notifications not yet allowed", status: .off,
                        detail: "optional · peeks still work", required: false, fix: .allowNotifications))
            }
        } else {
            checks.append(
                SetupCheck(
                    id: "notifications", title: "notifications unavailable", status: .off,
                    detail: "optional · needs the .app bundle from make-app.sh", required: false))
        }
        let inApplications = LoginItemManager.inApplications
        if LoginItemManager.shared.isEnabled {
            checks.append(SetupCheck(id: "login", title: "launch at login on", status: .pass, required: false))
        } else if inApplications {
            checks.append(SetupCheck(id: "login", title: "launch at login", status: .off, detail: "optional", required: false, fix: .enableLoginItem))
        } else {
            checks.append(
                SetupCheck(
                    id: "login", title: "launch at login", status: .off,
                    detail: "optional · needs the app in /Applications", required: false,
                    fix: Notifier.shared.available ? .moveToApplications : nil))
        }
        return checks
    }

    /// Returns a few words for the link to show for a moment when the click has no other visible
    /// effect: "copied", "copied, paste in Terminal" when Terminal automation was refused, or a
    /// failure. A retry instead shows "checking…" through `retrying` for as long as it runs.
    @discardableResult
    func apply(_ fix: SetupCheck.Fix) -> String? {
        fixApplied()
        var feedback: String?
        switch fix {
        case .openClaudeCode(let directory):
            if !openClaudeCode(configDirectory: directory) { feedback = "copied, paste in Terminal" }
        case .retry:
            guard !retrying else { return nil }
            retrying = true
            Task {
                await refresh()
                await run()
                retrying = false
            }
            return nil
        case .copy(let command):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
            feedback = "copied"
        case .allowNotifications:
            Notifier.shared.requestAuthorization()
        case .openNotificationSettings:
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
        case .openSlackSettings:
            openSettings()
        case .enableLoginItem:
            LoginItemManager.shared.setEnabled(true)
        case .moveToApplications:
            if !moveToApplications() { feedback = "could not copy to /Applications" }
        }
        Task {
            try? await Task.sleep(for: .seconds(1))
            await run()
        }
        return feedback
    }

    /// Runs `claude` in Terminal under the account's config dir. If Terminal automation is
    /// refused, the command is copied instead; returns whether Terminal opened.
    private func openClaudeCode(configDirectory: String?) -> Bool {
        let command = configDirectory.map { "CLAUDE_CONFIG_DIR='\($0.replacingOccurrences(of: "'", with: "'\\''"))' claude" } ?? "claude"
        let quoted = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "tell application \"Terminal\" to do script \"\(quoted)\"\ntell application \"Terminal\" to activate"
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        guard error != nil else { return true }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        return false
    }

    /// Copies the bundle into /Applications and relaunches from there; false if the copy failed.
    private func moveToApplications() -> Bool {
        let source = Bundle.main.bundleURL
        let target = URL(fileURLWithPath: "/Applications").appendingPathComponent(source.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.copyItem(at: source, to: target)
            NSWorkspace.shared.openApplication(at: target, configuration: .init()) { _, error in
                guard error == nil else { return }
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
            return true
        } catch {
            return false
        }
    }
}
