import Foundation

public enum TimeFormatting {
    public static func countdown(secondsRemaining: Int) -> String {
        guard secondsRemaining > 0 else { return "now" }
        let days = secondsRemaining / 86_400
        let hours = (secondsRemaining % 86_400) / 3600
        let minutes = (secondsRemaining % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return minutes > 0 ? "\(minutes)m" : "<1m"
    }

    public static func freshness(secondsAgo: Int) -> String {
        let seconds = max(0, secondsAgo)
        if seconds < 60 { return "updated \(seconds)s ago" }
        let minutes = seconds / 60
        return minutes < 60 ? "updated \(minutes)m ago" : "updated \(minutes / 60)h ago"
    }
}
