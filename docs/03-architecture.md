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
│   │   ├── ResetAllDataService.swift   (6-step full data wipe)
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

- Types: `PermissionService` (16-case), `PermissionGrant`, `AppIdentity`, `LaunchAgentItem`, `BTMItem` (with `ItemType` / `Disposition` / `Scope`), `StaleApp`, `MediaUseEvent`, `SnapshotID`, `DigestAuthorizationStatus`.
- Scanner/observer protocols: `TCCScanner`, `LaunchAgentScanner`, `BTMScanner`, `MediaUseObserver`, `LastUsedProbe`, `WeeklyDigestScheduler`.
- Error type: `ScannerError` (`permissionDenied` / `schemaMismatch` / `unsupportedOnThisOS`). (`StoreError` lives in `PermissionsStore`.)
- Zero third-party dependencies. Pure Swift, fully `Sendable`.

### `PermissionsScanners`

- Concrete implementations: `TCCScannerSQLite`, `LaunchAgentScannerFS`, `BTMScannerDirect` (parses `.btm` via `NSKeyedUnarchiver`), `MediaUseObserverCMIO` (CoreMediaIO + CoreAudio), `LastUsedProbeHybrid` (`mdls` → file mtime → skip), `LiveWeeklyDigestScheduler` (`UNUserNotificationCenter`).
- A `Mock…` implementation for every protocol — used by tests and SwiftUI previews. Mock is **never** the shipped runtime default (the app always injects the live scanners); any mock-sourced section is visibly badged "Mock" so it can't be mistaken for real data. When FDA is denied, TCC/BTM surface an error / empty state, not mock data.
- A `sfltool dumpbtm` BTM fallback (`BTMScannerSFL`) is **planned but not implemented** (deferred since v0.4.0; would need a manual sudo step). Only the direct `.btm` reader ships today.
- Depends on `PermissionsCore` + GRDB (GRDB is used by `TCCScannerSQLite` for read-only SQLite). No UI.

### `PermissionsStore`

- GRDB.swift-backed SQLite store at `~/Library/Application Support/com.wallymagill.permissionpulse/snapshots.db`.
- Daily snapshot writes (`writeFullSnapshot`), per-domain diff engine (`TCCGrantsDiff` / `BTMItemsDiff` / `LaunchAgentsDiff` via `DomainChange<T>`), snapshot discovery (`latestSnapshotID(atOrBefore:)`), and retention pruning (`pruneSnapshots(olderThan:)`). Retention is configurable (7–365 days, default 90) — injected from the app, not a fixed constant.
- Three GRDB migrations: v1 `schema_version`, v2 `snapshots` + `launch_agents`, v3 `tcc_grants` + `btm_items` (the `*_kind` TEXT + nullable `*_raw` INTEGER pattern preserves `unknown(rawValue:)` losslessly). Defines `StoreError`.
- Depends on `PermissionsCore` + GRDB. No UI, no scanning.

### `PermissionsUI`

- SwiftUI views: `MenuBarContentView`, `DetailWindowView` (NavigationSplitView with five pages), `PreferencesWindowView`, `WelcomeWindowView`, the per-domain sections (`PermissionsSection` / `LaunchAgentsSection` / `BackgroundItemsSection`), the detail sheets (`AppPermissionsDetailSheet` / `LaunchAgentDetailSheet` / `BackgroundItemDetailSheet` / `FDAGrantSheet` / `ResetConfirmationSheet`), `DiffTabView`, `StaleAppsTabView`, and shared chrome (`SchemaMismatchBanner`, `Mock`/`LiveBadge`, `VibrancyCard`, `TappableRow`).
- `@Observable @MainActor` view models / stores: `AppViewModel` (the central state object — scanner results, media use, diffs, stale apps, `menuBarSymbolName`), `PreferencesViewModel`, `PreferencesStore`, `DismissedDiffEntryStore`, `DismissedStaleAppStore`.
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

- **`ScanCoordinator`** runs the three scanners (`TCCScannerSQLite`, `LaunchAgentScannerFS`, `BTMScannerDirect`) in parallel via `async let`, then applies results to `AppViewModel`. TCC/BTM errors surface on the view model; LaunchAgent errors degrade to an empty list.
- **`SnapshotCoordinator`** writes one snapshot per calendar day (only when TCC + BTM both succeeded), prunes by the configured retention window, then recomputes the yesterday/week diffs and the stale-app list.
- **`MediaUseCoordinator`** runs the mic/cam `AsyncStream` loop and updates `AppViewModel`.
- **`WeeklyDigestCoordinator`** reconciles the `UNUserNotificationCenter` weekly schedule.
- **`ResetAllDataService`** performs the destructive full wipe on demand.

On launch the app kicks off a scan and reconciles the digest; user-initiated refresh re-runs the scan. There is no background timer — the daily-write guard keys off the calendar date at scan time.

## Concurrency

- App target and `PermissionsUI`: MainActor-by-default (Xcode 26 setting). View models, stores, and all coordinators are `@MainActor`.
- `PermissionsScanners`: the four scanners are `nonisolated` `Sendable` structs whose `scan()` runs on the cooperative pool. `MediaUseObserverCMIO` is a `final class` marked `@unchecked Sendable` (it guards mutable state with an `NSLock` because the CoreMediaIO/CoreAudio callbacks arrive on a private dispatch queue). `MockWeeklyDigestScheduler` is an `actor`.
- `PermissionsStore`: GRDB's `DatabaseQueue` is thread-safe; `SnapshotStore` is a `Sendable` struct exposing `async` methods.
- Scan results cross the actor boundary as `Sendable` value arrays (`[PermissionGrant]`, `[LaunchAgentItem]`, `[BTMItem]`); media use as a `MediaUseEvent` `AsyncStream`. There is no spurious `DispatchQueue.main.async` anywhere.

## AppKit drops (flagged)

Each drop carries a `// AppKit: <reason>` comment at the call site. Shipping drops as of v0.7.x:

- **Welcome and Reset-confirmation windows** — hosted in an `NSWindow` (a one-shot dialog launched from another window is awkward to time with a SwiftUI sheet; the `NSWindow` host is deterministic).
- **`TappableRow` cursor + hover** — uses `NSCursor` (pointing hand) for the hover affordance that SwiftUI doesn't expose cleanly on a custom row.

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

- `PermissionsCore`: unit tests, no fixtures. Pure data types. (~15 tests)
- `PermissionsScanners`: golden-fixture tests (`TCCFixtures`, `BTMFixtures`) + `Mock` behavior tests. Real-scanner tests run only on developer machines (FDA-gated). (~48 tests)
- `PermissionsStore`: in-memory + on-disk GRDB tests (migrations, diff engine, retention, discovery). (~24 tests)
- `PermissionsUI`: view-model and store logic tests with injected mocks + in-memory store. (~74 tests)
- App target (`PermissionPulseTests`): coordinator-level tests (`SnapshotCoordinator`, `WeeklyDigestCoordinator`, `ResetAllDataService`) — exercised by `scripts/smoke-test.sh §4` locally, **not run in CI** (see `docs/07-build-and-test.md`). (~27 tests)

## What lives in the App target, not packages

- `Info.plist` (empty `<dict/>`; all keys come from `INFOPLIST_KEY_*` build settings). **No `.entitlements` file** — App Sandbox is off and there are no entitlements (sandbox would block the TCC.db / BTM reads).
- Bundle ID, build settings, signing config (Developer ID deferred), Sparkle config (deferred).
- The `App` struct + `AppDelegate`: the trampoline `WindowGroup`, the `MenuBarExtra`, and the singleton `Window(id:)` scenes.
- The coordinators (`ScanCoordinator`, `SnapshotCoordinator`, `MediaUseCoordinator`, `WeeklyDigestCoordinator`) and `ResetAllDataService`, which wire concrete scanners + store + view models together.
- App icon + assets.

Everything else is in a package.
