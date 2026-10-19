import Foundation

/// One rate-limit record as Codex wrote it into a rollout log.
public struct CodexReading: Equatable {
    /// When Codex recorded it, which is the last time it ran a turn.
    public var observedAt: Double
    public var sessionPct: Double?
    public var sessionResetsAt: Double?
    public var weeklyPct: Double?
    public var weeklyResetsAt: Double?

    public init(observedAt: Double, sessionPct: Double? = nil, sessionResetsAt: Double? = nil,
                weeklyPct: Double? = nil, weeklyResetsAt: Double? = nil) {
        self.observedAt = observedAt
        self.sessionPct = sessionPct
        self.sessionResetsAt = sessionResetsAt
        self.weeklyPct = weeklyPct
        self.weeklyResetsAt = weeklyResetsAt
    }

    /// Parses one rollout line, returning nil for the many lines that carry no rate limits.
    /// `primary` is the 5 hour window and `secondary` the 7 day one.
    public static func parse(_ line: Data) -> CodexReading? {
        guard let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let payload = root["payload"] as? [String: Any],
              let limits = payload["rate_limits"] as? [String: Any] else { return nil }
        let primary = limits["primary"] as? [String: Any]
        let secondary = limits["secondary"] as? [String: Any]
        guard primary != nil || secondary != nil else { return nil }
        return CodexReading(observedAt: UsageParsing.epochSeconds(root["timestamp"]) ?? Date().timeIntervalSince1970,
                            sessionPct: UsageParsing.percentage(primary?["used_percent"]),
                            sessionResetsAt: UsageParsing.epochSeconds(primary?["resets_at"]),
                            weeklyPct: UsageParsing.percentage(secondary?["used_percent"]),
                            weeklyResetsAt: UsageParsing.epochSeconds(secondary?["resets_at"]))
    }

    /// A window whose reset time has passed rolled over after this record was written, and
    /// nothing has run since or there would be a newer record, so it is empty again.
    public func accountUsage(now: Double) -> AccountUsage {
        let session = expire(pct: sessionPct, resetsAt: sessionResetsAt, now: now)
        let weekly = expire(pct: weeklyPct, resetsAt: weeklyResetsAt, now: now)
        return AccountUsage(id: CodexUsageSource.accountId, label: CodexUsageSource.label, provider: .codex,
                            sessionPct: session.pct, weeklyPct: weekly.pct,
                            sessionResetsAt: session.resetsAt, weeklyResetsAt: weekly.resetsAt,
                            observedAt: observedAt)
    }

    private func expire(pct: Double?, resetsAt: Double?, now: Double) -> (pct: Double?, resetsAt: Double?) {
        guard let resetsAt, resetsAt <= now else { return (pct, resetsAt) }
        return (0, nil)
    }
}

/// Codex writes its rate limits into the rollout log of every session, so usage is read
/// from disk: no token, no second caller on OpenAI's API. The cost is freshness, since the
/// reading only moves when Codex runs. `observedAt` carries that so the UI can say so.
public struct CodexUsageSource: UsageSource {
    public let provider = UsageProvider.codex
    static let accountId = "codex"
    static let label = "codex"
    /// Rollouts hold one line per event; the rate limits are near the end of the last turn.
    static let tailBytes: UInt64 = 512 * 1024

    let directory: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        directory = home.appendingPathComponent(".codex")
    }

    public func fetch(previous: [AccountUsage]) async -> [AccountUsage] {
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("auth.json").path) else { return [] }
        guard let reading = Self.newestReading(in: directory.appendingPathComponent("sessions")) else {
            return [AccountUsage(id: Self.accountId, label: Self.label, provider: .codex,
                                 failure: .other("no usage recorded yet, run codex once"))]
        }
        return [reading.accountUsage(now: Date().timeIntervalSince1970)]
    }

    /// Sessions can resume long after creation, so filenames and day directories do not
    /// determine which usage record is freshest.
    static func newestReading(in sessions: URL) -> CodexReading? {
        var newest: CodexReading?
        for day in dayDirectories(in: sessions) {
            for rollout in newestFirst(day) where rollout.pathExtension == "jsonl" {
                guard let reading = reading(inTailOf: rollout) else { continue }
                if newest.map({ reading.observedAt > $0.observedAt }) ?? true {
                    newest = reading
                }
            }
        }
        return newest
    }

    /// Rollouts live under `sessions/YYYY/MM/DD` and their names start with a timestamp, so
    /// descending name order is newest-first at every level.
    static func dayDirectories(in sessions: URL, limit: Int = .max) -> [URL] {
        var days: [URL] = []
        for year in subdirectories(sessions) {
            for month in subdirectories(year) {
                for day in subdirectories(month) {
                    days.append(day)
                    if days.count == limit { return days }
                }
            }
        }
        return days
    }

    static func newestFirst(_ directory: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    static func subdirectories(_ directory: URL) -> [URL] {
        newestFirst(directory).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    /// Reads only the end of the file: a long session's rollout runs to megabytes and the
    /// record we want is written after the last turn.
    static func reading(inTailOf file: URL) -> CodexReading? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        let offset = end > tailBytes ? end - tailBytes : 0
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd() else { return nil }
        var lines = data.split(separator: UInt8(ascii: "\n"))
        // Seeking mid-file lands inside a line; that fragment is not parseable JSON.
        if offset > 0, !lines.isEmpty { lines.removeFirst() }
        for line in lines.reversed() {
            if let reading = CodexReading.parse(Data(line)) { return reading }
        }
        return nil
    }
}
