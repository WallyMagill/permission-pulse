# 03 — Architecture

Permission Pulse is a thin SwiftUI app wrapping four local SwiftPM packages.

## Layout

```
permission-pulse/                       (repo root)
├── PermissionPulse/                    (Xcode project folder)
│   ├── PermissionPulse.xcodeproj/      (with shared scheme)
│   ├── PermissionPulse/                (app target sources)
│   │   ├── PermissionPulseApp.swift    (the @main App + AppDelegate, owns all coordinators)
│   │   ├── ScanCoordinator.swift       (runs the three scanners in parallel → viewModel)
│   │   ├── SnapshotCoordinator.swift   (daily snapshot write, diff refresh, stale apps)
│   │   ├── MediaUseCoordinator.swift   (mic/cam observation loop → viewModel)
│   │   ├── WeeklyDigestCoordinator.swift (digest schedule lifecycle + compose)
│   │   ├── ResetAllDataService.swift   (ordered, result-bearing reset lifecycle)
│   │   ├── SnapshotPath.swift          (Application Support path resolution)
│   │   ├── Assets.xcassets/
│   │   └── Info.plist                  (empty <dict/>; all keys live in INFOPLIST_KEY_* build settings)
│   ├── PermissionPulseTests/           (Swift Testing — SnapshotCoordinator/WeeklyDigest/ResetAllData suites)
│   └── PermissionPulseUITests/         (XCTest launch scaffolding)
└── Packages/
    ├── PermissionsCore/                (types, protocols, errors — zero deps)
    ├── PermissionsScanners/            (TCC, LaunchAgents, BTM, Mic/Cam, last-used, digest + Mocks; deps: Core, GRDB)
    ├── PermissionsStore/               (GRDB-backed snapshot store + diff engine; deps: Core, GRDB)
    └── PermissionsUI/                  (shared SwiftUI views + @Observable view models; deps: Core, Store)
```

The app target uses Xcode 26's `PBXFileSystemSynchronizedRootGroup`, so any `.swift` file dropped into `PermissionPulse/PermissionPulse/` is automatically included in the build — no pbxproj edits needed to add or remove source files.

## Package responsibilities

### `PermissionsCore`

- Types: `PermissionService` (16-case), `PermissionGrant`, `AppIdentity`, `LaunchAgentItem`, `BTMItem` (with `ItemType` / `Disposition` / `Scope`), `StaleApp`, `MediaUseEvent`, `SnapshotID`, `DigestAuthorizationStatus`, plus `ScannerOutput<Item>`, `ScannerWarning`, and `ScannerSource` for coverage truth.
- Scanner/observer protocols: `TCCScanner`, `LaunchAgentScanner`, and `BTMScanner` return typed `ScannerOutput` values; `MediaUseObserver`, `LastUsedProbe`, and `WeeklyDigestScheduler` provide the other runtime boundaries.
- Error type: `ScannerError` (`permissionDenied` / `schemaMismatch` / `unsupportedOnThisOS` / `temporarilyUnavailable`). (`StoreError` lives in `PermissionsStore`.)
- `AppIdentity.stableKey` has exactly two eligible forms: `bundle:<bundle-id>` when a bundle ID exists, otherwise `path:<standardized-file-path>` when a path exists. An identity with neither is visible where possible but is excluded from stale tracking. Legacy unprefixed stale dismissals load as bundle keys and migrate on the next persistence operation.
- Zero third-party dependencies. Pure Swift, fully `Sendable`.

### `PermissionsScanners`

- Concrete implementations: `TCCScannerSQLite`, `LaunchAgentScannerFS`, `BTMScannerDirect` (parses `.btm` via `NSKeyedUnarchiver`), `MediaUseObserverCMIO` (CoreMediaIO + CoreAudio), `LastUsedProbeHybrid` (`mdls` → file mtime → skip), `LiveWeeklyDigestScheduler` (`UNUserNotificationCenter`). TCC bundle-ID rows resolve one installed application URL and retain it for stale probing; path-only rows retain standardized URLs and independent stable keys.
- Successful scanners return `ScannerOutput(items:warnings:)`. No warnings means complete coverage; warnings identify an omitted user/system TCC source, LaunchAgent directory, or materially unreadable entries without exposing private paths. If no relevant source can be read, the scanner throws instead of manufacturing a partial success.
- A `Mock…` implementation for every protocol — used by tests and SwiftUI previews. Mocks can deterministically emit complete, degraded, or failed results and are **never** the shipped runtime default (the app always injects live scanners); any mock-sourced section is visibly badged "Mock" so it cannot be mistaken for real data. When FDA is denied, TCC/BTM surface truthful failed or last-known state, not mock data.
- A `sfltool dumpbtm` BTM fallback (`BTMScannerSFL`) is **planned but not implemented** (deferred since v0.4.0; would need a manual sudo step). Only the direct `.btm` reader ships today.
- Depends on `PermissionsCore` + GRDB (GRDB is used by `TCCScannerSQLite` for read-only SQLite). No UI.

### `PermissionsStore`

- GRDB.swift-backed SQLite store at `~/Library/Application Support/com.wallymagill.permissionpulse/snapshots.db`.
- Daily snapshot writes (`writeFullSnapshot`), per-domain diff engine (`TCCGrantsDiff` / `BTMItemsDiff` / `LaunchAgentsDiff` via `DomainChange<T>`), snapshot discovery (`latestSnapshotID(atOrBefore:)`), and retention pruning (`pruneSnapshots(olderThan:)`). Retention is configurable (7–365 days, default 90) — injected from the app, not a fixed constant.
- Five GRDB migrations: v1 `schema_version`, v2 `snapshots` + `launch_agents`, v3 `tcc_grants` + `btm_items`, v4 persisted TCC `auth_value`, and v5 LaunchAgent `is_disabled` plus `snapshots.launch_agent_disabled_captured`. Existing v4 rows migrate transactionally with the capture marker false; new snapshots set it true. Disabled state participates in a LaunchAgent diff only when both snapshots carry the marker, preventing a false upgrade transition while preserving real v5-to-v5 changes. The `*_kind` TEXT + nullable `*_raw` INTEGER pattern preserves unknown BTM enum values losslessly. Defines `StoreError`.
- Depends on `PermissionsCore` + GRDB. No UI, no scanning.

### `PermissionsUI`

- SwiftUI views: `MenuBarContentView`, `DetailWindowView` (NavigationSplitView with six pages, `OverviewPage` first), `PreferencesWindowView` (native Settings-style tabs), `WelcomeWindowView`, the non-modal inspectors (`AppPermissionsInspector` / `LaunchAgentInspector` / `BackgroundItemInspector` on the shared `InspectorPanel`), `DiffTabView`, `StaleAppsTabView`, and shared chrome (`SchemaMismatchBanner`, `MockBadge`, `ExportToolbar`, `DispositionBadge`, `PermissionsEmptyStateView`). The pre-Thread-C detail sheets and section/row components (`*DetailSheet`, `PermissionsSection`, `TappableRow`, `VibrancyCard`) were retired in the native redesign.
- `@Observable @MainActor` view models / stores: `AppViewModel` (the central state object — scanner results, per-domain `ScanAvailability`, media use, diffs, stale apps, `menuBarSymbolName`), `PreferencesViewModel`, `PreferencesStore`, `DismissedDiffEntryStore`, `DismissedStaleAppStore`.
- `ScanAvailability` is the single coverage truth: `.complete(lastUpdated:)`, `.degraded(lastUpdated:warnings:)`, or `.failed(lastSuccessful:error:)` after scanning, with `.never` before the first result. Shared banners, Overview/menu-bar attention, and VoiceOver copy consume the same state. Failed scans retain last-known rows; a failure without history is explicitly announced as having no successful data.
- `ChangeRow.Kind.permissionChanged` renders TCC before/after authorization labels with a transition-specific dismissal key. Recent Changes builds all TCC, BTM, and LaunchAgent row kinds first, then searches localized summaries plus their relevant app/service/label/path/developer/identifier fields. Search is section-aware: Overview has no search affordance; the five detail sections do.
- Depends on `PermissionsCore` + `PermissionsStore` (it consumes `SnapshotDiffs`). It does **not** depend on `PermissionsScanners` — concrete scanners are injected from the app target via the coordinators.

## Data flow

```
[ Scanners ] ──► ScanCoordinator ──► AppViewModel (@Observable) ──► SwiftUI views
                       │
                       ▼
              SnapshotCoordinator ──► PermissionsStore ──► daily snapshot rows
                       │                                         │
                       │                                    diff queries +
                       │                                    retention prune
                       ▼                                         │
              latestDiffYesterday / latestDiffWeek / staleApps ◄─┘  → AppViewModel → views
```

Coordination lives in the App target (not a package) and is split across focused `@MainActor` objects, all owned by `AppDelegate`:

- **`ScanCoordinator`** runs the three scanners (`TCCScannerSQLite`, `LaunchAgentScannerFS`, `BTMScannerDirect`) in parallel via `async let`, captures one evidence timestamp, and maps every domain to `.complete`, `.degraded`, or `.failed`. Complete and degraded outputs replace that domain's live rows; failure preserves prior rows and carries forward the last-successful timestamp. Unexpected errors become temporary unavailability, not permission denial.
- **`SnapshotCoordinator`** writes one snapshot per calendar day only when TCC, LaunchAgent, and BTM availability are all complete. Any degraded or failed domain suppresses the whole snapshot, preventing partial evidence from appearing as mass removals. On a complete boundary it prunes by the configured retention window, then recomputes yesterday/week diffs and stale apps. It reads retention and stale thresholds from the live preference store exactly once at the start of each scan-completion boundary. An edit therefore affects the next scan without recreating the coordinator, while both values remain stable inside a scan already in progress; the captured stale threshold is also published to the view model so UI copy matches the computation.
- **`MediaUseCoordinator`** runs the mic/cam `AsyncStream` loop and updates `AppViewModel`.
- **`WeeklyDigestCoordinator`** reconciles the `UNUserNotificationCenter` weekly schedule. Enabled day/time edits persist first, debounce superseded picker events, then enter a coordinator-local FIFO that serializes cancel/schedule/read mutations. A successful reconcile leaves one replacement request and publishes its actual next-fire date. Failures retain the selected values and reach Preferences as an orange Retry state. Digest copy counts TCC authorization transitions alongside BTM and launch-agent changes.
- **`ResetAllDataService`** performs the destructive full wipe on demand as an ordered, idempotent state machine: cancel owned weekly/test notifications; release the open history runtime; remove `snapshots.db`, `snapshots.db-wal`, and `snapshots.db-shm`; reset the live preference and dismissal stores; clear only Permission Pulse-prefixed defaults; recreate and migrate the history store; clear presentation state; run a fresh scan; and reconcile against the reset default `digestEnabled == false`. Missing history files are success. Other failures report the exact `.deleteHistory`, `.clearDefaults`, or `.recreateHistory` phase and stop at the appropriate dependency boundary, so a stale in-memory digest preference cannot recreate a schedule. A completed storage reset whose recovery scan fails is a distinct completed-reset outcome and produces a separate Refresh warning.

On launch the app kicks off a scan and reconciles the digest; user-initiated refresh re-runs the scan. There is no background timer — the daily-write guard keys off the calendar date at scan time.

## Concurrency

- App target and `PermissionsUI`: MainActor-by-default (Xcode 26 setting). View models, stores, and all coordinators are `@MainActor`.
- `AppDelegate` reserves scan/reset lifecycle ownership synchronously: it rejects reset while a scan is active, rejects rescan while reset is reserved or active, ignores overlapping reset requests, and prevents duplicate scans. Reset's own recovery scan uses the same guarded scan primitive without opening an external overlap window.
- `WeeklyDigestCoordinator` serializes all weekly schedule mutations in one FIFO. Canceled owners retain the mutation boundary until any late scheduler effect is cleaned up; next-fire reads wait for active mutations, so an older reconcile cannot remove a newer request or publish its date.
- `PermissionsScanners`: the four scanners are `nonisolated` `Sendable` structs whose `scan()` runs on the cooperative pool. `MediaUseObserverCMIO` is a `final class` marked `@unchecked Sendable` (it guards mutable state with an `NSLock` because the CoreMediaIO/CoreAudio callbacks arrive on a private dispatch queue). `MockWeeklyDigestScheduler` is an `actor`.
- `PermissionsStore`: GRDB's `DatabaseQueue` is thread-safe; `SnapshotStore` is a `Sendable` struct exposing `async` methods.
- Scan results cross the actor boundary as `Sendable` `ScannerOutput` values containing item arrays plus coverage warnings; media use crosses as a `MediaUseEvent` `AsyncStream`. There is no spurious `DispatchQueue.main.async` anywhere.

## AppKit drops (flagged)

Each drop carries a `// AppKit: <reason>` comment at the call site. Shipping drops as of v0.7.x:

- **Welcome window** — hosted in an `NSWindow` (a one-shot dialog launched from another window is awkward to time with a SwiftUI sheet; the `NSWindow` host is deterministic). Reset confirmation is now a SwiftUI `.alert` in Preferences.
- **`NSSavePanel` + `NSAlert`** — export destination picker and one-shot error dialogs (`ExportToolbar`, `PermissionPulseApp`).
- **`NSWorkspace`** — reveal-in-Finder (read-only) from the stale-apps list and the app-permissions inspector; `AppRelauncher` restarts the running bundle after Reset All Data.
- **`NSApp.activate`** — fronting the Preferences window from the detail toolbar.

Candidates we still anticipate may force AppKit:

- **Menu-bar right-click menu** — `MenuBarExtra` does not natively support right-click context menus. If we need one we drop to `NSStatusItem` + `NSMenu`.

## Tahoe-specific workarounds

### Hidden-WindowGroup Settings trampoline

`openSettings` is broken inside `MenuBarExtra` on Tahoe. The app declares a hidden zero-size `WindowGroup(id: "settings-trampoline")` *first* in `App.body` (before `MenuBarExtra` and the singleton `Window(id:)` scenes — there is no `Settings` scene). Menu items open windows through `@Environment(\.openWindow)`; the detail and Preferences windows are singleton `Window(id:)` scenes so `openWindow(id:)` reuses the existing window rather than spawning duplicates.

Reference: https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items.

**Every entry point that wants Settings goes through this trampoline. Do not call `openSettings` directly from `MenuBarExtra`.**

### Menu-bar icon design

Tahoe's transparent menu bar means our icon must render cleanly on both light and dark backgrounds. Use an SF Symbol with no fill where possible. Avoid bitmap icons unless they're designed as template images.

## Test strategy by layer

All package tests use **Swift Testing**; the UITest target uses XCTest.

- `PermissionsCore`: unit tests, no fixtures. Pure data types. (40 tests)
- `PermissionsScanners`: golden-fixture tests (`TCCFixtures`, `BTMFixtures`) + `Mock` behavior tests. Real-scanner tests run only on developer machines (FDA-gated). (65 tests)
- `PermissionsStore`: in-memory + on-disk GRDB tests (migrations, diff engine, retention, discovery). (39 tests)
- `PermissionsUI`: view-model and store logic tests with injected mocks + in-memory store. (136 tests)
- App target (`PermissionPulseTests`): coordinator-level tests (`SnapshotCoordinator`, `WeeklyDigestCoordinator`, `ResetAllDataService`) — exercised by `scripts/smoke-test.sh §4` locally and by pinned CI under `PERMISSION_PULSE_TEST_MODE=1`. (74 tests)

The four package suites total 280 tests; with the 74 app-target tests, the automated total is 354. These counts were observed fresh at the v0.7.2 Workstream C Task 7 gate on macOS 26.5 with Xcode 26.5 / Swift 6.3.2; see `docs/07-build-and-test.md`.

## What lives in the App target, not packages

- `Info.plist` (empty `<dict/>`; all keys come from `INFOPLIST_KEY_*` build settings). **No `.entitlements` file** — App Sandbox is off and there are no entitlements (sandbox would block the TCC.db / BTM reads).
- Bundle ID, build settings, signing config (Developer ID deferred), Sparkle config (deferred).
- The `App` struct + `AppDelegate`: the trampoline `WindowGroup`, the `MenuBarExtra`, and the singleton `Window(id:)` scenes.
- The coordinators (`ScanCoordinator`, `SnapshotCoordinator`, `MediaUseCoordinator`, `WeeklyDigestCoordinator`) and `ResetAllDataService`, which wire concrete scanners + store + view models together.
- App icon + assets.

Everything else is in a package.
