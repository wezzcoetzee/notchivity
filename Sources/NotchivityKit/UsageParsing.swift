import Foundation

public enum UsageParsing {
    public static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        return nil
    }

    public static func percentage(_ value: Any?) -> Double? {
        number(value).map { min(100, max(0, $0)) }
    }

    public static func epochSeconds(_ value: Any?) -> Double? {
        if let seconds = number(value) { return seconds }
        guard let string = value as? String else { return nil }
        return (fractional.date(from: string) ?? whole.date(from: string))?.timeIntervalSince1970
    }

    // Shared because the spend reader parses a timestamp per log line; ISO8601DateFormatter is thread safe.
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let whole = ISO8601DateFormatter()
}
