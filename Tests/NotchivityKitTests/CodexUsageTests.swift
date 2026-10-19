import Foundation
import Testing
@testable import NotchivityKit

/// A rollout line as Codex writes it, trimmed to the parts the reading needs.
private func rolloutLine(timestamp: String = "2026-09-14T07:46:16.444Z",
                         primaryResetsAt: Int = 2_000_000_000,
                         secondaryResetsAt: Int = 2_000_100_000) -> Data {
    let json: [String: Any] = [
        "timestamp": timestamp,
        "type": "event_msg",
        "payload": [
            "type": "token_count",
            "rate_limits": [
                "primary": ["used_percent": 76.0, "window_minutes": 300, "resets_at": primaryResetsAt],
                "secondary": ["used_percent": 12.0, "window_minutes": 10080, "resets_at": secondaryResetsAt],
                "plan_type": "plus",
            ],
        ],
    ]
    return try! JSONSerialization.data(withJSONObject: json)
}

@Suite struct CodexUsageTests {
    @Test func parsesPrimaryAsSessionAndSecondaryAsWeek() throws {
        let reading = try #require(CodexReading.parse(rolloutLine()))

        #expect(reading.sessionPct == 76)
        #expect(reading.weeklyPct == 12)
        #expect(reading.sessionResetsAt == 2_000_000_000)
        #expect(reading.weeklyResetsAt == 2_000_100_000)
        #expect(reading.observedAt == ISO8601DateFormatter().date(from: "2026-09-14T07:46:16Z")!.timeIntervalSince1970 + 0.444)
    }

    @Test func linesWithoutRateLimitsAreSkipped() {
        let other = try! JSONSerialization.data(withJSONObject: ["type": "event_msg", "payload": ["type": "task_complete"]])
        #expect(CodexReading.parse(other) == nil)
        #expect(CodexReading.parse(Data("not json".utf8)) == nil)
    }

    @Test func readingBecomesACodexAccount() throws {
        let reading = try #require(CodexReading.parse(rolloutLine()))
        let usage = reading.accountUsage(now: 1_999_000_000)

        #expect(usage.provider == .codex)
        #expect(usage.label == "codex")
        #expect(usage.sessionPct == 76)
        #expect(usage.observedAt == reading.observedAt)
    }

    /// The reading is only as fresh as the last Codex turn, so a window whose reset has
    /// already passed is empty again rather than stuck at its last percentage.
    @Test func windowsPastTheirResetReadEmpty() throws {
        let reading = try #require(CodexReading.parse(rolloutLine()))
        let usage = reading.accountUsage(now: 2_000_050_000)

        #expect(usage.sessionPct == 0)
        #expect(usage.sessionResetsAt == nil)
        #expect(usage.weeklyPct == 12)
        #expect(usage.weeklyResetsAt == 2_000_100_000)
    }

    @Test func readsTheLastRateLimitsInAFilesTail() throws {
        let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("rollout-\(UUID()).jsonl")
        let lines = [rolloutLine(primaryResetsAt: 1), Data(#"{"type":"event_msg"}"#.utf8), rolloutLine(primaryResetsAt: 2)]
        try Data(lines.map { $0 + Data("\n".utf8) }.joined()).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        #expect(CodexUsageSource.reading(inTailOf: file)?.sessionResetsAt == 2)
    }

    @Test func newestReadingUsesEventTimeAcrossSessionsAndDays() throws {
        let sessions = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: sessions) }
        let files = [
            ("2026/09/14/rollout-2026-09-14T12-00-00-new.jsonl", "2026-09-14T12:01:00Z"),
            ("2026/09/14/rollout-2026-09-14T08-00-00-older.jsonl", "2026-09-14T13:00:00Z"),
            ("2026/09/13/rollout-2026-09-13T08-00-00.jsonl", "2026-09-14T14:00:00Z"),
            ("2026/09/12/rollout-2026-09-12T08-00-00.jsonl", "2026-09-14T11:00:00Z"),
            ("2026/09/11/rollout-2026-09-11T08-00-00.jsonl", "2026-09-14T15:00:00Z"),
        ]
        for (path, timestamp) in files {
            let file = sessions.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try (rolloutLine(timestamp: timestamp) + Data("\n".utf8)).write(to: file)
        }

        let today = sessions.appendingPathComponent("2026/09/14")
        #expect(CodexUsageSource.newestReading(in: sessions)?.observedAt == UsageParsing.epochSeconds("2026-09-14T15:00:00Z"))
        try FileManager.default.removeItem(at: sessions.appendingPathComponent("2026/09/11"))
        #expect(CodexUsageSource.newestReading(in: sessions)?.observedAt == UsageParsing.epochSeconds("2026-09-14T14:00:00Z"))
        try FileManager.default.removeItem(at: sessions.appendingPathComponent("2026/09/13"))
        #expect(CodexUsageSource.newestReading(in: sessions)?.observedAt == UsageParsing.epochSeconds("2026-09-14T13:00:00Z"))
        try Data("not a usage record\n".utf8).write(to: today.appendingPathComponent("rollout-2026-09-14T16-00-00-empty.jsonl"))
        #expect(CodexUsageSource.newestReading(in: sessions)?.observedAt == UsageParsing.epochSeconds("2026-09-14T13:00:00Z"))
    }

    @Test func noCodexDirectoryMeansNoAccounts() async {
        let source = CodexUsageSource(home: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString))
        #expect(await source.fetch(previous: []).isEmpty)
    }

    @Test func dayDirectoriesComeBackNewestFirst() throws {
        let sessions = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        for day in ["2026/09/13", "2026/09/14", "2025/12/31"] {
            try FileManager.default.createDirectory(at: sessions.appendingPathComponent(day), withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: sessions) }

        let days = CodexUsageSource.dayDirectories(in: sessions, limit: 3).map { $0.path.hasSuffix("2026/09/14") ? "new" : $0.lastPathComponent }
        #expect(days == ["new", "13", "31"])
    }
}
