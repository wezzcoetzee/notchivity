import Foundation
import Testing

@testable import NotchivityKit

/// An assistant line as Claude Code logs it, trimmed to the parts spend reads.
private func logLine(
    id: String = "msg_1", request: String = "req_1", model: String = "claude-opus-5-5", at: Date = Date(),
    input: Int = 10, output: Int = 1000, write5m: Int = 2000, write1h: Int = 4000, read: Int = 100_000
) -> String {
    let json: [String: Any] = [
        "type": "assistant",
        "requestId": request,
        "timestamp": ISO8601DateFormatter().string(from: at),
        "message": [
            "id": id, "model": model, "role": "assistant",
            "usage": [
                "input_tokens": input, "output_tokens": output, "cache_read_input_tokens": read,
                "cache_creation_input_tokens": write5m + write1h,
                "cache_creation": ["ephemeral_5m_input_tokens": write5m, "ephemeral_1h_input_tokens": write1h],
            ],
        ],
    ]
    return String(data: try! JSONSerialization.data(withJSONObject: json), encoding: .utf8)!
}

private func response(_ line: String) throws -> LoggedResponse {
    try #require(LoggedResponse.parse(Data(line.utf8)))
}

private func spend(weekStart: Date, today: Int, todayCost: Double, weekCost: Double) -> Spend {
    var days = Array(repeating: Spend.Day(), count: 7)
    days[today].cost = todayCost
    if today > 0 { days[0].cost = weekCost - todayCost }
    return Spend(weekStart: weekStart, days: days, today: today)
}

@Suite struct SpendTests {
    @Test func pricesEachTokenKindAtItsOwnRate() throws {
        let opus = try response(logLine())
        // 10 in at $4, 1K out at $20, 2K 5m writes at 1.25x, 4K 1h writes at 2x, 100K reads at $0.20.
        #expect(abs(opus.cost - (40 + 20_000 + 10_000 + 32_000 + 20_000) / 1e6) < 1e-12)
        #expect(opus.tokens.total == 107_010)
    }

    @Test func haikuPromptOver100KUsesTheLongTier() throws {
        let long = try response(logLine(model: "claude-haiku-5-5", input: 200_000, output: 1000, write5m: 0, write1h: 0, read: 0))
        #expect(abs(long.cost - (200_000 * 0.5 + 1000 * 2.5) / 1e6) < 1e-12)
    }

    @Test func unknownIdsPriceAsTheirFamilyAndSyntheticIsFree() throws {
        #expect(try response(logLine(model: "claude-opus-6")).cost == response(logLine()).cost)
        #expect(try response(logLine(model: "<synthetic>")).cost == 0)
    }

    @Test func readerCountsEachResponseOnceAcrossLinkedFoldersAndAppends() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let projects = home.appendingPathComponent(".claude/projects/p")
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude-two"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: home.appendingPathComponent(".claude-two/projects"), withDestinationURL: home.appendingPathComponent(".claude/projects"))
        defer { try? FileManager.default.removeItem(at: home) }

        let now = Date()
        let lastWeek = Spend.weekStart(of: now).addingTimeInterval(-3600)
        let file = projects.appendingPathComponent("s.jsonl")
        // The same response twice (one line per content block) and one from last week.
        try ([logLine(at: now), logLine(at: now), logLine(id: "old", at: lastWeek)].joined(separator: "\n") + "\n")
            .write(to: file, atomically: true, encoding: .utf8)

        let reader = SpendReader(home: home)
        let first = try #require(await reader.read(now: now))
        #expect(first.todayCost == first.weekCost)
        #expect(first.weekTokens == 107_010)

        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((logLine(id: "msg_2", at: now) + "\n").utf8))
        try handle.close()
        let second = try #require(await reader.read(now: now))
        #expect(second.weekTokens == 2 * 107_010)
    }

    @Test func noLogsMeansNoSpend() async {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(await SpendReader(home: home).read() == nil)
    }

    @Test func alertsOnceWhenALimitIsCrossed() {
        let week = Spend.weekStart(of: Date())
        let before = spend(weekStart: week, today: 3, todayCost: 40, weekCost: 200)
        let after = spend(weekStart: week, today: 3, todayCost: 46, weekCost: 206)

        let events = EventDiff.spend(old: before, new: after, dailyLimit: 60, weeklyLimit: 400)
        #expect(events.map(\.headline) == ["spend at 76% today · $46.00 of $60"])
        #expect(events.first?.detail == "week $206.00 of $400")
        #expect(EventDiff.spend(old: after, new: after, dailyLimit: 60, weeklyLimit: 400).isEmpty)
        #expect(EventDiff.spend(old: before, new: after, dailyLimit: 0, weeklyLimit: 0).isEmpty)
    }

    @Test func aNewDayStartsFromZero() {
        let week = Spend.weekStart(of: Date())
        let yesterday = spend(weekStart: week, today: 2, todayCost: 50, weekCost: 100)
        let today = spend(weekStart: week, today: 3, todayCost: 46, weekCost: 146)
        #expect(EventDiff.spend(old: yesterday, new: today, dailyLimit: 60, weeklyLimit: 0).map(\.headline) == ["spend at 76% today · $46.00 of $60"])
    }
}
