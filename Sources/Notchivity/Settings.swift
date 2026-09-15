import Foundation
import NotchivityKit

/// Every user preference, persisted in UserDefaults. Slack lives in `Config` because it
/// holds a secret; launch at login lives in `LoginItemManager` because macOS owns it.
@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    enum Overflow: String, CaseIterable { case viewAll, scroll }
    enum Indicator: String, CaseIterable { case counts, dots, none }

    // PRs
    @Stored("categoryOrder", default: PRCategory.allCases.map(\.rawValue)) private var categoryOrderRaw: [String]
    @Stored("overflow", default: Overflow.viewAll.rawValue) private var overflowRaw: String
    @Stored("rowsBeforeOverflow", default: 6) var rowsBeforeOverflow: Int
    @Stored("hideDrafts", default: false) var hideDrafts: Bool
    @Stored("showAge", default: true) var showAge: Bool
    // Usage
    @Stored("underlineAccount", default: "") var underlineAccount: String
    @Stored("usageInterval", default: 180.0) var usageInterval: Double
    @Stored("thresholds", default: EventDiff.defaultThresholds) var thresholds: [Double]
    // Notifications
    @Stored("peekEnabled", default: true) var peekEnabled: Bool
    @Stored("peekDuration", default: 3.0) var peekDuration: Double
    // Displays
    @Stored("externalDisplays", default: false) var externalDisplays: Bool
    @Stored("collapsedUsage", default: true) var collapsedUsage: Bool
    @Stored("indicator", default: Indicator.counts.rawValue) private var indicatorRaw: String
    @Stored("hoverDelayMs", default: 120) var hoverDelayMs: Int

    init() {
        for child in Mirror(reflecting: self).children {
            (child.value as? StoredBase)?.attach(defaults: defaults) { [weak self] in self?.objectWillChange.send() }
        }
    }

    var categoryOrder: [PRCategory] {
        get {
            let stored = categoryOrderRaw.compactMap(PRCategory.init(rawValue:))
            return stored + PRCategory.allCases.filter { !stored.contains($0) }
        }
        set { categoryOrderRaw = newValue.map(\.rawValue) }
    }

    var overflow: Overflow {
        get { Overflow(rawValue: overflowRaw) ?? .viewAll }
        set { overflowRaw = newValue.rawValue }
    }

    var indicator: Indicator {
        get { Indicator(rawValue: indicatorRaw) ?? .counts }
        set { indicatorRaw = newValue.rawValue }
    }

    func notifies(_ kind: Event.Kind) -> Bool {
        defaults.object(forKey: "notify.\(kind.rawValue)") as? Bool ?? kind.notifiesByDefault
    }

    func setNotifies(_ kind: Event.Kind, _ on: Bool) {
        objectWillChange.send()
        defaults.set(on, forKey: "notify.\(kind.rawValue)")
    }
}

private protocol StoredBase: AnyObject {
    func attach(defaults: UserDefaults, onChange: @escaping () -> Void)
}

/// A UserDefaults-backed property that notifies the owning ObservableObject on write.
@propertyWrapper
final class Stored<Value>: StoredBase {
    private let key: String
    private let fallback: Value
    private var defaults: UserDefaults = .standard
    private var onChange: () -> Void = {}

    init(_ key: String, default fallback: Value) {
        self.key = key
        self.fallback = fallback
    }

    func attach(defaults: UserDefaults, onChange: @escaping () -> Void) {
        self.defaults = defaults
        self.onChange = onChange
    }

    var wrappedValue: Value {
        get { defaults.object(forKey: key) as? Value ?? fallback }
        set {
            onChange()
            defaults.set(newValue, forKey: key)
        }
    }
}
