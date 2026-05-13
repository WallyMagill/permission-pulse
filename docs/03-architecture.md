# 03 — Architecture

Permission Pulse is a thin SwiftUI app wrapping four local SwiftPM packages.

## Layout

```
permission-pulse/                       (Xcode project)
├── App/                                (Xcode app target — SwiftUI lifecycle)
│   ├── PermissionPulseApp.swift
│   ├── MenuBar/
│   ├── DetailWindow/
│   ├── ScanCoordinator.swift
│   ├── Info.plist
│   └── PermissionPulse.entitlements
└── Packages/
    ├── PermissionsCore/                (types, protocols, errors — zero deps)
    ├── PermissionsScanners/            (TCC, LaunchAgents, BTM, Mic/Cam)
    ├── PermissionsStore/               (GRDB-backed snapshot store)
    └── PermissionsUI/                  (shared SwiftUI views, ViewModels)
```

## Package responsibilities

### `PermissionsCore`

- Types: `PermissionService`, `PermissionGrant`, `AppIdentity`, `LaunchAgentItem`, `BackgroundItem`, `SnapshotID`.
- Scanner protocols: `TCCScanner`, `LaunchAgentScanner`, `BTMScanner`, `MediaUseScanner`.
- Error types: `ScannerError`, `StoreError`.
- Zero third-party dependencies. Pure Swift, fully `Sendable`.

### `PermissionsScanners`

- Concrete scanner implementations: `TCCScannerSQLite`, `LaunchAgentScannerFS`, `BTMScannerDirect` (parses `.btm`), `BTMScannerSFL` (shell to `sfltool dumpbtm`), `MediaUseScannerAVFoundation`.
- `MockScanner` implementations for every protocol — for tests and the "scanners not yet wired" runtime mode.
- Depends on `PermissionsCore`.
- No UI, no storage. Pure scanning logic.

### `PermissionsStore`

- GRDB.swift-backed SQLite store at `~/Library/Application Support/com.wallymagill.permissionpulse/snapshots.db`.
- Daily snapshot writes, diff queries, retention (keep ≤ 90 days for v1).
- Depends on `PermissionsCore` + GRDB.
- No UI, no scanning.

### `PermissionsUI`

- SwiftUI views: `PermissionInboxView`, `WhatChangedView`, `StaleAppsView`, `MenuBarContentView`, `DetailWindowView`.
- `@Observable` ViewModels: `PermissionInboxViewModel`, `WhatChangedViewModel`, `StaleAppsViewModel`.
- Depends on `PermissionsCore`. Does **not** depend directly on `PermissionsScanners` or `PermissionsStore` — those are injected into ViewModels from the app target.

## Data flow

```
[ Scanners ] → ScanResult → [ Store ] → daily snapshot rows
                                ↓
                           diff queries
                                ↓
                       [ ViewModels ] → @Observable state
                                ↓
                          [ SwiftUI views ]
```

A `ScanCoordinator` (in the App target, not a package) owns the scanners, the store, and a background scheduler. On launch it kicks off a scan; on a daily timer it writes a fresh snapshot; on user-initiated refresh it re-scans and writes.

## Concurrency

- App target and `PermissionsUI`: MainActor-by-default (Xcode 26 setting). ViewModels are `@MainActor`.
- `PermissionsScanners`: `nonisolated` types. Each scanner is an `actor` or a `Sendable` struct depending on whether it needs mutable state.
- `PermissionsStore`: GRDB's `DatabasePool` is thread-safe; the store wrapper is a `Sendable` struct exposing `async` methods.
- Scan results cross the actor boundary as `Sendable` `ScanResult` values.

## AppKit drops (flagged)

None yet planned for v1. If any are needed, they will be added to this section with a one-paragraph "why SwiftUI can't do this" justification.

Candidates we anticipate may force AppKit:

- **Menu-bar right-click menu** — SwiftUI `MenuBarExtra` does not natively support right-click context menus. If we need one (e.g., "Quit / Preferences / Pause" on right-click), we drop to `NSStatusItem` + `NSMenu`.
- **Native System Settings deep-link list with section anchors** — likely fine in SwiftUI but flag if it gets ugly.

## Tahoe-specific workarounds

### Hidden-WindowGroup Settings trampoline

`openSettings` is broken inside `MenuBarExtra` on Tahoe. The app declares a hidden `WindowGroup(id: "settings-trampoline")` *before* the `Settings` scene. Menu items that open Settings route through `@Environment(\.openWindow)` to the trampoline, which immediately invokes `openSettings` from a normal-window context where it works.

Reference: https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items.

**Every entry point that wants Settings goes through this trampoline. Do not call `openSettings` directly from `MenuBarExtra`.**

### Menu-bar icon design

Tahoe's transparent menu bar means our icon must render cleanly on both light and dark backgrounds. Use an SF Symbol with no fill where possible. Avoid bitmap icons unless they're designed as template images.

## Test strategy by layer

- `PermissionsCore`: unit tests, no fixtures. Pure data types.
- `PermissionsScanners`: smoke tests using `MockScanner` fixtures. Real-scanner tests run only on developer machines (FDA-gated) and are tagged so CI skips them.
- `PermissionsStore`: in-memory GRDB tests + on-disk integration tests against a temp file.
- `PermissionsUI`: ViewModel logic tests with injected `MockScanner` + in-memory store. SwiftUI snapshot tests only if a regression bites us.

## What lives in the App target, not packages

- `Info.plist` and `PermissionPulse.entitlements`.
- Bundle ID, signing config (when we have a Developer ID), Sparkle config (deferred).
- The `App` struct with `MenuBarExtra` and `WindowGroup`s.
- The `ScanCoordinator` (composes scanners + store + ViewModels).
- App icon + assets.

Everything else is in a package.
