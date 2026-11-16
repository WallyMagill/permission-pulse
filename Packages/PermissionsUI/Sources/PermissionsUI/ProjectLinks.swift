import Foundation

/// Where the project lives; the app never contacts these itself, it only
/// opens them in the browser.
public enum ProjectLinks {
    public static let releases = URL(string: "https://github.com/WallyMagill/permission-pulse/releases")!
    public static let repository = URL(string: "https://github.com/WallyMagill/permission-pulse")!
}
