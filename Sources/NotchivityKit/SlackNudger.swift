import Foundation

/// Posts "please review" requests to Slack. With a bot token it calls chat.postMessage;
/// without one it shells out to `claude -p` and lets its Slack MCP send the message.
/// The first ask for a PR posts the URL top-level and remembers the thread; later asks
/// nudge inside that thread. Several PRs at once go out as one list message, which then
/// becomes the thread for each of them.
public struct SlackNudger {
    /// `nudged`: a later ask, posted as a reminder in the PR's existing thread.
    public enum Outcome { case posted, nudged }

    let config: Config
    static let threadsFile = Config.directory.appendingPathComponent("slack-threads.json")

    public init(config: Config = .load()) { self.config = config }

    public func askForReview(_ prs: [PullRequest]) async throws -> Outcome {
        guard let channel = config.slackChannel, !channel.isEmpty else {
            throw ShellError(description: "set slackChannel in \(Config.file.path)")
        }
        guard let first = prs.first else { throw ShellError(description: "no PRs selected") }
        var threads = Self.loadThreads()
        if prs.count == 1, let ts = threads[first.id] {
            _ = try await post(":eyes: still needs a review please: *\(first.title)*\n\(first.url.absoluteString)", channel: channel, thread: ts)
            return .nudged
        }
        let text = prs.count == 1 ? first.url.absoluteString : Self.batchMessage(prs)
        let ts = try await post(text, channel: channel, thread: nil)
        for pr in prs { threads[pr.id] = ts }
        Self.saveThreads(threads)
        return .posted
    }

    /// One line per PR so the message stays scannable; links are labelled with the short ref.
    public static func batchMessage(_ prs: [PullRequest]) -> String {
        ([":eyes: \(plural(prs.count, "PR")) waiting for review please:"]
            + prs.map { "• <\($0.url.absoluteString)|\($0.shortRef)> \($0.title)" }).joined(separator: "\n")
    }

    func post(_ text: String, channel: String, thread: String?) async throws -> String {
        if let token = config.slackBotToken, !token.isEmpty {
            return try await postViaToken(text, channel: channel, thread: thread, token: token)
        }
        return try await postViaClaude(text, channel: channel, thread: thread)
    }

    func postViaToken(_ text: String, channel: String, thread: String?, token: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://slack.com/api/chat.postMessage")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["channel": channel, "text": text, "unfurl_links": false]
        if let thread { body["thread_ts"] = thread }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard json?["ok"] as? Bool == true, let ts = json?["ts"] as? String else {
            throw ShellError(description: "slack: \(json?["error"] as? String ?? "no ts")")
        }
        return ts
    }

    func postViaClaude(_ text: String, channel: String, thread: String?) async throws -> String {
        let hint = thread.map { " Post it as a threaded reply to the message with timestamp \($0) (pass that as thread_ts to the tool)." } ?? ""
        let prompt = """
            Send EXACTLY this message to Slack channel \(channel) using your Slack send-message tool.\(hint) Do not edit or add anything.

            \(text)

            After the tool returns, reply with a single line "SLACK_OK <ts>" using the message timestamp the tool returned. \
            If you cannot send it, reply "SLACK_FAIL <reason>" and nothing else. Never reply SLACK_OK unless the tool actually returned a timestamp.
            """
        let data = try await Shell.run(Shell.which("claude"), ["-p", prompt, "--max-turns", "6"], timeout: 120)
        let out = String(decoding: data, as: UTF8.self)
        if let match = out.firstMatch(of: #/SLACK_OK\s+(\S+)/#) { return String(match.1) }
        let reason = out.firstMatch(of: #/SLACK_FAIL\s+(.+)/#).map { String($0.1) } ?? "Slack MCP did not confirm delivery"
        throw ShellError(description: reason)
    }

    static func loadThreads() -> [String: String] {
        guard let data = try? Data(contentsOf: threadsFile) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    static func saveThreads(_ threads: [String: String]) {
        try? FileManager.default.createDirectory(at: Config.directory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(threads).write(to: threadsFile, options: .atomic)
    }

    enum Failure { case noChannel, channelNotFound, notInChannel, badToken, timeout, other }

    /// Classifies a failed ask from the Slack API error code or the `claude -p` fallback's reply.
    static func failure(_ error: Error) -> Failure {
        let text = "\(error)".lowercased()
        if text.contains("slackchannel") { return .noChannel }
        if text.contains("channel_not_found") { return .channelNotFound }
        if text.contains("not_in_channel") { return .notInChannel }
        if text.contains("invalid_auth") || text.contains("not_authed") || text.contains("token_revoked") { return .badToken }
        if text.contains("timed out") || text.contains("timeout") { return .timeout }
        return .other
    }

    /// A short reason for the notch when an ask fails.
    public static func failureSummary(_ error: Error) -> String {
        switch failure(error) {
        case .noChannel: return "no Slack channel set"
        case .channelNotFound: return "Slack channel not found"
        // The bot's name is not known here, so the line says the fix instead of linking it.
        case .notInChannel: return "invite the Slack bot to the channel"
        case .badToken: return "Slack token rejected"
        case .timeout: return "Slack post timed out"
        case .other: return "Slack post failed"
        }
    }

    /// The link beside a failed ask. A missing bot opens the channel, where "/invite" goes. A
    /// timeout has none: the failed PRs stay selected, so the selection line is the retry.
    public static func failureFix(_ error: Error, channel: String? = Config.load().slackChannel) -> SetupCheck.Fix? {
        switch failure(error) {
        case .noChannel, .channelNotFound, .badToken, .other: return .openSlackSettings
        case .notInChannel: return channel.map(SetupCheck.Fix.openSlackChannel)
        case .timeout: return nil
        }
    }
}
