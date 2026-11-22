import Testing

@testable import NotchivityKit

@Suite struct SlackNudgerTests {
    @Test func failuresCarryTheirFix() {
        let cases: [(String, String, SetupCheck.Fix?)] = [
            ("set slackChannel in config.json", "no Slack channel set", .openSlackSettings),
            ("slack: channel_not_found", "Slack channel not found", .openSlackSettings),
            ("slack: not_in_channel", "invite the Slack bot to the channel", .openSlackChannel("C1")),
            ("slack: invalid_auth", "Slack token rejected", .openSlackSettings),
            ("request timed out", "Slack post timed out", nil),
            ("Slack MCP did not confirm delivery", "Slack post failed", .openSlackSettings),
        ]
        for (raw, summary, fix) in cases {
            let error = ShellError(description: raw)
            #expect(SlackNudger.failureSummary(error) == summary)
            #expect(SlackNudger.failureFix(error, channel: "C1") == fix)
        }
    }
}
