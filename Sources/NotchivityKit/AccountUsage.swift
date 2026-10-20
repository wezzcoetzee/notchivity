import Foundation

/// One account's usage reading, with only the windows its provider exposes.
public struct AccountUsage: Codable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var provider: UsageProvider
    public var sessionPct: Double?
    public var weeklyPct: Double?
    public var monthlyPct: Double?
    public var sessionResetsAt: Double?
    public var weeklyResetsAt: Double?
    public var monthlyResetsAt: Double?
    /// Set when the last poll for this account failed; the percentages are then stale.
    public var failure: UsageError?
    /// When the reading was taken, for sources that read a recorded value rather than poll
    /// live. Nil means it is as fresh as the last refresh.
    public var observedAt: Double?
    /// A name the user typed in Settings, replacing the one discovered from the sign-in.
    public var customLabel: String?

    public var error: String? { failure?.description }

    /// The name to show for this account anywhere a human reads it.
    public var displayLabel: String { customLabel ?? label }

    public init(id: String, label: String, provider: UsageProvider = .claude,
                sessionPct: Double? = nil, weeklyPct: Double? = nil,
                sessionResetsAt: Double? = nil, weeklyResetsAt: Double? = nil,
                failure: UsageError? = nil, observedAt: Double? = nil,
                monthlyPct: Double? = nil, monthlyResetsAt: Double? = nil) {
        self.id = id
        self.label = label
        self.provider = provider
        self.sessionPct = sessionPct
        self.weeklyPct = weeklyPct
        self.sessionResetsAt = sessionResetsAt
        self.weeklyResetsAt = weeklyResetsAt
        self.monthlyPct = monthlyPct
        self.monthlyResetsAt = monthlyResetsAt
        self.failure = failure
        self.observedAt = observedAt
    }

    public enum Window: String, CaseIterable {
        case session, weekly, monthly

        public var label: String {
            switch self {
            case .session: return "session"
            case .weekly: return "week"
            case .monthly: return "month"
            }
        }
    }

    public var windows: [Window] {
        if provider == .grok {
            return monthlyResetsAt != nil || monthlyPct != nil ? [.monthly] : [.weekly]
        }
        return [.session, .weekly]
    }

    public var primaryPct: Double? { windows.first.flatMap(pct) }

    public func pct(_ window: Window) -> Double? {
        switch window {
        case .session: return sessionPct
        case .weekly: return weeklyPct
        case .monthly: return monthlyPct
        }
    }

    public func resetsAt(_ window: Window) -> Double? {
        switch window {
        case .session: return sessionResetsAt
        case .weekly: return weeklyResetsAt
        case .monthly: return monthlyResetsAt
        }
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
