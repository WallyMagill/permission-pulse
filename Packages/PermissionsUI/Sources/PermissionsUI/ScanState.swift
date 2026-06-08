/// Pure decision for when a domain section should show a "Scanning…"
/// placeholder instead of its empty state. Mid-scan with nothing yet must not
/// look like a finished empty result. (U1)
enum ScanState {
    /// True only when a scan is running, there is nothing to show yet, there is
    /// no error (the error state owns that surface), and the user is not
    /// searching (a search miss is its own "no matches" state).
    static func showsScanningPlaceholder(
        isScanning: Bool,
        isEmpty: Bool,
        hasError: Bool,
        isSearching: Bool
    ) -> Bool {
        isScanning && isEmpty && !hasError && !isSearching
    }
}
