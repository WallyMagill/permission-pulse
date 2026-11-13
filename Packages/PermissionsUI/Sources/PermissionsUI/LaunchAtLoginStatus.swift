/// Mirror of `SMAppService.Status`, so the view model needs no
/// ServiceManagement import and tests can supply any state.
public enum LaunchAtLoginStatus: Sendable, Equatable {
    case enabled
    /// Registered, but the user must allow it in System Settings → Login Items.
    case requiresApproval
    case notRegistered
    /// macOS could not find the app as a login item.
    case notFound
}
