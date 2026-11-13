# 03 — Architecture

Permission Pulse is a thin SwiftUI app wrapping four local SwiftPM packages.

## Layout

```
permission-pulse/                       (repo root)
├── PermissionPulse/                    (Xcode project folder)
│   ├── PermissionPulse.xcodeproj/      (with shared scheme)
│   ├── PermissionPulse/                (app target sources)
│   │   ├── PermissionPulseApp.swift    (the @main App + AppDelegate, owns all coordinators and the one scan path)
│   │   ├── AppDelegate+Windows.swift   (AppKit-hosted Welcome and Full Disk Access windows)
│   │   ├── AppDelegate+FullDiskAccess.swift (classify a Full Disk Access loss, open the recovery window once per version)
│   │   ├── AppDelegate+Diagnostics.swift (text for Preferences → Data → Copy Diagnostics)
│   │   ├── SingleInstanceGuard.swift   (one running copy: hand off to an existing one, or wait for a relaunched-from one)
│   │   ├── ScanCoordinator.swift       (runs the three scanners in parallel → viewModel)
│   │   ├── SnapshotCoordinator.swift   (change-driven snapshot write, per-domain baselines, diff refresh, stale apps)
│   │   ├── ScanScheduler.swift         (wake / day-change / stale-open scan triggers)
│   │   ├── MediaUseCoordinator.swift   (mic/cam observation loop → viewModel)
│   │   ├── WeeklyDigestCoordinator.swift (digest compose + re-arm of its next occurrence)
│   │   ├── ChangeAlertCoordinator.swift (opt-in change alert after a snapshot write; Full Disk Access-off alert)
│   │   ├── NotificationAuthorization.swift (the one notification permission request both toggles share)
│   │   ├── ResetAllDataService.swift   (ordered, result-bearing reset lifecycle)
│   │   ├── SnapshotPath.swift          (Application Support path resolution)
│   │   ├── Assets.xcassets/
│   │   └── Info.plist                  (empty <dict/>; all keys live in INFOPLIST_KEY_* build settings)
│   ├── PermissionPulseTests/           (Swift Testing — coordinator, scan-completion, history, Full Disk Access, single-instance, and reset suites)
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

- Types: `PermissionService` (18 cases; `systemLevel` names the seven whose grants live in the system TCC database), `PermissionGrant`, `AppIdentity`, `LaunchAgentItem` (with `detailsReadable` and `fileName`), `BTMItem` (with `ItemType` / `Disposition` / `Scope`; `identityKey` is scope + identifier), `StaleApp`, `MediaUseEvent`, `SnapshotID`, `DigestAuthorizationStatus`, plus `ScannerOutput<Item>`, `ScannerWarning`, and `ScannerSource` for coverage truth.
- `BTMItem.ItemType` maps the store's raw `type` values to named cases (app, login item, app agent, developer group, Spotlight / Dock tile / QuickLook extensions, background tasks, legacy agent, legacy daemon) and keeps anything else as `unknown(rawValue:)`.
- `PermissionsExport` + `ExportCoverage` build the JSON/Markdown export, including export `schemaVersion` 2, app and macOS versions, and per-domain coverage.
- Scanner/observer protocols: `TCCScanner`, `LaunchAgentScanner`, and `BTMScanner` return typed `ScannerOutput` values; `MediaUseObserver`, `LastUsedProbe`, and `WeeklyDigestScheduler` provide the other runtime boundaries.
- Error type: `ScannerError` (`permissionDenied` / `schemaMismatch` / `unsupportedOnThisOS` / `temporarilyUnavailable`). (`StoreError` lives in `PermissionsStore`.)
- `AppIdentity.stableKey` has exactly two eligible forms: `bundle:<bundle-id>` when a bundle ID exists, otherwise `path:<standardized-file-path>` when a path exists. An identity with neither is visible where possible but is excluded from stale tracking. Legacy unprefixed stale dismissals load as bundle keys and migrate on the next persistence operation.
- Zero third-party dependencies. Pure Swift, fully `Sendable`.

### `PermissionsScanners`

- Concrete implementations: `TCCScannerSQLite`, `LaunchAgentScannerFS` (reads launchd's disabled-override files through `LaunchdDisabledOverrides`), `BTMScannerDirect` (parses `.btm` via `NSKeyedUnarchiver`), `MediaUseObserverCMIO` (CoreMediaIO + CoreAudio; `MediaDeviceTracker` over the `MediaDeviceSource` implementations in `MediaDeviceSources.swift` adds and drops device listeners as devices come and go), `LastUsedProbeHybrid` (`.app` bundles only: `mdls` → file mtime → skip), `LiveWeeklyDigestScheduler` (`UNUserNotificationCenter`; non-repeating weekly trigger plus one-shot notifications). TCC bundle-ID rows resolve one installed application URL and retain it for stale probing; path-only rows retain standardized URLs and independent stable keys.
- Successful scanners return `ScannerOutput(items:warnings:)`. No warnings means complete coverage; warnings identify an omitted user/system TCC source, LaunchAgent directory, or omitted entries (with their file names) without exposing private paths. A launchd plist that is permission-denied or unparseable is an item with `detailsReadable = false`, not a warning. If no relevant source can be read, the scanner throws instead of manufacturing a partial success.
- A `Mock…` implementation for every protocol — used by tests and SwiftUI previews. Mocks can deterministically emit complete, degraded, or failed results and are **never** the shipped runtime default (the app always injects live scanners); any mock-sourced section is visibly badged "Mock" so it cannot be mistaken for real data. When FDA is denied, TCC/BTM surface truthful failed or last-known state, not mock data.
- A `sfltool dumpbtm` BTM fallback (`BTMScannerSFL`) is **planned but not implemented** (deferred since v0.4.0; would need a manual sudo step). Only the direct `.btm` reader ships today.
- Depends on `PermissionsCore` + GRDB (GRDB is used by `TCCScannerSQLite` for read-only SQLite). No UI.

### `PermissionsStore`

- GRDB.swift-backed SQLite store at `~/Library/Application Support/com.wallymagill.permissionpulse/snapshots.db`.
- Change-driven snapshot writes (`writeSnapshot`), per-domain diff engine (`TCCGrantsDiff` / `BTMItemsDiff` / `LaunchAgentsDiff` via `DomainChange<T>`), snapshot summaries (`snapshotSummaries(atOrBefore:)`, `snapshotSummary(id:)`), and retention pruning (`pruneSnapshots(olderThan:keeping:)`). Retention is configurable (7–365 days, default 90) — injected from the app, not a fixed constant.
- Diffs compare only what the UI shows: a grant's `authValue`, a background item's disposition and type, and a launch agent's program, arguments, run-at-load, keep-alive, readability, and (when both snapshots captured it) disabled state.
- `BaselineSelector` (in `SnapshotBaseline.swift`) picks each domain's baseline: the newest candidate whose coverage can be compared with the latest snapshot's. A complete baseline can narrow to the system-level services for a reduced latest snapshot. With no usable baseline it returns an `UncomparedReason` (`scopeChanged`, `latestScanFailed`, `itemsUnreadable`, `noEarlierSnapshot`). Pruning (`SnapshotStore+History.swift`) keeps, per domain and scope, the newest snapshot any future latest could use as a baseline, plus the caller's protected snapshots.
- Seven GRDB migrations: v1 `schema_version`, v2 `snapshots` + `launch_agents`, v3 `tcc_grants` + `btm_items`, v4 persisted TCC `auth_value`, v5 LaunchAgent `is_disabled` plus `snapshots.launch_agent_disabled_captured`, v6 per-domain `tcc_coverage` / `btm_coverage` / `launch_agent_coverage` on `snapshots`, and v7 `launch_agents.details_readable` (default 1) plus nullable `launch_agents.file_name`. Existing v4 rows migrate transactionally with the capture marker false; new snapshots set it true. Disabled state participates in a LaunchAgent diff only when both snapshots carry the marker, preventing a false upgrade transition while preserving real v5-to-v5 changes. `file_name` is not part of LaunchAgent equivalence, so pre-v7 rows (NULL) do not read as changed. The `*_kind` TEXT + nullable `*_raw` INTEGER pattern preserves unknown BTM enum values losslessly. Defines `StoreError` and `SnapshotStoreOpenError` (`createdByNewerVersion` when the file records migrations this build does not know, `corrupt` for `SQLITE_CORRUPT` / `SQLITE_NOTADB`). Writes wait up to 5 s on a lock held by another process.
- Depends on `PermissionsCore` + GRDB. No UI, no scanning.

### `PermissionsUI`

- SwiftUI views: `MenuBarContentView`, `DetailWindowView` (NavigationSplitView with six pages, `OverviewPage` first; `PermissionsDetailPage`, `RecentChangesDetailPage`, and `StaleAppsDetailPage` live in their own files), `PreferencesWindowView` (native Settings-style tabs: General with About, Scanning, Notifications, Data), `WelcomeWindowView`, `FullDiskAccessPromptView` (the recovery window), `WindowOpeningTrampoline` (content of the hidden trampoline window; opens the scene named in `AppViewModel.windowToOpen`), the non-modal inspectors (`AppPermissionsInspector` / `LaunchAgentInspector` / `BackgroundItemInspector` on the shared `InspectorPanel`), `DiffTabView`, `StaleAppsTabView`, and shared chrome (`SchemaMismatchBanner`, `MockBadge`, `ExportToolbar`, `DispositionBadge`, `PermissionsEmptyStateView`). The pre-Thread-C detail sheets and section/row components (`*DetailSheet`, `PermissionsSection`, `TappableRow`, `VibrancyCard`) were retired in the native redesign.
- `@Observable @MainActor` view models / stores: `AppViewModel` (the central state object — scanner results, per-domain `ScanAvailability`, media use, diffs, stale apps, `menuBarSymbolName`), `PreferencesViewModel`, `PreferencesStore`, `DismissedDiffEntryStore`, `DismissedStaleAppStore`, `FullDiskAccessRecovery` (the wait / check / restored / still-denied loop shared by the Welcome and recovery windows).
- History presentation: `DiffEntry` flattens a `SnapshotDiffs` into rows; `DismissedDiffEntryStore.visibleEntries` drops dismissed and snoozed ones, and that one list feeds Recent Changes, the sidebar badge, the dropdown and Overview counts, change alerts (`ChangeAlert`), and the digest. `HistoryDomain` names the three domains, `RecentChangesWindow` the two windows (`sinceLastReview`, `lastSevenDays`), and `RecentChangesStatus` the per-domain baseline and not-compared lines.
- Scope and status helpers: `PermissionScope` (whether the permissions scan is reduced and which services macOS hides, used by search, empty states, Overview, and Stale Apps), `FullDiskAccessLoss` (first run / lost after an update / revoked), `AppPresence` ("App not found on this Mac"), `AppVersion` + `AppLocation` (version text, `~` paths, App Translocation detection), `DiagnosticsReport`, and `ProjectLinks` (Releases and repository URLs, opened in the browser only).
- `ScanAvailability` is the single coverage truth: `.complete(lastUpdated:)`, `.degraded(lastUpdated:warnings:)`, or `.failed(lastSuccessful:error:)` after scanning, with `.never` before the first result. Shared banners, Overview/menu-bar attention, and VoiceOver copy consume the same state. Failed scans retain last-known rows; a failure without history is explicitly announced as having no successful data.
- `ChangeRow.Kind.permissionChanged` renders TCC before/after authorization labels with a transition-specific dismissal key. Recent Changes builds all TCC, BTM, and LaunchAgent row kinds first, then searches localized summaries plus their relevant app/service/label/path/developer/identifier fields. Search is section-aware: Overview has no search affordance; the five detail sections do.
- Depends on `PermissionsCore` + `PermissionsStore` (it consumes `SnapshotDiffs`). It does **not** depend on `PermissionsScanners` — concrete scanners are injected from the app target via the coordinators.

## Data flow

```
[ Scanners ] ──► ScanCoordinator ──► AppViewModel (@Observable) ──► SwiftUI views
                       │
                       ▼
              SnapshotCoordinator ──► PermissionsStore ──► change-driven snapshot rows
                       │                                         │
                       │                                    diff queries +
                       │                                    retention prune
                       ▼                                         │
              latestDiffSinceReview / latestDiffWeek / staleApps ◄─┘  → AppViewModel → views
```

Coordination lives in the App target (not a package) and is split across focused `@MainActor` objects, all owned by `AppDelegate`:

- **`ScanCoordinator`** runs the three scanners (`TCCScannerSQLite`, `LaunchAgentScannerFS`, `BTMScannerDirect`) in parallel via `async let`, captures one evidence timestamp, and maps every domain to `.complete`, `.degraded`, or `.failed`. Complete and degraded outputs replace that domain's live rows; failure preserves prior rows and carries forward the last-successful timestamp. Unexpected errors become temporary unavailability, not permission denial.
- **`SnapshotCoordinator`** writes a snapshot after any scan whose evidence differs from the latest stored snapshot (or when none exists), using the store's own diff rules (`SnapshotStore.evidenceChanged`). Each snapshot records per-domain coverage (`complete` / `reduced` / `degraded` / `failed`, a v6 column); `reduced` means the TCC scan was complete except for the per-user database macOS 27 hides. A failed domain stores no rows, and a scan where every domain failed writes nothing. The first snapshot ever (and the first after Reset All Data) is recorded as the last-reviewed one. It computes two windows: **since last review** (candidates at or before the last-reviewed snapshot; start of today when none is recorded) and **last 7 days** (candidates at or before the start of the day seven days ago). Each domain gets its own baseline from `BaselineSelector`; a domain without one is listed in `SnapshotDiffs.uncompared` with its reason, so partial evidence never appears as removals, and a complete macOS 26 baseline against a reduced macOS 27 latest diffs only `PermissionService.systemLevel` (`systemLevelPermissionsOnly`). After a write it prunes by the retention window, keeping every baseline in use and the last-reviewed snapshot. Stale apps are recomputed after every scan once any snapshot exists, from the grants the view model holds at that point (on a failed TCC scan, the last-known grants). `markCurrentSnapshotReviewed()` runs when the user leaves Recent Changes or the detail window closes on it, or chooses Mark All Reviewed. `onSnapshotWritten` reports the (previous, new) snapshot IDs for change alerts. It reads retention and stale thresholds from the live preference store exactly once at the start of each scan-completion boundary. An edit therefore affects the next scan without recreating the coordinator, while both values remain stable inside a scan already in progress; the captured stale threshold is also published to the view model so UI copy matches the computation.
- **`MediaUseCoordinator`** runs the mic/cam `AsyncStream` loop and updates `AppViewModel`.
- **`WeeklyDigestCoordinator`** reconciles the `UNUserNotificationCenter` weekly schedule after every scan and on every Preferences change. It composes the body from the visible "last 7 days" changes and schedules only the next occurrence (a non-repeating calendar trigger), so a stale body is never repeated. Enabled day/time edits persist first, debounce superseded picker events, then enter a coordinator-local FIFO that serializes cancel/schedule/read mutations. A successful reconcile leaves one replacement request and publishes its actual next-fire date. Failures retain the selected values and reach Preferences as an orange Retry state. Digest copy counts TCC authorization transitions alongside BTM and launch-agent changes.
- **`ChangeAlertCoordinator`** posts the opt-in change alert (`changeAlertsEnabled`) when a scan wrote a snapshot: one one-shot notification under a fixed identifier (`com.wallymagill.permissionpulse.changes.latest`, so a newer alert replaces an older one) naming the visible changes from the previous snapshot to the new one. Domains the previous snapshot did not capture comparably contribute nothing, so the first snapshot and the post-reset scan stay silent. With alerts on it also posts the "Full Disk Access was turned off" notification when the recovery window opens. `NotificationAuthorization` is the single permission request both this and the digest use.
- **`ResetAllDataService`** performs the destructive full wipe on demand as an ordered, idempotent state machine: cancel owned weekly/test notifications; release the open history runtime; remove `snapshots.db`, `snapshots.db-wal`, and `snapshots.db-shm`; reset the live preference and dismissal stores; clear only Permission Pulse-prefixed defaults; recreate and migrate the history store; clear presentation state; run a fresh scan; and reconcile against the reset default `digestEnabled == false`. Missing history files are success. Other failures report the exact `.deleteHistory`, `.clearDefaults`, or `.recreateHistory` phase and stop at the appropriate dependency boundary, so a stale in-memory digest preference cannot recreate a schedule. A completed storage reset whose recovery scan fails is a distinct completed-reset outcome and produces a separate warning asking the user to choose Rescan.

On launch, `SingleInstanceGuard` runs first: if another copy with the same bundle identifier is running, this copy opens that one (which shows its window) and quits before touching the database; a copy started by `AppRelauncher` (`--relaunched-from <pid>`) waits up to 10 s for that process to exit instead. Then the app opens the store, records whether it runs from an App Translocation path, and runs the launch scan through `performRescanIfIdle()`, the one scan path. After each scan that path, in order: classifies any Full Disk Access refusal (`FullDiskAccessLoss`: first run, lost after an update, or revoked, using `lastLaunchedVersion` and whether any earlier snapshot captured Permissions or Background Items) and records this build as `lastLaunchedVersion`; updates history; opens the recovery window for a loss after an update or a revocation, at most once per build (`fdaPromptShownForVersion`); posts a change alert if one is due; and re-arms the digest. Scan requests that arrive before launch has wired up the scanner are ignored. When the user returns to the app while a Welcome or recovery window waits, it scans again and shows "back on" or offers Reopen. Double-clicking the running app in Finder (`applicationShouldHandleReopen`) opens the detail window on Overview. `ScanScheduler` then requests a scan on wake from sleep (`NSWorkspace.didWakeNotification`), at each calendar-day change (`.NSCalendarDayChanged`), and when the dropdown or detail window appears with a last scan older than 60 seconds (a full scan measured 51 ms); user-initiated refresh re-runs the scan. All requests go through `AppDelegate.rescan()`, whose in-progress guard coalesces overlaps. Each scan logs its duration under the `scan-coordinator` category.

## Concurrency

- App target and `PermissionsUI`: MainActor-by-default (Xcode 26 setting). View models, stores, and all coordinators are `@MainActor`.
- `AppDelegate` reserves scan/reset lifecycle ownership synchronously: it rejects reset while a scan is active, rejects rescan while reset is reserved or active, ignores overlapping reset requests, and prevents duplicate scans. Reset's own recovery scan uses the same guarded scan primitive without opening an external overlap window.
- `WeeklyDigestCoordinator` serializes all weekly schedule mutations in one FIFO. Canceled owners retain the mutation boundary until any late scheduler effect is cleaned up; next-fire reads wait for active mutations, so an older reconcile cannot remove a newer request or publish its date.
- `PermissionsScanners`: the four scanners are `nonisolated` `Sendable` structs whose `scan()` runs on the cooperative pool. `MediaUseObserverCMIO` is a `final class` marked `@unchecked Sendable` (it guards mutable state with an `NSLock` because the CoreMediaIO/CoreAudio callbacks arrive on a private dispatch queue). `MockWeeklyDigestScheduler` is an `actor`.
- `PermissionsStore`: GRDB's `DatabaseQueue` is thread-safe; `SnapshotStore` is a `Sendable` struct exposing `async` methods.
- Scan results cross the actor boundary as `Sendable` `ScannerOutput` values containing item arrays plus coverage warnings; media use crosses as a `MediaUseEvent` `AsyncStream`. There is no spurious `DispatchQueue.main.async` anywhere.

## AppKit drops (flagged)

Each drop carries a `// AppKit: <reason>` comment at the call site. Shipping drops as of v0.7.x:

- **Welcome and Full Disk Access recovery windows** — hosted in `NSWindow`s opened by the app delegate (`AppDelegate+Windows.swift`), which has no SwiftUI `openWindow` and must not depend on the menu-bar icon. Reset confirmation is now a SwiftUI `.alert` in Preferences.
- **`NSSavePanel` + `NSAlert`** — export destination picker and one-shot error dialogs (`ExportToolbar`, `PermissionPulseApp`).
- **`NSWorkspace`** — reveal-in-Finder (read-only) from the stale-apps list and the app-permissions inspector; `AppRelauncher` restarts the running bundle (after Reset All Data, and from the Full Disk Access windows' Reopen button).
- **`NSRunningApplication`** — `SingleInstanceGuard` finds and reactivates another running copy.
- **`NSPasteboard`** — Copy Diagnostics in Preferences → Data.
- **`NSApp.activate`** — fronting the Preferences window from the detail toolbar, and windows opened through the trampoline.

Candidates we still anticipate may force AppKit:

- **Menu-bar right-click menu** — `MenuBarExtra` does not natively support right-click context menus. If we need one we drop to `NSStatusItem` + `NSMenu`.

## Tahoe-specific workarounds

### Hidden-WindowGroup Settings trampoline

`openSettings` is broken inside `MenuBarExtra` on Tahoe. The app declares a hidden zero-size `WindowGroup(id: "settings-trampoline")` *first* in `App.body` (before `MenuBarExtra` and the singleton `Window(id:)` scenes — there is no `Settings` scene). Menu items open windows through `@Environment(\.openWindow)`; the detail and Preferences windows are singleton `Window(id:)` scenes so `openWindow(id:)` reuses the existing window rather than spawning duplicates. Code without SwiftUI's `openWindow` (the app delegate, e.g. on a Finder reopen) sets `AppViewModel.windowToOpen`; the trampoline's content view (`WindowOpeningTrampoline`) observes it, activates the app, opens that scene, and clears the request.

Reference: https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items.

**Every entry point that wants Settings goes through this trampoline. Do not call `openSettings` directly from `MenuBarExtra`.**

### Menu-bar icon design

Tahoe's transparent menu bar means our icon must render cleanly on both light and dark backgrounds. Use an SF Symbol with no fill where possible. Avoid bitmap icons unless they're designed as template images.

## Test strategy by layer

All package tests use **Swift Testing**; the UITest target uses XCTest.

- `PermissionsCore`: unit tests, no fixtures. Pure data types.
- `PermissionsScanners`: golden-fixture tests (`TCCFixtures`, `BTMFixtures`) + `Mock` behavior tests. Real-scanner tests run only on developer machines (FDA-gated).
- `PermissionsStore`: in-memory + on-disk GRDB tests (migrations, diff engine, retention, discovery).
- `PermissionsUI`: view-model and store logic tests with injected mocks + in-memory store.
- App target (`PermissionPulseTests`): coordinator-level tests (`SnapshotCoordinator`, snapshot history, scan completion, `WeeklyDigestCoordinator`, Full Disk Access flow, single instance, `ResetAllDataService`) — exercised by `scripts/smoke-test.sh §4` locally and by CI under `PERMISSION_PULSE_TEST_MODE=1`.

Current test counts and the commands that run them are in `docs/07-build-and-test.md`.

## What lives in the App target, not packages

- `Info.plist` (empty `<dict/>`; all keys come from `INFOPLIST_KEY_*` build settings). **No `.entitlements` file** — App Sandbox is off and there are no entitlements (sandbox would block the TCC.db / BTM reads).
- Bundle ID, build settings, signing config (Developer ID deferred), Sparkle config (deferred).
- The `App` struct + `AppDelegate`: the trampoline `WindowGroup`, the `MenuBarExtra`, and the singleton `Window(id:)` scenes.
- The coordinators (`ScanCoordinator`, `SnapshotCoordinator`, `MediaUseCoordinator`, `WeeklyDigestCoordinator`, `ChangeAlertCoordinator`), `ScanScheduler`, `SingleInstanceGuard`, and `ResetAllDataService`, which wire concrete scanners + store + view models together.
- App icon + assets.

Everything else is in a package.
