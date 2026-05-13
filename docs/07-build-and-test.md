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

From Xcode: ⌘R. A shield icon appears in the menu bar near the clock. Click it → "Open Permission Pulse" → the detail window opens with mock-data sections labeled with an orange `Mock` badge.

From the CLI after a Debug build:

```
~/Library/Developer/Xcode/DerivedData/PermissionPulse-*/Build/Products/Debug/PermissionPulse.app
```

You can `open` it directly.

## Test

From Xcode: ⌘U runs the per-package smoke tests and the (currently empty) app-level test target.

From the CLI:

```bash
# Package-level tests (run without the Xcode project)
swift test --package-path Packages/PermissionsCore
swift test --package-path Packages/PermissionsScanners
swift test --package-path Packages/PermissionsStore
swift test --package-path Packages/PermissionsUI

# Full app build + (empty) test target via xcodebuild
xcodebuild \
  -project PermissionPulse/PermissionPulse.xcodeproj \
  -scheme PermissionPulse \
  -destination 'platform=macOS,arch=arm64' \
  test
```

Tests use **Swift Testing** (`import Testing`) for new tests. The four packages each have a smoke test that asserts the package builds and basic types initialize.

## CI

GitHub Actions runs on every PR and every push to `main`:

- Build + test of all four SwiftPM packages with `swift test`.
- Build + test of the Xcode app target with `xcodebuild`.

Workflow file: `.github/workflows/ci.yml`. The CI runner uses macOS-latest; the deployment target stays at macOS 14.

## How this project was bootstrapped (historical)

The Xcode project at `PermissionPulse/PermissionPulse.xcodeproj` is committed. A fresh clone does **not** need to recreate it.

For reference, the original bootstrap (one-time, recorded for posterity in `git log`):

- File → New → Project → macOS → App
- Product Name `PermissionPulse`, Bundle ID `com.wallymagill.permissionpulse`, Interface SwiftUI, Language Swift, Storage None, Team None, **Include Tests** can be either (the auto-generated test targets are kept as no-op hosts).
- Min Deployments → macOS 14, App Category Utilities.
- App Sandbox OFF; Hardened Runtime ON with no exception checkboxes ticked.
- Add the four local packages via **File → Add Package Dependencies → Add Local…** and link each to the app target.
- `INFOPLIST_KEY_LSUIElement = YES` (set in the target's build settings, not the Info.plist file directly — Xcode 16+ generates Info.plist from build settings).
- Share the scheme: Product → Scheme → Manage Schemes → check the **Shared** column next to `PermissionPulse`.

## Troubleshooting

- **"Cannot read TCC.db" at runtime** — grant Full Disk Access in System Settings → Privacy & Security → Full Disk Access. Restart the app after granting.
- **"Build failed: cannot find module 'GRDB'"** — `File → Packages → Resolve Package Versions` in Xcode.
- **Menu-bar icon doesn't appear** — `Info.plist` must have `LSUIElement = YES`. Confirm in project settings under Info.
- **"openSettings" does nothing** — known Tahoe bug. Confirm the hidden-WindowGroup trampoline pattern is in `PermissionPulseApp.swift`. See `docs/03-architecture.md` § Tahoe-specific workarounds.
