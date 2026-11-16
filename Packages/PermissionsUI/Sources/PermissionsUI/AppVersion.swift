import Foundation

/// This build's version as the bundle states it.
public struct AppVersion: Sendable, Equatable {
    public let shortVersion: String
    public let build: String

    public init(shortVersion: String, build: String) {
        self.shortVersion = shortVersion
        self.build = build
    }

    public init(infoDictionary: [String: Any]?) {
        self.init(
            shortVersion: infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
            build: infoDictionary?["CFBundleVersion"] as? String ?? "?"
        )
    }

    public static var running: AppVersion {
        AppVersion(infoDictionary: Bundle.main.infoDictionary)
    }

    /// Version plus build, so two builds of one version still differ.
    public var identifier: String { "\(shortVersion) (\(build))" }

    public var displayText: String {
        String(localized: "Version \(shortVersion) (\(build))")
    }
}

/// Where this copy of the app runs from, for display and support text.
public enum AppLocation {
    /// `path` with the home folder shown as `~`.
    public static func displayPath(_ path: String, home: String = NSHomeDirectory()) -> String {
        guard !home.isEmpty, path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }

    /// A quarantined app opened without being moved runs from a random,
    /// read-only `/AppTranslocation/` copy, which breaks launch at login and
    /// relaunching.
    public static func isTranslocated(_ bundlePath: String) -> Bool {
        bundlePath.contains("/AppTranslocation/")
    }
}
