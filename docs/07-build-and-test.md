# 07 — Build and test

## Requirements

- macOS 14 Sonoma or later (developing on macOS 26 Tahoe).
- Xcode 26.0 or later (Xcode 26.5+ recommended).
- Swift 6.3 (bundled with Xcode 26).
- ~5 GB free disk for Xcode build outputs.

No other tooling is required for the v1 build. CI uses the same Xcode version on a GitHub Actions macOS runner.

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
  build
```

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
# Package-level tests (run without the Xcode project) — 282 tests total
swift test --package-path Packages/PermissionsCore       # 40
swift test --package-path Packages/PermissionsScanners   # 65
swift test --package-path Packages/PermissionsStore      # 39
swift test --package-path Packages/PermissionsUI         # 136

# App build + app-target tests via xcodebuild — 75 tests
PERMISSION_PULSE_TEST_MODE=1 xcodebuild test \
  -project PermissionPulse/PermissionPulse.xcodeproj \
  -scheme PermissionPulse \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:PermissionPulseTests CODE_SIGNING_ALLOWED=NO
```

Tests use **Swift Testing** (`import Testing`); the UITest target uses XCTest. The four package suites contain 282 tests and the app target contains 75 tests, for 357 automated tests total. These are fresh observed counts after the v0.7.2 final-findings regressions on macOS 26.5 with Xcode 26.5 / Swift 6.3.2, not estimates.

### Runtime-correctness contract

- Snapshot retention and stale-app thresholds are captured once at each scan boundary. Preference edits apply to the next scan without coordinator recreation and cannot change a scan already in progress.
- Reset clears the live and persisted preference/dismissal stores, Permission Pulse-prefixed defaults, presentation state, owned notifications, and the SQLite main/WAL/SHM files. It recreates the migrated store only after deletion/default cleanup succeeds. Tests assert the exact `deleteHistory`, `clearDefaults`, and `recreateHistory` failure phases, scan/reset serialization, and that reset's default-disabled live digest state cannot recreate a pending weekly request.
- A reset can complete its storage lifecycle even when the recovery scan fails. That outcome is tested and presented separately with Refresh guidance instead of being reported as either storage failure or full success.
- Weekly digest copy counts TCC-only authorization changes. Enabled day/time edits persist immediately, debounce to the final edit, serialize scheduler mutations, cancel-and-replace the pending request, refresh the actual next-fire date, and retain the selected values if scheduling fails. The orange failure state exposes Retry.

### Data-fidelity contract

- Stable application identity is `bundle:<bundle-id>` when available, otherwise `path:<standardized-file-path>`. Installed bundle clients retain their resolved path for stale probing; separate path-only clients remain independently grouped and dismissed. Legacy raw bundle-ID stale dismissals migrate without losing the choice.
- Every scanner returns `ScannerOutput(items:warnings:)`. Warning-free output is complete; warnings produce a visible degraded state with retained partial rows. A thrown failure preserves and labels last-known rows or explicitly reports that no successful history exists.
- `SnapshotCoordinator` writes only when TCC, Launch Agents, and BTM are all complete. Degraded and failed scans never persist snapshots.
- Schema v5 adds LaunchAgent `is_disabled` and a per-snapshot capture marker. v4 history is retained; disabled-only changes are ignored across a legacy boundary but detected between two v5 snapshots.
- Recent Changes renders TCC authorization transitions with stable dismissal keys. The badge, empty state, search filter, accessibility summary, and weekly digest all count the same event set. Search covers every rendered row's relevant summary/app/service/label/path/developer/identifier fields; Overview intentionally has no search field.

### Human FDA and hardware gate

The automated suites use fixtures and mocks; before release, run `scripts/smoke-test.sh` and complete the actionable Workstream C items on a representative Mac. Complete user + system TCC coverage under FDA, an installed bundle-ID stale candidate, independent path-only clients, and a visible TCC authorization transition remain human gates. One-source TCC degradation is covered safely by `swift test --package-path Packages/PermissionsScanners --filter scanRetainsItemsAndReportsSystemWarningWhenSecondDatabaseFails`, which uses isolated temporary databases and an injected missing source. Degraded, last-known, and no-history accessibility semantics are covered by `swift test --package-path Packages/PermissionsUI --filter AppViewModelAvailabilityTests`. The app has no supported live failure/source-injection seam, so the equivalent live UI and VoiceOver paths must remain explicitly unverified; do not edit, copy back, move, delete, `chmod`, or `chown` real TCC/BTM data, change protected permissions merely to force failure, use `sudo`, or otherwise escalate privileges for these checks. Intel likewise remains unverified unless the same release artifact and UI checklist run on real Intel hardware; the x86_64 slice alone is packaging evidence.

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

`scripts/smoke-test.sh` is the comprehensive pre-release gate. A normal run wipes only Permission Pulse's own state (never the real TCC.db / login items), does a Release build, asserts the bundle version (`0.7.2` / build `12`), runs all package + app-target tests, verifies the on-disk `snapshots.db` schema, and prints the full human checklist (A through V8). `--keep` preserves the production snapshot database and defaults domain; `--no-launch` skips launching the built app. Under the combined `--keep --no-launch` path, a structurally valid preserved schema-v4 database is reported as pending migration rather than v5-complete because the app had no migration opportunity; every schema-expected path still requires exact schema v5, both compatibility columns, and 0/1 marker values. Both pending-v4 and complete-v5 require the exact applicable GRDB migration identifier set (`v1` through `v4`, or `v1` through `v5`) with no missing, unexpected, or duplicate rows. All smoke schema reads use SQLite's read-only mode. `scripts/seed-diff.sh` inserts a dated empty snapshot so the next scan produces a non-empty diff for exercising the dismiss/snooze flow.

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

GitHub Actions (`.github/workflows/ci.yml`) runs on every PR and every push to `main`. Both jobs use `macos-26` and `/Applications/Xcode_26.5.app/Contents/Developer`, and print the macOS, Xcode, and Swift versions:

- **`packages` job** — runs all 282 tests in the four SwiftPM packages.
- **`app` job** — runs all 75 app-target tests in isolated test mode, performs static analysis, proves `smoke-test.sh --keep` preserves live state, then builds and independently verifies the exact v0.7.2/build 12 archive from the clean checkout.

CI never tags, publishes, or uploads that verified artifact. GitHub Releases remains a separate manual boundary.

GRDB is pinned at `7.10.0` (see each `Package.resolved`). Deployment targets are not uniform: the app release target is `14.6`, the test targets are `26.4`, and the SwiftPM packages floor at `.macOS(.v14)`. The app is built and tested only on Tahoe 26; treat 14.x as the declared floor, not a verified one.

## How this project was bootstrapped (historical)

The Xcode project at `PermissionPulse/PermissionPulse.xcodeproj` is committed. A fresh clone does **not** need to recreate it.

For reference, the original bootstrap (one-time, recorded for posterity in `git log`):

- File → New → Project → macOS → App
- Product Name `PermissionPulse`, Bundle ID `com.wallymagill.permissionpulse`, Interface SwiftUI, Language Swift, Storage None, Team None, **Include Tests** yes (the auto-generated test targets started as no-op hosts but now carry the app-target coordinator tests).
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
