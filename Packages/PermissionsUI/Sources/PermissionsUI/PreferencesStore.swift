import Foundation
import Observation

/// `@Observable` store for the six v0.7.0 preference keys.
///
/// Values are held as stored properties (not computed wrappers around
/// `UserDefaults`). The `@Observable` macro can only instrument stored
/// properties — without that, SwiftUI `Binding`s round-trip the value
/// through the setter but never see a tracked mutation, and the view
/// doesn't re-render. Stored property + `didSet` writeback is the
/// only shape that works for Slider/Toggle/DatePicker bindings.
///
/// Defaults preserve v0.6.0 `SnapshotCoordinator` behavior. Writes clamp
/// to safe ranges so a corrupted blob cannot push the rest of the app
/// off a cliff; the clamp re-enters `didSet` exactly once.
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

    public var snapshotRetentionDays: Int {
        didSet {
            let clamped = Self.clamp(snapshotRetentionDays, to: Self.snapshotRetentionDaysRange)
            if clamped != snapshotRetentionDays {
                snapshotRetentionDays = clamped // re-enters didSet once, then stops
                return
            }
            defaults.set(clamped, forKey: Self.snapshotRetentionDaysKey)
        }
    }

    public var staleThresholdDays: Int {
        didSet {
            let clamped = Self.clamp(staleThresholdDays, to: Self.staleThresholdDaysRange)
            if clamped != staleThresholdDays {
                staleThresholdDays = clamped
                return
            }
            defaults.set(clamped, forKey: Self.staleThresholdDaysKey)
        }
    }

    public var digestEnabled: Bool {
        didSet {
            defaults.set(digestEnabled, forKey: Self.digestEnabledKey)
        }
    }

    public var digestWeekday: Int {
        didSet {
            let clamped = Self.clamp(digestWeekday, to: Self.weekdayRange)
            if clamped != digestWeekday {
                digestWeekday = clamped
                return
            }
            defaults.set(clamped, forKey: Self.digestWeekdayKey)
        }
    }

    public var digestHour: Int {
        didSet {
            let clamped = Self.clamp(digestHour, to: Self.hourRange)
            if clamped != digestHour {
                digestHour = clamped
                return
            }
            defaults.set(clamped, forKey: Self.digestHourKey)
        }
    }

    public var digestMinute: Int {
        didSet {
            let clamped = Self.clamp(digestMinute, to: Self.minuteRange)
            if clamped != digestMinute {
                digestMinute = clamped
                return
            }
            defaults.set(clamped, forKey: Self.digestMinuteKey)
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.snapshotRetentionDays = Self.readClampedInt(
            defaults: defaults,
            key: Self.snapshotRetentionDaysKey,
            fallback: Self.defaultSnapshotRetentionDays,
            range: Self.snapshotRetentionDaysRange
        )
        self.staleThresholdDays = Self.readClampedInt(
            defaults: defaults,
            key: Self.staleThresholdDaysKey,
            fallback: Self.defaultStaleThresholdDays,
            range: Self.staleThresholdDaysRange
        )
        if defaults.object(forKey: Self.digestEnabledKey) != nil {
            self.digestEnabled = defaults.bool(forKey: Self.digestEnabledKey)
        } else {
            self.digestEnabled = Self.defaultDigestEnabled
        }
        self.digestWeekday = Self.readClampedInt(
            defaults: defaults,
            key: Self.digestWeekdayKey,
            fallback: Self.defaultDigestWeekday,
            range: Self.weekdayRange
        )
        self.digestHour = Self.readClampedInt(
            defaults: defaults,
            key: Self.digestHourKey,
            fallback: Self.defaultDigestHour,
            range: Self.hourRange
        )
        self.digestMinute = Self.readClampedInt(
            defaults: defaults,
            key: Self.digestMinuteKey,
            fallback: Self.defaultDigestMinute,
            range: Self.minuteRange
        )
    }

    public func resetToDefaults() {
        snapshotRetentionDays = Self.defaultSnapshotRetentionDays
        staleThresholdDays = Self.defaultStaleThresholdDays
        digestEnabled = Self.defaultDigestEnabled
        digestWeekday = Self.defaultDigestWeekday
        digestHour = Self.defaultDigestHour
        digestMinute = Self.defaultDigestMinute
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

    private static func readClampedInt(
        defaults: UserDefaults,
        key: String,
        fallback: Int,
        range: ClosedRange<Int>
    ) -> Int {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return clamp(defaults.integer(forKey: key), to: range)
    }

    private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
