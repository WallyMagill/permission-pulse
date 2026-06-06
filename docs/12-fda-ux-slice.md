# 12 — Third slice: FDA UX closure

**Status:** Implemented v0.3.1 — 2026-05-14.

**Why this slice:**

- v0.3.0 shipped a working TCC scanner but with a known UX gap: when Full Disk Access isn't granted, the Permission Inbox silently renders empty. No in-app indication of why, no path to fix it.
- Users without FDA needed to discover the error via OSLog, which is unreasonable for a permission-hygiene tool.
- All three deliverables (Welcome screen, empty-state CTA, schema-mismatch banner) were explicitly deferred to v0.3.1 in `docs/11-tcc-slice.md`.

## What shipped

1. **Welcome window on first launch.** New users see a 480 × 420 window explaining what Permission Pulse does (reads TCC read-only, never modifies any file, no network requests) with a "Grant Full Disk Access" CTA that deep-links into System Settings → Privacy & Security → Full Disk Access. Dismissing the window (either button) sets the `com.wallymagill.permissionpulse.hasSeenWelcome` UserDefaults key to true. Subsequent launches skip the greeter.

2. **Empty-state CTA in the Permissions section.** When `ScanCoordinator` catches `ScannerError.permissionDenied`, the Permissions section renders an inline CTA with a Grant Access button, body copy explaining why FDA is needed, and a "Why does Permission Pulse need this?" disclosure with the read-only justification. Distinct visual state from "no permissions yet" (true empty).

3. **Schema-mismatch banner.** When the scanner throws `.schemaMismatch` or `.unsupportedOnThisOS`, a banner appears at the top of the detail window with the running macOS version interpolated (via `ProcessInfo.processInfo.operatingSystemVersion`) and a Report link to a labeled GitHub issue.

4. **Menu-bar attention row.** When FDA is denied, the dropdown's "N permissions tracked" line is replaced with a tappable "Full Disk Access needed" row (warning icon, opens System Settings on tap). When the schema is unrecognized, the row reads "TCC schema not recognized" and tapping opens the detail window.

5. **Refresh toolbar button.** The detail window grows a primary-action toolbar Refresh button that re-runs the scan via `ScanCoordinator.rescan()`. Lets users re-test FDA status without relaunching.

## Data flow

```
TCCScannerSQLite.scan() throws ScannerError
        │
        ▼
ScanCoordinator.runScan()
        │   on .success      → viewModel.tccScanError = nil
        │   on ScannerError   → viewModel.tccScanError = error
        │   on other Error    → viewModel.tccScanError = .permissionDenied(reason: localizedDescription)
        ▼
AppViewModel.tccScanError: ScannerError?  (new @Observable property)
        │
        ├─→ MenuBarContentView.permissionsLine — branches on the error case
        ├─→ DetailWindowView — renders SchemaMismatchBanner when applicable
        ├─→ PermissionsEmptyStateView — branches on the error case
        └─→ (Welcome window opens on first launch, not error-driven)
```

One source of truth, three observers. The error case itself encodes the intent.

## Files touched

- New:
  - `Packages/PermissionsUI/Sources/PermissionsUI/SystemSettingsLink.swift`
  - `Packages/PermissionsUI/Sources/PermissionsUI/SchemaMismatchBanner.swift`
  - `Packages/PermissionsUI/Sources/PermissionsUI/PermissionsEmptyStateView.swift`
  - `Packages/PermissionsUI/Sources/PermissionsUI/WelcomeWindowView.swift`
  - `Packages/PermissionsUI/Tests/PermissionsUITests/AppViewModelErrorStateTests.swift`
  - `docs/12-fda-ux-slice.md` (this file)

- Modified:
  - `Packages/PermissionsUI/Sources/PermissionsUI/AppViewModel.swift` (added `tccScanError`)
  - `Packages/PermissionsUI/Sources/PermissionsUI/DetailWindowView.swift` (banner + empty state + Refresh toolbar button)
  - `Packages/PermissionsUI/Sources/PermissionsUI/MenuBarContentView.swift` (attention row)
  - `PermissionPulse/PermissionPulse/PermissionPulseApp.swift` (AppDelegate, Welcome window, Refresh wiring)
  - `PermissionPulse/PermissionPulse/ScanCoordinator.swift` (surfaces errors to ViewModel; adds `rescan()`)
  - `docs/09-roadmap.md` (v0.3.1 marked done)

## Test coverage

- `AppViewModelErrorStateTests`: 4 cases covering the new `tccScanError` property — default nil, settable, init-parameter honored, clearable.
- Existing v0.3.0 test suites all still pass without modification (44 → 48 tests across all packages).
- ScanCoordinator integration coverage is manual smoke (the Xcode app-target test bundle was still a no-op host at v0.3.1; app-target coordinator tests landed in v0.5.0).

## FDA URL

Deep-link verified on macOS Tahoe 26 (Darwin 25.4.0):

```
x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles
```

Lands directly on the Full Disk Access pane. Isolated in `SystemSettingsLink.swift` so future fallback URL changes are a one-file edit.

## UserDefaults keys

- `com.wallymagill.permissionpulse.hasSeenWelcome` (Bool) — false default; set to true when the user dismisses the Welcome window (either button).

## Deferred to later slices

- **Real-time TCC.db watching** (DispatchSource on the file) to auto-detect FDA grants without relaunch — future slice once we know the FS-cost.
- **`didBecomeActiveNotification` auto-rescan** — partially solves the relaunch UX; deferred for the same reason.
- **Snapshot persistence for TCC grants** → v0.5.0.
- **`csreq` / cdHash verification** for Input Monitoring → v0.6.0.
- **Surfacing denied / limited rows** → v0.6.0.

## Done means

- All package tests pass (`swift test` on each).
- App target builds via `xcodebuild`.
- First launch on a clean install (no UserDefaults entry) shows the Welcome window.
- Subsequent launches skip the Welcome.
- Without FDA: the Permissions section shows the Grant Access CTA, and the menu-bar dropdown shows the attention row.
- With FDA: behavior unchanged from v0.3.0.
- Refresh button on the detail window re-runs the scan.
