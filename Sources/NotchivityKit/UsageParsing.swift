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
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date.timeIntervalSince1970 }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)?.timeIntervalSince1970
    }
}
