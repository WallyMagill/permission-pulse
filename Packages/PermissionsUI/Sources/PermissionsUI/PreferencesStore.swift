import Foundation
import Observation

/// `@Observable` wrapper over `UserDefaults` for the six v0.7.0 preference keys.
///
/// Defaults preserve the v0.6.0 behavior baked into `SnapshotCoordinator`:
/// retention = 90 days, stale = 90 days, digest = off, weekday = 2 (Monday),
/// hour = 9, minute = 0. Reads clamp to safe ranges so a corrupted defaults
/// blob cannot push the rest of the app off a cliff.
@Observable
@MainActor
public final class PreferencesStore {
    public static let snapshotRetentionDaysKey =
        "com.wallymagill.permissionpulse.snapshotRetentionDays"
    public static let staleThresholdDaysKey =
        "com.wallymagill.permissionpulse.staleThresholdDays"
    public static let digestEnabledKey =
        "com.wallymagill.permissionpulse.digestEnabled"
    public static let digestWeekdayKey =
        "com.wallymagill.permissionpulse.digestWeekday"
    public static let digestHourKey =
        "com.wallymagill.permissionpulse.digestHour"
    public static let digestMinuteKey =
        "com.wallymagill.permissionpulse.digestMinute"

    public static let defaultSnapshotRetentionDays = 90
    public static let defaultStaleThresholdDays = 90
    public static let defaultDigestEnabled = false
    public static let defaultDigestWeekday = 2 // Monday (Calendar uses 1=Sunday...7=Saturday)
    public static let defaultDigestHour = 9
    public static let defaultDigestMinute = 0

    public static let snapshotRetentionDaysRange = 7...365
    public static let staleThresholdDaysRange = 30...365
    public static let weekdayRange = 1...7
    public static let hourRange = 0...23
    public static let minuteRange = 0...59

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var snapshotRetentionDays: Int {
        get {
            readInt(Self.snapshotRetentionDaysKey,
                    default: Self.defaultSnapshotRetentionDays,
                    range: Self.snapshotRetentionDaysRange)
        }
        set {
            writeInt(newValue, key: Self.snapshotRetentionDaysKey,
                     range: Self.snapshotRetentionDaysRange)
        }
    }

    public var staleThresholdDays: Int {
        get {
            readInt(Self.staleThresholdDaysKey,
                    default: Self.defaultStaleThresholdDays,
                    range: Self.staleThresholdDaysRange)
        }
        set {
            writeInt(newValue, key: Self.staleThresholdDaysKey,
                     range: Self.staleThresholdDaysRange)
        }
    }

    public var digestEnabled: Bool {
        get {
            guard defaults.object(forKey: Self.digestEnabledKey) != nil else {
                return Self.defaultDigestEnabled
            }
            return defaults.bool(forKey: Self.digestEnabledKey)
        }
        set {
            defaults.set(newValue, forKey: Self.digestEnabledKey)
        }
    }

    public var digestWeekday: Int {
        get {
            readInt(Self.digestWeekdayKey,
                    default: Self.defaultDigestWeekday,
                    range: Self.weekdayRange)
        }
        set {
            writeInt(newValue, key: Self.digestWeekdayKey,
                     range: Self.weekdayRange)
        }
    }

    public var digestHour: Int {
        get {
            readInt(Self.digestHourKey,
                    default: Self.defaultDigestHour,
                    range: Self.hourRange)
        }
        set {
            writeInt(newValue, key: Self.digestHourKey,
                     range: Self.hourRange)
        }
    }

    public var digestMinute: Int {
        get {
            readInt(Self.digestMinuteKey,
                    default: Self.defaultDigestMinute,
                    range: Self.minuteRange)
        }
        set {
            writeInt(newValue, key: Self.digestMinuteKey,
                     range: Self.minuteRange)
        }
    }

    // MARK: - DatePicker convenience

    /// Returns a `Date` whose hour/minute reflect the persisted digest time
    /// (today's date is used as a placeholder; only h/m are surfaced by the
    /// `.hourAndMinute` DatePicker style).
    public func digestTime() -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = digestHour
        components.minute = digestMinute
        return Calendar.current.date(from: components) ?? Date()
    }

    public func setDigestTime(_ date: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        if let h = components.hour { digestHour = h }
        if let m = components.minute { digestMinute = m }
    }

    // MARK: - Private

    private func readInt(
        _ key: String,
        default fallback: Int,
        range: ClosedRange<Int>
    ) -> Int {
        guard defaults.object(forKey: key) != nil else { return fallback }
        let raw = defaults.integer(forKey: key)
        return clamp(raw, to: range)
    }

    private func writeInt(_ value: Int, key: String, range: ClosedRange<Int>) {
        defaults.set(clamp(value, to: range), forKey: key)
    }

    private func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
