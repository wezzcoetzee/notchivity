import Foundation

/// One line of the setup checklist.
public struct SetupCheck: Identifiable, Equatable {
    public enum Status: Equatable { case pass, fail, warn, off }
    public enum Fix: Equatable {
        case openClaudeCode
        case retry
        case copy(String)
        case allowNotifications
        case openNotificationSettings
        case createSlackConfig
        case enableLoginItem
        case moveToApplications

        public var label: String {
            switch self {
            case .openClaudeCode: return "open Claude Code"
            case .retry: return "retry"
            case .copy(let command): return "copy \(command)"
            case .allowNotifications: return "allow"
            case .openNotificationSettings: return "System Settings"
            case .createSlackConfig: return "create config"
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

    public init(id: String, title: String, status: Status, detail: String? = nil, diagnostic: String? = nil,
                required: Bool = true, fix: Fix? = nil) {
        self.id = id
        self.title = title
        self.status = status
        self.detail = detail
        self.diagnostic = diagnostic
        self.required = required
        self.fix = fix
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
        async let claude = claudeChecks(usage: usage?.filter { $0.provider == .claude })
        async let codex = codexChecks(usage: usage?.filter { $0.provider == .codex })
        async let grok = grokChecks(usage: usage?.filter { $0.provider == .grok })
        async let github = githubChecks(prs: prs)
        let results = await (claude, codex, grok, github)
        return results.0 + results.1 + results.2 + results.3 + extra + [slack()]
    }

    func claudeChecks(usage: [AccountUsage]?) async -> [SetupCheck] {
        if let usage { return usageChecks(usage) }
        let accounts = ClaudeAccountDiscovery.discover()
        guard !accounts.isEmpty else {
            return [SetupCheck(id: "accounts", title: "no Claude sign-in found", status: .fail,
                               detail: "sign in to Claude Code once; a second account uses CLAUDE_CONFIG_DIR=~/.claude-<name>",
                               fix: .openClaudeCode)]
        }
        let checks = [SetupCheck(id: "accounts", title: plural(accounts.count, "Claude account") + " found",
                                 status: .pass, detail: accounts.map(\.label).joined(separator: ", "))]
        let fetcher = UsageFetcher()
        var readings: [AccountUsage] = []
        for account in accounts {
            do {
                readings.append(try await fetcher.usage(for: account))
            } catch {
                readings.append(AccountUsage(id: account.id, label: account.label, failure: error as? UsageError ?? .other("\(error)")))
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
            SetupCheck(id: "usage.\(reading.id)", title: "usage for \(reading.provider.name)",
                       status: reading.failure == nil ? .pass : .warn,
                       detail: reading.failure?.description ?? usageDetail(reading), required: false)
        }
    }

    func usageChecks(_ readings: [AccountUsage], includeCount: Bool = true) -> [SetupCheck] {
        guard !readings.isEmpty else {
            return [SetupCheck(id: "accounts", title: "no Claude sign-in found", status: .fail,
                               detail: "sign in to Claude Code once; a second account uses CLAUDE_CONFIG_DIR=~/.claude-<name>",
                               fix: .openClaudeCode)]
        }
        var checks: [SetupCheck] = []
        if includeCount {
            checks.append(SetupCheck(id: "accounts", title: plural(readings.count, "Claude account") + " found",
                                     status: .pass, detail: readings.map(\.displayLabel).joined(separator: ", ")))
        }
        for reading in readings {
            if let failure = reading.failure {
                // A 429 clears on its own; it should not hold the checklist open.
                checks.append(SetupCheck(id: "usage.\(reading.id)", title: "usage for \(reading.displayLabel)",
                                         status: failure == .http(429) ? .warn : .fail,
                                         detail: failure.description, fix: failure.fix))
            } else {
                checks.append(SetupCheck(id: "usage.\(reading.id)", title: "usage for \(reading.displayLabel)", status: .pass,
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
            return [SetupCheck(id: "gh", title: "GitHub CLI signed in as \(fetched.me)", status: .pass, detail: "\(fetched.prs.count) open PRs")]
        } catch {
            if (try? await Shell.run(gh, ["auth", "status"])) == nil {
                return [SetupCheck(id: "gh", title: "GitHub CLI not signed in", status: .fail, fix: .copy("gh auth login"))]
            }
            return [SetupCheck(id: "gh", title: "PR query failed", status: .fail,
                               detail: Shell.summary(error, fallback: "pr fetch failed"), diagnostic: "\(error)", fix: .retry)]
        }
    }

    func slack() -> SetupCheck {
        Config.load().slackConfigured
            ? SetupCheck(id: "slack", title: "Slack review nudges configured", status: .pass, required: false)
            : SetupCheck(id: "slack", title: "Slack review nudges", status: .off, detail: "optional", required: false, fix: .createSlackConfig)
    }

    /// Writes a config template if none exists and returns its path.
    public static func createSlackConfigTemplate() -> URL {
        if !FileManager.default.fileExists(atPath: Config.file.path) {
            try? FileManager.default.createDirectory(at: Config.directory, withIntermediateDirectories: true)
            let template = #"{ "slackChannel": "C0123456789", "slackBotToken": "" }"#
            try? Data((template + "\n").utf8).write(to: Config.file)
        }
        return Config.file
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
