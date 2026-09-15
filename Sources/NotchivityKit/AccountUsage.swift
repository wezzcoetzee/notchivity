import Foundation

/// One account's rate-limit reading: session (5 hour) and weekly (7 day) windows.
public struct AccountUsage: Codable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var sessionPct: Double?
    public var weeklyPct: Double?
    public var sessionResetsAt: Double?
    public var weeklyResetsAt: Double?
    /// Set when the last poll for this account failed; the percentages are then stale.
    public var failure: UsageError?

    public var error: String? { failure?.description }

    public init(id: String, label: String, sessionPct: Double? = nil, weeklyPct: Double? = nil,
                sessionResetsAt: Double? = nil, weeklyResetsAt: Double? = nil, failure: UsageError? = nil) {
        self.id = id
        self.label = label
        self.sessionPct = sessionPct
        self.weeklyPct = weeklyPct
        self.sessionResetsAt = sessionResetsAt
        self.weeklyResetsAt = weeklyResetsAt
        self.failure = failure
    }

    public enum Window: String, CaseIterable { case session, weekly }

    public func pct(_ window: Window) -> Double? {
        window == .session ? sessionPct : weeklyPct
    }

    public func resetsAt(_ window: Window) -> Double? {
        window == .session ? sessionResetsAt : weeklyResetsAt
    }

    /// Parses the `/api/oauth/usage` response body.
    public static func parse(_ json: [String: Any], id: String, label: String) -> AccountUsage {
        let five = json["five_hour"] as? [String: Any]
        let seven = json["seven_day"] as? [String: Any]
        return AccountUsage(id: id, label: label,
                            sessionPct: UsageParsing.percentage(five?["utilization"]),
                            weeklyPct: UsageParsing.percentage(seven?["utilization"]),
                            sessionResetsAt: UsageParsing.epochSeconds(five?["resets_at"]),
                            weeklyResetsAt: UsageParsing.epochSeconds(seven?["resets_at"]))
    }
}
