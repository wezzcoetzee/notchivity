import Foundation

/// One line of the setup checklist.
public struct SetupCheck: Identifiable, Equatable {
    public enum Status: Equatable { case pass, fail, warn, off }
    public enum Fix: Equatable {
        /// Opens Terminal running `claude`, under `CLAUDE_CONFIG_DIR` when the sign-in is not the default.
        case openClaudeCode(configDirectory: String? = nil)
        case retry
        case copy(String)
        case allowNotifications
        case openNotificationSettings
        case openSlackSettings
        case enableLoginItem
        case moveToApplications

        public var label: String {
            switch self {
            case .openClaudeCode: return "open Claude Code"
            case .retry: return "retry"
            case .copy(let command): return "copy \(command)"
            case .allowNotifications: return "allow"
            case .openNotificationSettings: return "open System Settings"
            case .openSlackSettings: return "open Settings"
            case .enableLoginItem: return "enable"
            case .moveToApplications: return "move to /Applications"
            }
        }
    }

    public let id: String
    public let title: String
    public let status: Status
    public let detail: String?
    /// Raw error text for the `--doctor` report only; the notch shows `detail`.
    public let diagnostic: String?
    public let required: Bool
    public let fix: Fix?
    /// A warning that hides the real result (offline, a server outage): it never blocks, but
    /// first-run setup does not count as passed until it clears.
    public let inconclusive: Bool

    public init(
        id: String, title: String, status: Status, detail: String? = nil, diagnostic: String? = nil,
        required: Bool = true, fix: Fix? = nil, inconclusive: Bool = false
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.detail = detail
        self.diagnostic = diagnostic
        self.required = required
        self.fix = fix
        self.inconclusive = inconclusive
    }

    public var blocking: Bool { required && status == .fail }
}

/// Runs every check the app needs to work. The app-only checks (notifications, login
/// item) are supplied by the caller since they need AppKit.
public struct SetupDoctor {
    public init() {}

    public typealias PRResult = Result<(me: String, prs: [PullRequest]), Error>

    /// `usage` and `prs` are the app's most recent readings when it has them, so the checklist
    /// does not add a second poller against either API. The CLI passes nil and fetches.
    public func run(usage: [AccountUsage]? = nil, prs: PRResult? = nil, extra: [SetupCheck] = []) async -> [SetupCheck] {
        async let quotas = quotaChecks(usage: usage, config: .load())
        async let github = githubChecks(prs: prs)
        let results = await (quotas, github)
        return results.0 + results.1 + extra + [slack()]
    }

    func quotaChecks(usage: [AccountUsage]?, config: Config) async -> [SetupCheck] {
        if config.usesCLIProxy {
            let readings = if let usage { usage } else { await UsageReader().fetch(previous: [], config: config) }
            return proxyChecks(readings)
        }
        async let claude = claudeChecks(usage: usage?.filter { $0.provider == .claude })
        async let codex = codexChecks(usage: usage?.filter { $0.provider == .codex })
        async let grok = grokChecks(usage: usage?.filter { $0.provider == .grok })
        let results = await (claude, codex, grok)
        return results.0 + results.1 + results.2
    }

    func proxyChecks(_ readings: [AccountUsage]) -> [SetupCheck] {
        guard !readings.isEmpty else {
            return [SetupCheck(id: "cliproxy", title: "CLI proxy connected", status: .warn, detail: "no supported accounts returned")]
        }
        return readings.map { reading in
            SetupCheck(
                id: "usage.\(reading.id)", title: "CLI proxy: \(reading.displayLabel)",
                status: reading.failure == nil ? .pass : (reading.id.hasSuffix(":connection") ? .fail : .warn),
                detail: reading.failure?.description ?? usageDetail(reading), fix: reading.failure == nil ? nil : .retry)
        }
    }

    func claudeChecks(usage: [AccountUsage]?) async -> [SetupCheck] {
        if let usage { return usageChecks(usage) }
        let accounts = ClaudeAccountDiscovery.discover()
        guard !accounts.isEmpty else {
            return [
                SetupCheck(
                    id: "accounts", title: "no Claude sign-in found", status: .fail,
                    detail: "sign in to Claude Code once; a second account uses CLAUDE_CONFIG_DIR=~/.claude-<name>",
                    fix: .openClaudeCode())
            ]
        }
        let checks = [
            SetupCheck(
                id: "accounts", title: plural(accounts.count, "Claude account") + " found",
                status: .pass, detail: accounts.map(\.label).joined(separator: ", "))
        ]
        let fetcher = UsageFetcher()
        var readings: [AccountUsage] = []
        for account in accounts {
            do {
                readings.append(try await fetcher.usage(for: account))
            } catch {
                var failed = AccountUsage(id: account.id, label: account.label, failure: UsageError(error))
                failed.configDirectory = account.configDirectory
                readings.append(failed)
            }
        }
        return checks + usageChecks(readings, includeCount: false)
    }

    /// Codex is optional: nothing here blocks setup, and an unsigned-in Codex shows nothing
    /// at all rather than a row the user cannot act on.
    func codexChecks(usage: [AccountUsage]?) async -> [SetupCheck] {
        let readings = if let usage { usage } else { await CodexUsageSource().fetch(previous: []) }
        return optionalUsageChecks(readings)
    }

    func grokChecks(usage: [AccountUsage]?) async -> [SetupCheck] {
        let readings = if let usage { usage } else { await GrokUsageSource().fetch(previous: []) }
        return optionalUsageChecks(readings)
    }

    private func optionalUsageChecks(_ readings: [AccountUsage]) -> [SetupCheck] {
        return readings.map { reading in
            SetupCheck(
                id: "usage.\(reading.id)", title: "usage for \(reading.provider.name)",
                status: reading.failure == nil ? .pass : .warn,
                detail: "optional · " + (reading.failure?.description ?? usageDetail(reading)), required: false)
        }
    }

    func usageChecks(_ readings: [AccountUsage], includeCount: Bool = true) -> [SetupCheck] {
        guard !readings.isEmpty else {
            return [
                SetupCheck(
                    id: "accounts", title: "no Claude sign-in found", status: .fail,
                    detail: "sign in to Claude Code once; a second account uses CLAUDE_CONFIG_DIR=~/.claude-<name>",
                    fix: .openClaudeCode())
            ]
        }
        var checks: [SetupCheck] = []
        if includeCount {
            checks.append(
                SetupCheck(
                    id: "accounts", title: plural(readings.count, "Claude account") + " found",
                    status: .pass, detail: readings.map(\.displayLabel).joined(separator: ", ")))
        }
        for reading in readings {
            if let failure = reading.failure {
                // A 429, the network or a server outage clears on its own; it should not hold the
                // checklist open. An expired token (also transient) needs the user, so it fails.
                let passing = failure == .http(429) || (failure.isTransient && failure != .http(401))
                checks.append(
                    SetupCheck(
                        id: "usage.\(reading.id)", title: "usage for \(reading.displayLabel)",
                        status: passing ? .warn : .fail,
                        // Beside "open Claude Code" the short reason is enough; anything else keeps the
                        // full sentence, which for the keychain is the guidance ("click Always Allow…").
                        detail: failure == .http(401) ? failure.short : failure.description, fix: reading.fix,
                        inconclusive: passing && failure != .http(429)))
            } else {
                checks.append(
                    SetupCheck(
                        id: "usage.\(reading.id)", title: "usage for \(reading.displayLabel)", status: .pass,
                        detail: usageDetail(reading)))
            }
        }
        return checks
    }

    func usageDetail(_ reading: AccountUsage) -> String {
        reading.windows.map { window in
            let value = reading.pct(window).map { "\(Int($0))%" } ?? "unknown"
            return "\(window.label) \(value)"
        }.joined(separator: " · ")
    }

    func githubChecks(prs: PRResult?) async -> [SetupCheck] {
        let gh = Shell.which("gh")
        guard FileManager.default.isExecutableFile(atPath: gh) else {
            return [SetupCheck(id: "gh", title: "GitHub CLI not installed", status: .fail, fix: .copy("brew install gh"))]
        }
        do {
            let fetched = if let prs { try prs.get() } else { try await PRFetcher().fetch() }
            return [SetupCheck(id: "gh", title: "GitHub CLI signed in as \(fetched.me)", status: .pass, detail: plural(fetched.prs.count, "open PR"))]
        } catch {
            // Offline (launch at login before Wi-Fi) is not a sign-in problem, and `gh auth status`
            // would fail too and say it is.
            if Shell.summary(error, fallback: "") == Shell.offline {
                return [
                    SetupCheck(
                        id: "gh", title: Shell.offline, status: .warn, detail: "PRs load once the network is back", fix: .retry,
                        inconclusive: true)
                ]
            }
            if (try? await Shell.run(gh, ["auth", "status"])) == nil {
                return [SetupCheck(id: "gh", title: Shell.signedOut, status: .fail, fix: .copy("gh auth login"))]
            }
            return [
                SetupCheck(
                    id: "gh", title: "PR query failed", status: .fail,
                    detail: Shell.summary(error, fallback: "PR fetch failed"), diagnostic: "\(error)", fix: .retry)
            ]
        }
    }

    func slack() -> SetupCheck {
        Config.load().slackConfigured
            ? SetupCheck(id: "slack", title: "Slack review nudges configured", status: .pass, required: false)
            : SetupCheck(id: "slack", title: "Slack review nudges", status: .off, detail: "optional", required: false, fix: .openSlackSettings)
    }

    /// Plain-text report for `--doctor`.
    public static func report(_ checks: [SetupCheck]) -> String {
        let width = checks.map(\.title.count).max() ?? 0
        var lines = checks.map { check -> String in
            let mark: String
            switch check.status {
            case .pass: mark = "✔"
            case .fail: mark = "✘"
            case .warn: mark = "!"
            case .off: mark = "○"
            }
            let detail = [check.detail, check.diagnostic, check.fix.map { "→ \($0.label)" }].compactMap { $0 }.joined(separator: "  ")
            return "\(mark) \(check.title.padding(toLength: width, withPad: " ", startingAt: 0))  \(detail)"
        }
        let problems = checks.filter(\.blocking).count
        lines.append(problems == 0 ? "all required checks pass" : plural(problems, "problem"))
        return lines.joined(separator: "\n")
    }
}
