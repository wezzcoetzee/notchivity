import Foundation

/// API list prices in dollars per million tokens. Cache writes are a fixed multiple of input
/// (1.25x for the 5 minute TTL, 2x for 1 hour); cache reads differ by model, so they are listed.
struct ModelPrice: Equatable {
    let input: Double
    let output: Double
    let cacheRead: Double
    /// Haiku 5.5 bills a prompt over 100K tokens at a higher tier.
    var longPrompt: Tier?

    struct Tier: Equatable {
        let input: Double
        let output: Double
        let cacheRead: Double
    }

    static let longPromptTokens = 100_000

    /// Most specific prefix first, so "claude-opus-5" never claims "claude-opus-5-5".
    /// Checked 2026-11; update alongside Anthropic's pricing page.
    private static let table: [(prefix: String, price: ModelPrice)] = [
        ("claude-fable-5-2", .init(input: 8, output: 40, cacheRead: 0.20)),
        ("claude-mythos-5-2", .init(input: 8, output: 40, cacheRead: 0.20)),
        ("claude-fable-5-1", .init(input: 10, output: 50, cacheRead: 0.25)),
        ("claude-mythos-5-1", .init(input: 10, output: 50, cacheRead: 0.25)),
        ("claude-fable-5", .init(input: 10, output: 50, cacheRead: 1)),
        ("claude-mythos-5", .init(input: 10, output: 50, cacheRead: 1)),
        ("claude-opus-5-5", .init(input: 4, output: 20, cacheRead: 0.20)),
        ("claude-opus-5", .init(input: 5, output: 25, cacheRead: 0.50)),
        ("claude-opus-4-8", .init(input: 5, output: 25, cacheRead: 0.50)),
        ("claude-opus-4-7", .init(input: 5, output: 25, cacheRead: 0.50)),
        ("claude-opus-4-6", .init(input: 5, output: 25, cacheRead: 0.50)),
        ("claude-opus-4-5", .init(input: 5, output: 25, cacheRead: 0.50)),
        ("claude-opus-4", .init(input: 15, output: 75, cacheRead: 1.50)),
        ("claude-sonnet-5-5", .init(input: 2, output: 10, cacheRead: 0.10)),
        ("claude-sonnet-5", .init(input: 2, output: 10, cacheRead: 0.20)),
        ("claude-sonnet-4", .init(input: 3, output: 15, cacheRead: 0.30)),
        (
            "claude-haiku-5-5",
            .init(input: 0.10, output: 0.50, cacheRead: 0.01, longPrompt: .init(input: 0.50, output: 2.50, cacheRead: 0.05))
        ),
        ("claude-haiku-4-5", .init(input: 1, output: 5, cacheRead: 0.10)),
    ]

    /// An id the table does not know yet (a newer release) is priced as the newest model of
    /// its family; anything else (`<synthetic>`) is not a billed model.
    static func forModel(_ model: String) -> ModelPrice? {
        if let match = table.first(where: { model.hasPrefix($0.prefix) }) { return match.price }
        let newest = [
            "fable": "claude-fable-5-2", "mythos": "claude-mythos-5-2", "opus": "claude-opus-5-5", "sonnet": "claude-sonnet-5-5", "haiku": "claude-haiku-5-5",
        ]
        guard let family = newest.first(where: { model.contains($0.key) }) else { return nil }
        return table.first { $0.prefix == family.value }?.price
    }
}

/// The token counts of one API response.
struct TokenCount: Equatable {
    var input = 0
    var output = 0
    var cacheWrite5m = 0
    var cacheWrite1h = 0
    var cacheRead = 0

    var total: Int { input + output + cacheWrite5m + cacheWrite1h + cacheRead }

    func cost(_ price: ModelPrice) -> Double {
        let prompt = input + cacheWrite5m + cacheWrite1h + cacheRead
        let tier =
            prompt > ModelPrice.longPromptTokens
            ? price.longPrompt : nil
        let inputRate = tier?.input ?? price.input
        let dollars =
            Double(input) * inputRate + Double(output) * (tier?.output ?? price.output)
            + Double(cacheWrite5m) * inputRate * 1.25 + Double(cacheWrite1h) * inputRate * 2
            + Double(cacheRead) * (tier?.cacheRead ?? price.cacheRead)
        return dollars / 1_000_000
    }
}

/// One assistant response as Claude Code logged it.
struct LoggedResponse: Equatable {
    /// Claude Code writes a response once per content block, all with the same usage, so the
    /// message and request ids together count it once.
    let key: String
    let model: String
    let at: Double
    let tokens: TokenCount

    var cost: Double { ModelPrice.forModel(model).map(tokens.cost) ?? 0 }

    static let marker = Data("\"output_tokens\"".utf8)

    /// Nil for the many lines that are not an assistant response with usage.
    static func parse(_ line: Data) -> LoggedResponse? {
        guard line.range(of: marker) != nil,
            let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            let message = root["message"] as? [String: Any],
            let usage = message["usage"] as? [String: Any],
            let id = message["id"] as? String,
            let at = UsageParsing.epochSeconds(root["timestamp"])
        else { return nil }
        func count(_ value: Any?) -> Int { UsageParsing.number(value).map { Int($0) } ?? 0 }
        // Older logs carry only the total cache write; it was all 5 minute writes then.
        let written = count(usage["cache_creation_input_tokens"])
        let split = usage["cache_creation"] as? [String: Any]
        let oneHour = count(split?["ephemeral_1h_input_tokens"])
        return LoggedResponse(
            key: "\(id):\(root["requestId"] as? String ?? "")",
            model: message["model"] as? String ?? "",
            at: at,
            tokens: TokenCount(
                input: count(usage["input_tokens"]), output: count(usage["output_tokens"]),
                cacheWrite5m: split == nil ? written : count(split?["ephemeral_5m_input_tokens"]),
                cacheWrite1h: oneHour, cacheRead: count(usage["cache_read_input_tokens"])))
    }
}

/// What the tokens spent this week would cost at API list prices, day by day from Monday.
public struct Spend: Equatable, Sendable {
    public struct Day: Equatable, Sendable {
        public var cost = 0.0
        public var tokens = 0
        public init(cost: Double = 0, tokens: Int = 0) {
            self.cost = cost
            self.tokens = tokens
        }
    }

    public let weekStart: Date
    /// Seven days, Monday first; days still ahead are empty.
    public let days: [Day]
    /// Today's index into `days`.
    public let today: Int

    public init(weekStart: Date, days: [Day], today: Int) {
        self.weekStart = weekStart
        self.days = days
        self.today = today
    }

    public var todayCost: Double { days[today].cost }
    public var weekCost: Double { days.reduce(0) { $0 + $1.cost } }
    public var weekTokens: Int { days.reduce(0) { $0 + $1.tokens } }

    /// The strip reads Monday to Sunday whatever the locale's first weekday is.
    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        return calendar
    }

    public static func weekStart(of date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// "$48.20", or whole dollars past $1,000 where cents are noise.
    public static func money(_ dollars: Double) -> String {
        dollars >= 1000 ? "$" + dollars.formatted(.number.precision(.fractionLength(0))) : String(format: "$%.2f", dollars)
    }

    /// A limit, which is whole dollars: "$60".
    public static func limit(_ dollars: Double) -> String {
        "$" + dollars.formatted(.number.precision(.fractionLength(0)))
    }

    /// "980K", "312M", "1.42B".
    public static func tokens(_ count: Int) -> String {
        let n = Double(count)
        switch n {
        case 1e9...: return String(format: "%.2fB", n / 1e9)
        case 1e6...: return String(format: "%.0fM", n / 1e6)
        case 1e3...: return String(format: "%.0fK", n / 1e3)
        default: return "\(count)"
        }
    }
}

/// Reads Claude Code's session logs for this week's token spend. Every sign-in directory's
/// `projects` folder is read once even when one links to another, and each file only from
/// where the last read stopped, since a week of logs runs to gigabytes.
public actor SpendReader {
    private let roots: [URL]
    private var weekStart: Date?
    private var offsets: [String: UInt64] = [:]
    private var seen: Set<String> = []
    private var days: [Spend.Day] = Array(repeating: .init(), count: 7)

    private static let chunk = 4 * 1024 * 1024

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        let directories = [home.appendingPathComponent(ClaudeAccountDiscovery.defaultDirectoryName)] + ClaudeAccountDiscovery.siblingDirectories(home: home)
        var unique: [URL] = []
        for directory in directories {
            let projects = directory.appendingPathComponent("projects").resolvingSymlinksInPath()
            if !unique.contains(projects) { unique.append(projects) }
        }
        roots = unique
    }

    /// Nil when no Claude Code logs exist, so the panel shows nothing rather than $0.00.
    public func read(now: Date = Date()) -> Spend? {
        let fileManager = FileManager.default
        let existing = roots.filter { fileManager.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { return nil }
        let start = Spend.weekStart(of: now)
        // A new week starts from nothing; last week's files are skipped by date below.
        if start != weekStart {
            weekStart = start
            offsets = [:]
            seen = []
            days = Array(repeating: .init(), count: 7)
        }
        for root in existing { scan(root, since: start) }
        let today = Spend.calendar.dateComponents([.day], from: start, to: Spend.calendar.startOfDay(for: now)).day ?? 0
        return Spend(weekStart: start, days: days, today: min(max(today, 0), 6))
    }

    private func scan(_ root: URL, since start: Date) {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return }
        for case let file as URL in files where file.pathExtension == "jsonl" {
            guard let values = try? file.resourceValues(forKeys: Set(keys)),
                let modified = values.contentModificationDate, modified >= start,
                let size = values.fileSize.map(UInt64.init)
            else { continue }
            // A file that shrank was rewritten; the seen set keeps a re-read from counting twice.
            let offset = offsets[file.path].flatMap { $0 <= size ? $0 : nil } ?? 0
            guard offset < size else { continue }
            offsets[file.path] = read(file, from: offset, since: start)
        }
    }

    /// Counts every complete line from `offset` and returns where the last one ended, so a
    /// line still being written is read whole next time.
    private func read(_ file: URL, from offset: UInt64, since start: Date) -> UInt64 {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return offset }
        defer { try? handle.close() }
        try? handle.seek(toOffset: offset)
        var consumed = offset
        var pending = Data()
        while let data = try? handle.read(upToCount: Self.chunk), !data.isEmpty {
            pending.append(data)
            var lineStart = pending.startIndex
            while let newline = pending[lineStart...].firstIndex(of: 0x0A) {
                count(pending[lineStart..<newline], since: start)
                lineStart = pending.index(after: newline)
            }
            consumed += UInt64(lineStart - pending.startIndex)
            pending = Data(pending[lineStart...])
        }
        return consumed
    }

    private func count(_ line: Data, since start: Date) {
        guard let response = LoggedResponse.parse(line), response.at >= start.timeIntervalSince1970,
            seen.insert(response.key).inserted
        else { return }
        let day = Spend.calendar.dateComponents([.day], from: start, to: Date(timeIntervalSince1970: response.at)).day ?? 0
        guard (0..<7).contains(day) else { return }
        days[day].cost += response.cost
        days[day].tokens += response.tokens.total
    }
}
