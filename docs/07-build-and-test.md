# 07 — Build and test

## Requirements

- To run the app: macOS 14.6 or later (the declared deployment target, not a verified one). Developed on macOS 26 Tahoe and macOS 27.
- To build: Xcode 26.5 or later (Swift 6.3 with Xcode 26.5; the release Mac uses Xcode 27.2 / Swift 6.4.2 on macOS 27.2).
- ~5 GB free disk for Xcode build outputs.

No other tooling is required. CI builds and tests with Xcode 26.5 on macOS 26 and with Xcode 27.2 on macOS 27 (see [CI](#ci)). Release artifacts are built with Xcode 27.2.

## Clone

```bash
git clone https://github.com/WallyMagill/permission-pulse.git
cd permission-pulse
```

## Open

```bash
open PermissionPulse/PermissionPulse.xcodeproj
```

## Build (Debug)

From Xcode: select the `PermissionPulse` scheme, hit ⌘B.

From the CLI:

```bash
xcodebuild \
  -project PermissionPulse/PermissionPulse.xcodeproj \
  -scheme PermissionPulse \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO build
```

`CODE_SIGNING_ALLOWED=NO` matters on machines other than the maintainer's: the project carries the maintainer's `DEVELOPMENT_TEAM` with automatic signing, so a checkout without that team's certificate fails the signing step otherwise. CI and `scripts/package-release.sh` disable signing the same way and ad-hoc sign the release build afterwards.

## Run

From Xcode: ⌘R. A shield icon appears in the menu bar near the clock. Click it → "Open Permission Pulse" → the detail window opens. With Full Disk Access granted it shows live TCC + BTM data; without FDA those sections show degraded, last-known, or no-history failure state as the evidence warrants (Launch Agents and mic/cam work regardless). The app always uses the live scanners — mock data only appears in tests and SwiftUI previews, badged orange `Mock`.

From the CLI after a Debug build:

```
~/Library/Developer/Xcode/DerivedData/PermissionPulse-*/Build/Products/Debug/PermissionPulse.app
```

You can `open` it directly.

## Test

From Xcode: ⌘U runs the per-package suites and the app-level test target.

From the CLI:

```bash
# Package-level tests (run without the Xcode project) — 304 tests total
swift test --package-path Packages/PermissionsCore       # 40
swift test --package-path Packages/PermissionsScanners   # 73
swift test --package-path Packages/PermissionsStore      # 50
swift test --package-path Packages/PermissionsUI         # 141

# App build + app-target tests via xcodebuild — 87 tests
PERMISSION_PULSE_TEST_MODE=1 xcodebuild test \
  -project PermissionPulse/PermissionPulse.xcodeproj \
  -scheme PermissionPulse \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:PermissionPulseTests CODE_SIGNING_ALLOWED=NO
```

Tests use **Swift Testing** (`import Testing`); the UITest target uses XCTest. The four package suites contain 304 tests and the app target contains 87 tests, for 391 automated tests total. These are observed counts from 2026-11-13 on `release/v0.7.2` on macOS 27.2 with Xcode 27.2 / Swift 6.4.2, not estimates.

### Runtime-correctness contract

- Snapshot retention and stale-app thresholds are captured once at each scan boundary. Preference edits apply to the next scan without coordinator recreation and cannot change a scan already in progress.
- Reset clears the live and persisted preference/dismissal stores, Permission Pulse-prefixed defaults, presentation state, owned notifications, and the SQLite main/WAL/SHM files. It recreates the migrated store only after deletion/default cleanup succeeds. Tests assert the exact `deleteHistory`, `clearDefaults`, and `recreateHistory` failure phases, scan/reset serialization, and that reset's default-disabled live digest state cannot recreate a pending weekly request.
- A reset can complete its storage lifecycle even when the recovery scan fails. That outcome is tested and presented separately with Rescan guidance instead of being reported as either storage failure or full success.
- Weekly digest copy counts TCC-only authorization changes. Enabled day/time edits persist immediately, debounce to the final edit, serialize scheduler mutations, cancel-and-replace the pending request, refresh the actual next-fire date, and retain the selected values if scheduling fails. The orange failure state exposes Retry.

### Data-fidelity contract

- Stable application identity is `bundle:<bundle-id>` when available, otherwise `path:<standardized-file-path>`. Installed bundle clients retain their resolved path for stale probing; separate path-only clients remain independently grouped and dismissed. Legacy raw bundle-ID stale dismissals migrate without losing the choice.
- Every scanner returns `ScannerOutput(items:warnings:)`. Warning-free output is complete; warnings produce a visible degraded state with retained partial rows. A thrown failure preserves and labels last-known rows or explicitly reports that no successful history exists.
- `SnapshotCoordinator` writes a snapshot when a scan's evidence or coverage differs from the latest stored snapshot. Each snapshot records per-domain coverage (added in schema v6) as `complete`, `reduced`, `degraded`, or `failed`; a failed domain stores no rows and a scan where every domain failed writes nothing. Each domain picks its own baseline: the newest earlier snapshot whose coverage can be compared with the latest's (`complete`↔`complete`, `reduced`↔`reduced`, or a `complete` baseline narrowed to the system-level services for a `reduced` latest). A domain with no such baseline is reported as not compared, with its reason.
- Schema v5 adds LaunchAgent `is_disabled` and a per-snapshot capture marker. v4 history is retained; disabled-only changes are ignored across a legacy boundary but detected between two v5 snapshots.
- Schema v7 (current) adds `launch_agents.details_readable` and `launch_agents.file_name`. v4, v5, and v6 databases migrate in place; a migrated v6 database with the same agents reports no change on the next scan. A database written by a newer build or a corrupt one is refused with its own state.
- Recent Changes renders TCC authorization transitions with stable dismissal keys. The badge, empty state, search filter, accessibility summary, and weekly digest all count the same event set. Search covers every rendered row's relevant summary/app/service/label/path/developer/identifier fields; Overview intentionally has no search field.

### Human FDA and hardware gate

The automated suites use fixtures and mocks; before release, run `scripts/smoke-test.sh` and complete the actionable Workstream C items on a representative Mac. Full TCC coverage under FDA (on macOS 26: user and system records, banner "Complete data", `tcc_coverage = 'complete'`; on macOS 27: system records only, banner "System-level permissions only", `tcc_coverage = 'reduced'`), an installed bundle-ID stale candidate, independent path-only clients, and a visible TCC authorization transition remain human gates. One-source TCC degradation is covered safely by `swift test --package-path Packages/PermissionsScanners --filter scanRetainsItemsAndReportsSystemWarningWhenSecondDatabaseFails`, which uses isolated temporary databases and an injected missing source. Degraded, last-known, and no-history accessibility semantics are covered by `swift test --package-path Packages/PermissionsUI --filter AppViewModelAvailabilityTests`. The app has no supported live failure/source-injection seam, so the equivalent live UI and VoiceOver paths must remain explicitly unverified; do not edit, copy back, move, delete, `chmod`, or `chown` real TCC/BTM data, change protected permissions merely to force failure, use `sudo`, or otherwise escalate privileges for these checks. Intel likewise remains unverified unless the same release artifact and UI checklist run on real Intel hardware; the x86_64 slice alone is packaging evidence.

The focused Workstream B gate is:

```bash
swift test --package-path Packages/PermissionsUI
PERMISSION_PULSE_TEST_MODE=1 xcodebuild test \
  -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:PermissionPulseTests CODE_SIGNING_ALLOWED=NO
git diff --check
```

### Full local smoke test

`scripts/smoke-test.sh` is the comprehensive pre-release gate. A normal run wipes only Permission Pulse's own state (`snapshots.db` with its `-wal` and `-shm` files, and the defaults domain; never the real TCC.db / login items), does a Release build into its own temporary derived-data directory and checks that exact product, asserts the bundle version and build against `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `Config/Version.xcconfig` (a mismatch in either fails the run), runs all package tests (each with its own `--scratch-path` in the same temporary directory) and the app-target tests, verifies the on-disk `snapshots.db` schema, and prints the full human checklist (A through X8). If the build fails, the version check and launch are skipped. The Release build keeps the project's normal signing, because the launched app must hold Full Disk Access, post notifications, and register for launch at login during the human checklist. The temporary directory is removed at the end unless the app was launched from it, in which case the script prints its path; quit the app before deleting it. `--keep` preserves the production snapshot database and defaults domain; `--no-launch` skips launching the built app. Under the combined `--keep --no-launch` path, a structurally valid preserved schema-v4, schema-v5, or schema-v6 database is reported as pending migration rather than v7-complete because the app had no migration opportunity; every schema-expected path still requires exact schema v7: both v5 compatibility columns with 0/1 marker values, the three per-domain coverage columns holding only `complete`, `reduced`, `degraded`, or `failed`, and both v7 `launch_agents` columns. Pending-v4, pending-v5, pending-v6, and complete-v7 each require the exact applicable GRDB migration identifier set (`v1` through `v4`, `v5`, `v6`, or `v7`) with no missing, unexpected, or duplicate rows. All smoke schema reads use SQLite's read-only mode. To exercise Recent Changes, change one real permission (on macOS 27, Screen Recording or Accessibility for one app) and Rescan.

## Build and verify the v0.7.2 release artifact

This is the single supported release-artifact path. It is non-publishing and must run from a clean release commit:

```bash
scripts/smoke-test.sh --keep --no-launch
scripts/package-release.sh 0.7.2 /tmp/permission-pulse-v0.7.2
scripts/verify-release.sh \
  /tmp/permission-pulse-v0.7.2/PermissionPulse-v0.7.2.app.zip 0.7.2 12
```

The packaging script produces a universal arm64 + x86_64, ad-hoc-signed, entitlement-clean app; verifies the raw app and exact archive; and records the release commit and checksum in sidecars. Tagging, GitHub Release creation, uploading, and post-download verification remain manual steps described in `docs/06-distribution.md`. v0.7.1 and its development-signed asset remain immutable and stay latest until v0.7.2 is actually published; only then do the new release notes supersede the older artifact prospectively.

## CI

GitHub Actions (`.github/workflows/ci.yml`) runs on every PR to `main`, every push to `main` or a `release/**` branch, and on manual dispatch; a newer run on the same ref cancels the older one. Each job runs on two legs that do not cancel each other (`fail-fast: false`): `macos-26` with Xcode 26.5, and `xcode-27` (macOS 27) with Xcode 27.2. Each leg selects Xcode through `DEVELOPER_DIR`, fails with the expected path and the list of installed `/Applications/Xcode_*.app` if that Xcode is missing, and prints the macOS, Xcode, and Swift versions:

- **`packages` job** — runs all 304 tests in the four SwiftPM packages.
- **`app` job** — runs all 87 app-target tests in isolated test mode, performs static analysis, proves `smoke-test.sh --keep` preserves live state, then builds and independently verifies the release archive from the clean checkout, using the version and build number read from `Config/Version.xcconfig`.

CI never tags, publishes, or uploads that verified artifact. GitHub Releases remains a separate manual boundary.

GRDB is pinned at `7.10.0` (see each `Package.resolved`). Deployment targets are not uniform: the app release target is `14.6`, the test targets are `26.4`, and the SwiftPM packages floor at `.macOS(.v14)`. The app is built and tested only on macOS 26 and macOS 27; treat 14.6 as the declared floor, not a verified one.

## How this project was bootstrapped (historical)

The Xcode project at `PermissionPulse/PermissionPulse.xcodeproj` is committed. A fresh clone does **not** need to recreate it.

For reference, the original bootstrap (one-time, recorded for posterity in `git log`):

- File → New → Project → macOS → App
- Product Name `PermissionPulse`, Bundle ID `com.wallymagill.permissionpulse`, Interface SwiftUI, Language Swift, Storage None, Team None at bootstrap (the project now carries the maintainer's `DEVELOPMENT_TEAM` with automatic signing; see the build note above), **Include Tests** yes (the auto-generated test targets started as no-op hosts but now carry the app-target coordinator tests).
- Min Deployments → macOS 14, App Category Utilities.
- App Sandbox OFF; Hardened Runtime ON with no exception checkboxes ticked.
- Add the four local packages via **File → Add Package Dependencies → Add Local…** and link each to the app target.
- `INFOPLIST_KEY_LSUIElement = YES` (set in the target's build settings, not the Info.plist file directly — Xcode 26 generates Info.plist from build settings).
- Share the scheme: Product → Scheme → Manage Schemes → check the **Shared** column next to `PermissionPulse`.

## Troubleshooting

- **"Cannot read TCC.db" at runtime** — grant Full Disk Access in System Settings → Privacy & Security → Full Disk Access. Restart the app after granting.
- **"Build failed: cannot find module 'GRDB'"** — `File → Packages → Resolve Package Versions` in Xcode.
- **Menu-bar icon doesn't appear** — `Info.plist` must have `LSUIElement = YES`. Confirm in project settings under Info.
- **"openSettings" does nothing** — known Tahoe bug. Confirm the hidden-WindowGroup trampoline pattern is in `PermissionPulseApp.swift`. See `docs/03-architecture.md` § Tahoe-specific workarounds.
