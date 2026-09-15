import Testing
@testable import NotchivityKit

@Suite struct SetupCheckTests {
    @Test func usageReadingsBecomeChecks() {
        let checks = SetupDoctor().usageChecks([
            AccountUsage(id: "a", label: "idexx", sessionPct: 13, weeklyPct: 63),
            AccountUsage(id: "b", label: "ezyvet", failure: .keychain),
            AccountUsage(id: "c", label: "other", failure: .http(401)),
            AccountUsage(id: "d", label: "limited", failure: .http(429)),
        ])
        #expect(checks.map(\.status) == [.pass, .pass, .fail, .fail, .warn])
        #expect(checks[1].detail == "session 13% · week 63%")
        #expect(checks[2].fix == .retry)
        #expect(checks[3].fix == .openClaudeCode)
        #expect(checks.filter(\.blocking).count == 2)
    }

    @Test func noAccountsIsOneBlockingCheck() {
        let checks = SetupDoctor().usageChecks([])
        #expect(checks.count == 1)
        #expect(checks[0].blocking)
        #expect(checks[0].fix == .openClaudeCode)
    }

    @Test func reportCountsProblems() {
        let report = SetupDoctor.report([
            SetupCheck(id: "x", title: "Thing", status: .fail, fix: .copy("brew install gh")),
            SetupCheck(id: "y", title: "Slack", status: .off, required: false),
        ])
        #expect(report.hasSuffix("1 problem"))
        #expect(report.contains("→ copy brew install gh"))
    }
}
