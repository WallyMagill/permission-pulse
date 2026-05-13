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
open PermissionPulse.xcodeproj
```

The Xcode project must already exist (created during initial bootstrap — see "Bootstrapping the Xcode project" below if cloning a pre-Xcode commit).

## Build (Debug)

From Xcode: select the `PermissionPulse` scheme, hit ⌘B.

From the CLI:

```bash
xcodebuild \
  -project PermissionPulse.xcodeproj \
  -scheme PermissionPulse \
  -configuration Debug \
  -destination 'platform=macOS' \
  build
```

## Run

From Xcode: ⌘R. A menu-bar icon appears near the clock. Click it to open the detail window.

From the CLI after a Debug build:

```
~/Library/Developer/Xcode/DerivedData/PermissionPulse-*/Build/Products/Debug/Permission Pulse.app
```

You can `open` it directly.

## Test

From Xcode: ⌘U runs all tests across the four packages.

From the CLI:

```bash
# Package-level tests (run without the Xcode project)
swift test --package-path Packages/PermissionsCore
swift test --package-path Packages/PermissionsScanners
swift test --package-path Packages/PermissionsStore
swift test --package-path Packages/PermissionsUI

# Full app + packages test via xcodebuild
xcodebuild \
  -project PermissionPulse.xcodeproj \
  -scheme PermissionPulse \
  -destination 'platform=macOS' \
  test
```

Tests use **Swift Testing** (`import Testing`) for new tests. The four packages each have a smoke test that asserts the package builds and basic types initialize.

## CI

GitHub Actions runs on every PR and every push to `main`:

- Build (Debug) of the Xcode project.
- Test of all four packages and the app.

Workflow file: `.github/workflows/ci.yml`. The CI runner uses macOS 26 Tahoe; the deployment target stays at macOS 14.

## Bootstrapping the Xcode project (one-time)

The first commit of this repo does **not** contain `PermissionPulse.xcodeproj` — Xcode project files are best created interactively in Xcode to avoid file-format drift. To create the project from a fresh clone:

1. Open Xcode 26.5+.
2. **File → New → Project → macOS → App**.
3. Settings:
   - **Product Name:** `PermissionPulse`
   - **Team:** None (ad-hoc signing for now).
   - **Organization Identifier:** `com.wallymagill`
   - **Bundle Identifier:** `com.wallymagill.permissionpulse` (auto-derived).
   - **Interface:** SwiftUI
   - **Language:** Swift
   - **Storage:** None
   - **Include Tests:** Off (we use per-package tests).
4. Save at the repo root (the folder containing this README). Xcode will create `PermissionPulse.xcodeproj` and a nested `PermissionPulse/` folder with `PermissionPulseApp.swift` and `ContentView.swift`.
5. **Project settings → PermissionPulse target → General:**
   - **Minimum Deployments → macOS:** 14.0
   - **App Category:** Utilities
6. **Signing & Capabilities:**
   - **App Sandbox:** OFF
   - **Hardened Runtime:** ON (default)
7. **Info tab:** add `LSUIElement = YES` (Boolean). This hides the Dock icon and makes Permission Pulse a menu-bar-only app.
8. Add the four local packages: **File → Add Package Dependencies → Add Local…** for each of:
   - `Packages/PermissionsCore`
   - `Packages/PermissionsScanners`
   - `Packages/PermissionsStore`
   - `Packages/PermissionsUI`
   Link each into the `PermissionPulse` target.
9. Replace the generated `ContentView.swift` and `PermissionPulseApp.swift` with the files in `App/` from this repo (a follow-up commit drops these in alongside the project file).
10. Build (⌘B). Should be green.

This is the only manual step; once the project is committed, future clones use the committed `PermissionPulse.xcodeproj` directly.

## Troubleshooting

- **"Cannot read TCC.db" at runtime** — grant Full Disk Access in System Settings → Privacy & Security → Full Disk Access. Restart the app after granting.
- **"Build failed: cannot find module 'GRDB'"** — `File → Packages → Resolve Package Versions` in Xcode.
- **Menu-bar icon doesn't appear** — `Info.plist` must have `LSUIElement = YES`. Confirm in project settings under Info.
- **"openSettings" does nothing** — known Tahoe bug. Confirm the hidden-WindowGroup trampoline pattern is in `PermissionPulseApp.swift`. See `docs/03-architecture.md` § Tahoe-specific workarounds.
