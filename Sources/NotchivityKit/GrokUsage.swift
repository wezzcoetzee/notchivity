import Foundation

/// Grok Build records the included allowance in its unified log after each billing fetch.
/// Session token totals in `sessions/*/usage.json` are not subscription limits.
struct GrokReading: Equatable {
    let observedAt: Double
    let window: AccountUsage.Window
    let percentage: Double
    let resetsAt: Double

    private struct Entry: Decodable {
        let ts: String
        let msg: String
        let ctx: Context

        struct Context: Decodable {
            let config: Config
        }

        struct Config: Decodable {
            let creditUsagePercent: Double?
            let currentPeriod: Period?
            let monthlyLimit: Cents?
            let used: Cents?
            let billingPeriodEnd: String?
        }

        struct Period: Decodable {
            let type: String?
            let end: String?
        }

        struct Cents: Decodable {
            let val: Int?
        }
    }

    static func parse(_ line: Data) -> GrokReading? {
        guard let entry = try? JSONDecoder().decode(Entry.self, from: line),
              entry.msg == "billing: fetched credits config",
              let observedAt = UsageParsing.epochSeconds(entry.ts) else { return nil }
        let config = entry.ctx.config
        let window: AccountUsage.Window
        let percentage: Double
        let end: String?
        if let period = config.currentPeriod {
            guard let pct = config.creditUsagePercent else { return nil }
            switch period.type {
            case "USAGE_PERIOD_TYPE_WEEKLY": window = .weekly
            case "USAGE_PERIOD_TYPE_MONTHLY": window = .monthly
            default: return nil
            }
            percentage = pct
            end = period.end
        } else if let limit = config.monthlyLimit?.val, limit > 0, let used = config.used {
            window = .monthly
            percentage = Double(used.val ?? 0) / Double(limit) * 100
            end = config.billingPeriodEnd
        } else {
            return nil
        }
        guard percentage.isFinite, let resetsAt = UsageParsing.epochSeconds(end) else { return nil }
        return GrokReading(observedAt: observedAt, window: window,
                           percentage: min(100, max(0, percentage)), resetsAt: resetsAt)
    }

    var accountUsage: AccountUsage {
        AccountUsage(id: GrokUsageSource.accountId, label: "grok", provider: .grok,
                     weeklyPct: window == .weekly ? percentage : nil,
                     weeklyResetsAt: window == .weekly ? resetsAt : nil,
                     observedAt: observedAt,
                     monthlyPct: window == .monthly ? percentage : nil,
                     monthlyResetsAt: window == .monthly ? resetsAt : nil)
    }
}

public struct GrokUsageSource: UsageSource {
    public let provider = UsageProvider.grok
    static let accountId = "grok"
    // Grok trims this log at 5 MiB. Read its retained history, not just a busy turn's tail.
    static let maxLogBytes = 5 * 1024 * 1024
    let directory: URL
    let authFile: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                environment: [String: String] = ProcessInfo.processInfo.environment) {
        directory = environment["GROK_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".grok")
        authFile = environment["GROK_AUTH_PATH"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? directory.appendingPathComponent("auth.json")
    }

    public func fetch(previous: [AccountUsage]) async -> [AccountUsage] {
        guard FileManager.default.fileExists(atPath: authFile.path) else { return [] }
        var usage = previous.first { $0.id == Self.accountId && $0.provider == .grok }
        do {
            if let reading = try Self.newestReading(in: directory.appendingPathComponent("logs/unified.jsonl")),
               reading.observedAt >= (usage?.observedAt ?? -.infinity) {
                usage = reading.accountUsage
            }
        } catch {
            var failed = usage ?? AccountUsage(id: Self.accountId, label: "grok", provider: .grok)
            failed.failure = .other("Grok usage log unreadable")
            return [failed]
        }
        var result = usage ?? AccountUsage(id: Self.accountId, label: "grok", provider: .grok,
                                          failure: .other("no billing snapshot yet, open grok and run /usage"))
        if let reset = result.windows.first.flatMap(result.resetsAt), reset <= Date().timeIntervalSince1970 {
            // A shared pool can be used outside this CLI, so an old snapshot cannot prove 0%.
            result.weeklyPct = nil
            result.monthlyPct = nil
            result.failure = .other("usage period ended, open grok and run /usage")
        }
        return [result]
    }

    static func newestReading(in file: URL) throws -> GrokReading? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let end = try handle.seekToEnd()
        let offset = end > UInt64(maxLogBytes) ? end - UInt64(maxLogBytes) : 0
        try handle.seek(toOffset: offset)
        let data = try handle.read(upToCount: maxLogBytes) ?? Data()
        var lines = data.split(separator: UInt8(ascii: "\n"))
        if offset > 0, !lines.isEmpty { lines.removeFirst() }
        return lines.compactMap { GrokReading.parse(Data($0)) }.max { $0.observedAt < $1.observedAt }
    }
}
