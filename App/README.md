# App/ — Xcode app target sources

These files belong to the `PermissionPulse` Xcode app target, not to any SwiftPM package.

They are stored here so they live in version control and survive a clean re-creation of the Xcode project. They will not compile on their own — they assume the Xcode project links the four local packages in `Packages/`.

## Files

- `PermissionPulseApp.swift` — `@main` SwiftUI App with `MenuBarExtra`, the detail `WindowGroup`, and the Tahoe-specific settings trampoline.
- `ScanCoordinator.swift` — composes mock scanners + view model. Where real scanners get wired starting in v0.2.0.

## After creating the Xcode project

Follow `docs/07-build-and-test.md`. The short version once the project exists:

1. Drag both files from `App/` into the Xcode `PermissionPulse` target.
2. Delete Xcode's generated `ContentView.swift` and `PermissionPulseApp.swift` if those were auto-created.
3. Confirm the four local packages (`PermissionsCore`, `PermissionsScanners`, `PermissionsStore`, `PermissionsUI`) are added as Local Package Dependencies and linked to the `PermissionPulse` target.
4. Set `LSUIElement = YES` in the target's Info tab so the app runs menu-bar-only.
5. Build (⌘B). Run (⌘R). A shield icon appears in the menu bar; click it to see the dropdown; click "Open Permission Pulse" to open the detail window populated with mock data.
