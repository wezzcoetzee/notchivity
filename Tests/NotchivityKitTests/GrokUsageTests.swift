import Foundation
import Testing
@testable import NotchivityKit

private func billingLine(timestamp: String = "2026-10-20T10:00:00.123Z",
                         period: String = "USAGE_PERIOD_TYPE_WEEKLY",
                         percentage: Double = 64,
                         end: String = "2099-10-27T10:00:00Z") throws -> Data {
    try JSONSerialization.data(withJSONObject: [
        "ts": timestamp, "src": "shell", "lvl": "info",
        "msg": "billing: fetched credits config",
        "ctx": ["config": [
            "creditUsagePercent": percentage,
            "currentPeriod": ["type": period, "end": end],
            "onDemandUsed": ["val": 500],
        ]],
    ])
}

@Suite struct GrokUsageTests {
    @Test(arguments: ["USAGE_PERIOD_TYPE_WEEKLY", "USAGE_PERIOD_TYPE_MONTHLY"])
    func parsesTheActualAllowancePeriod(period: String) throws {
        let reading = try #require(GrokReading.parse(billingLine(period: period)))
        let usage = reading.accountUsage
        let window: AccountUsage.Window = period == "USAGE_PERIOD_TYPE_WEEKLY" ? .weekly : .monthly
        #expect(usage.provider == .grok)
        #expect(usage.windows == [window])
        #expect(usage.pct(window) == 64)
        #expect(usage.primaryPct == 64)
        #expect(usage.sessionPct == nil)
        #expect(usage.resetsAt(window) == UsageParsing.epochSeconds("2099-10-27T10:00:00Z"))
        #expect(usage.observedAt == UsageParsing.epochSeconds("2026-10-20T10:00:00.123Z"))
    }

    @Test func parsesLegacyMonthlyCreditsAndClampsPercentages() throws {
        let legacy = Data(#"{"ts":"2026-10-20T10:00:00Z","msg":"billing: fetched credits config","ctx":{"config":{"monthlyLimit":{"val":10000},"used":{"val":2500},"billingPeriodEnd":"2099-11-01T00:00:00Z"}}}"#.utf8)
        #expect(GrokReading.parse(legacy)?.accountUsage.monthlyPct == 25)
        #expect(GrokReading.parse(try billingLine(percentage: 150))?.percentage == 100)
        #expect(GrokReading.parse(try billingLine(percentage: -5))?.percentage == 0)
    }

    @Test func rejectsUnrelatedIncompleteAndUnknownPeriodRecords() throws {
        #expect(GrokReading.parse(Data("not json".utf8)) == nil)
        #expect(GrokReading.parse(Data(#"{"session":{"totalTokens":123}}"#.utf8)) == nil)
        #expect(GrokReading.parse(try billingLine(timestamp: "invalid")) == nil)
        #expect(GrokReading.parse(try billingLine(period: "USAGE_PERIOD_TYPE_DAILY")) == nil)
        #expect(GrokReading.parse(try billingLine(end: "invalid")) == nil)
        let missing = Data(#"{"ts":"2026-10-20T10:00:00Z","msg":"billing: fetched credits config","ctx":{"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2099-11-01T00:00:00Z"}}}}"#.utf8)
        #expect(GrokReading.parse(missing) == nil)
        let conflicting = Data(#"{"ts":"2026-10-20T10:00:00Z","msg":"billing: fetched credits config","ctx":{"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY"},"monthlyLimit":{"val":100},"used":{"val":50},"billingPeriodEnd":"2099-11-01T00:00:00Z"}}}"#.utf8)
        #expect(GrokReading.parse(conflicting) == nil)
    }

    @Test func newestSnapshotUsesTimestampAndSurvivesPartialLinesAndBusyLogs() throws {
        let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        var data = try billingLine(timestamp: "2026-10-20T11:00:00Z", percentage: 75) + Data("\n".utf8)
        data += try billingLine(timestamp: "2026-10-20T10:00:00Z", percentage: 64) + Data("\n".utf8)
        data += Data(String(repeating: "unrelated log entry\n", count: 40_000).utf8)
        data += Data(#"{"ts":"partial""#.utf8)
        try data.write(to: file)
        #expect(try GrokUsageSource.newestReading(in: file)?.percentage == 75)
    }

    @Test func discoveryRefreshAndLogTrimmingKeepTheLatestSnapshot() async throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let source = GrokUsageSource(home: home, environment: [:])
        #expect(await source.fetch(previous: []).isEmpty)
        try FileManager.default.createDirectory(at: source.directory.appendingPathComponent("logs"), withIntermediateDirectories: true)
        try Data().write(to: source.authFile)
        let missing = await source.fetch(previous: [])
        #expect(missing.first?.failure != nil)
        let log = source.directory.appendingPathComponent("logs/unified.jsonl")
        try (billingLine() + Data("\n".utf8)).write(to: log)
        let fresh = await source.fetch(previous: missing)
        #expect(fresh.first?.weeklyPct == 64)
        #expect(fresh.first?.failure == nil)
        try Data("trimmed\n".utf8).write(to: log)
        #expect(await source.fetch(previous: fresh) == fresh)
        try (billingLine(timestamp: "2026-10-20T09:00:00Z", percentage: 20) + Data("\n".utf8)).write(to: log)
        #expect(await source.fetch(previous: fresh) == fresh)
        try FileManager.default.removeItem(at: source.authFile)
        #expect(await source.fetch(previous: fresh).isEmpty)
    }

    @Test func expiredSharedAllowanceIsUnknownAndDoesNotEmitAFalseReset() async throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let source = GrokUsageSource(home: home, environment: [:])
        try FileManager.default.createDirectory(at: source.directory, withIntermediateDirectories: true)
        try Data().write(to: source.authFile)
        let previous = try #require(GrokReading.parse(billingLine(period: "USAGE_PERIOD_TYPE_MONTHLY", end: "2026-01-01T00:00:00Z"))).accountUsage
        let result = await source.fetch(previous: [previous])
        #expect(result.first?.monthlyPct == nil)
        #expect(result.first?.windows == [.monthly])
        #expect(result.first?.failure != nil)
        #expect(EventDiff.usage(old: [previous], new: result).isEmpty)
    }

    @Test func configuredPathsAreUsedWithoutReadingCredentials() {
        let source = GrokUsageSource(environment: ["GROK_HOME": "/tmp/custom-grok", "GROK_AUTH_PATH": "/tmp/custom-auth.json"])
        #expect(source.directory.path == "/tmp/custom-grok")
        #expect(source.authFile.path == "/tmp/custom-auth.json")
    }

    @Test func oversizedLogSkipsThePartialHeadAndReadsTheRetainedTail() throws {
        let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        var data = Data(repeating: UInt8(ascii: "x"), count: GrokUsageSource.maxLogBytes + 100)
        data += Data("\n".utf8) + (try billingLine()) + Data("\n".utf8)
        try data.write(to: file)
        #expect(try GrokUsageSource.newestReading(in: file)?.percentage == 64)
    }

    @Test func unreadableLogRetainsTheLastValueWithAWarning() async throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let source = GrokUsageSource(home: home, environment: [:])
        try FileManager.default.createDirectory(at: source.directory.appendingPathComponent("logs/unified.jsonl"), withIntermediateDirectories: true)
        try Data().write(to: source.authFile)
        let previous = try #require(GrokReading.parse(billingLine())).accountUsage
        let result = await source.fetch(previous: [previous])
        #expect(result.first?.weeklyPct == 64)
        #expect(result.first?.observedAt == previous.observedAt)
        #expect(result.first?.failure != nil)
    }

    @Test func monthlyThresholdsAndResetsUseTheExistingEventFlow() {
        let old = AccountUsage(id: "grok", label: "grok", provider: .grok, monthlyPct: 64)
        var new = old
        new.monthlyPct = 95
        let events = EventDiff.usage(old: [old], new: [new])
        #expect(events.count == 1)
        #expect(events.first?.headline == "grok monthly at 90%")
        #expect(EventDiff.usage(old: [new], new: [new]).isEmpty)
        #expect(EventDiff.usage(old: [new], new: [old]).first?.kind == .limitReset)
    }

    @Test func oldAccountEncodingStillDecodesWithBothWindows() throws {
        let old = Data(#"{"id":"codex","label":"codex","provider":"codex","sessionPct":15,"weeklyPct":35}"#.utf8)
        let usage = try JSONDecoder().decode(AccountUsage.self, from: old)
        #expect(usage.monthlyPct == nil)
        #expect(usage.windows == [.session, .weekly])
        #expect(usage.primaryPct == 15)
    }
}
