# 14 — Fifth slice: mic/cam observer + state-driven menu-bar icon

**Status:** Implemented v0.4.1 — 2026-05-14.

## Why this slice

- v0.4.0 left two visible polish bugs (Mock badge + Grant button rendering inside `List` sections on Tahoe 26) and one missing feature (mic/cam current use). All three touch the same surface — menu bar + detail window — so doing them together avoids redesigning the same surface twice.
- The `MenuBarExtra("...", systemImage: "shield.lefthalf.filled")` literal at `PermissionPulseApp.swift:19` could not reflect runtime state. Users had no signal that something needed attention without opening the dropdown.
- The `List`-section rendering bugs were tried and patched in v0.4.0 with `.listRowInsets`/`.listRowBackground`; both attempts failed. The fix was to leave `List` entirely.

## Preconditions verified

A standalone Swift script (`/tmp/mediausediag.swift`) was run on macOS Tahoe 26 to verify mic/cam observation feasibility without entitlements. Results:

- `AVCaptureDevice.devices(for:)` enumerates devices but is deprecated since macOS 10.15.
- `AVCaptureDevice.isInUseByAnotherApplication` exists on the SDK but reports `0` whether or not another app is using the device (deprecated; only honors values when the calling process holds an active capture session).
- **`CoreMediaIO` `kCMIODevicePropertyDeviceIsRunningSomewhere`** returned `err=0` on Tahoe with no entitlements, no permission popup, no `Info.plist` usage strings. This is the OverSight-style approach used by other camera-indicator utilities for years.
- `CoreMediaIO` only enumerates **video** devices (`kCMIOHardwarePropertyDevices`). For audio inputs, the parallel `CoreAudio` API (`kAudioHardwarePropertyDevices` + filter to `kAudioDevicePropertyStreamConfiguration` with `mNumberChannels > 0` on `kAudioDevicePropertyScopeInput`) provides the same property selector under the `kAudioDevicePropertyDeviceIsRunningSomewhere` name.

Decision: **Branch α — ship the observer.**

## What shipped

1. **`MediaUseObserver` protocol** in `PermissionsCore` — `func events() -> AsyncStream<MediaUseEvent>` + `func stop() async`. `AsyncStream` (not `async throws -> [T]`) because mic/cam state is continuous and event-driven; polling would either miss short usages or burn CPU.
2. **`MediaUseObserverCMIO`** in `PermissionsScanners` — `nonisolated final class @unchecked Sendable`. Registers `CMIOObjectAddPropertyListenerBlock` on every CMIO device (cameras) and `AudioObjectAddPropertyListenerBlock` on every CoreAudio device with an input stream (microphones). Listener fires on a background `DispatchQueue` (`com.wallymagill.permissionpulse.mediause`, QoS `.utility`). Aggregate "any device of this kind running anywhere" is computed on each listener fire and yielded as a `MediaUseEvent`. Uses `NSLock.withLock` for state access (Swift 6 strict concurrency rejects `NSLock.lock()` in async contexts). Listeners are torn down on stream termination via `onTermination` and on `deinit`.
3. **`MockMediaUseObserver`** in `PermissionsScanners` — yields a deterministic four-event sequence (mic on, cam on, mic off, cam off) and finishes. Used in previews and tests.
4. **`MediaUseCoordinator`** in the app target — owns the observer, runs from `applicationDidFinishLaunching` until app quit. Consumes the stream in a `Task { @MainActor [weak viewModel] in ... }` so events propagate to `AppViewModel.micInUse` / `cameraInUse` without blocking the main actor. Uses `[weak viewModel]` on principle even though coordinator and viewModel share the AppDelegate's lifetime today.
5. **State-driven `MenuBarExtra` icon.** Converted to `label:` closure form reading from a new computed property `AppViewModel.menuBarSymbolName`. Priority: `error > cam+mic > cam > mic > idle`, mapping to:
   - `exclamationmark.shield.fill` (FDA error)
   - `video.badge.waveform` (both in use)
   - `video.fill` (camera only)
   - `mic.fill` (microphone only)
   - `shield.lefthalf.filled` (idle)

   No manual `.foregroundStyle` tinting — macOS templates the glyph to match light / dark / transparent menu bar; manual tints fight the system.
6. **`DetailWindowView` full ScrollView rewrite.** `NavigationStack { List { ... } }` becomes `NavigationStack { ScrollView { VStack { ... } } }` with custom-header section components. The `Section { } header: { ... }` pattern is gone, which removes the surface where the v0.4.0 Mock-badge bug lived. Toolbar Refresh button still attaches to `NavigationStack` and works unchanged.
7. **`PermissionsSection`** extracted as a new file with the same custom-header pattern, plus row separators via `Divider().padding(.leading, 12)` and a soft `.regularMaterial` card background for populated rows.
8. **`SectionHeader`** extracted as a shared helper used by `PermissionsSection`, `BackgroundItemsSection`, and `LaunchAgentsSection` for the title + Mock/Live badge HStack.
9. **`FDAGrantSheet`** new SwiftUI `.sheet`. Header (lock icon + title + subhead), body explaining FDA, three numbered steps in a card, footer "no network" reassurance, Cancel + "Open System Settings" buttons. Triggered by `viewModel.showFDASheetOnDetail = true`. Reuses `SystemSettingsLink.openFullDiskAccess()`.
10. **Routing for the sheet.** From the menu bar `AttentionRow`, the action becomes `viewModel.showFDASheetOnDetail = true; openWindow(id: "detail")` — sheet is presented from the detail window (`.sheet(isPresented: $bindable.showFDASheetOnDetail)`), not from `MenuBarExtra` directly, because SwiftUI `.sheet` from `MenuBarExtra(style: .window)` is documented as flaky cross-version. The empty-state Grant button (already in the detail window) sets the same flag.

## Data flow

```
CMIO/CoreAudio property listeners (background queue)
        │
        ▼
MediaUseObserverCMIO.events()  AsyncStream<MediaUseEvent>
        │
        ▼
MediaUseCoordinator   Task { @MainActor [weak viewModel] in for await ... }
        │
        ▼
AppViewModel.micInUse / cameraInUse  (@Observable)
        │
        ├─→ AppViewModel.menuBarSymbolName  (computed)
        │       │
        │       ▼
        │   MenuBarExtra { ... } label: { Image(systemName: ...) }
        │
        └─→ DetailWindowView   (could surface mic/cam state in v0.4.2)

MenuBar AttentionRow.action  →  viewModel.showFDASheetOnDetail = true; openWindow(id: "detail")
                                       │
                                       ▼
                              DetailWindowView   .sheet(isPresented: $bindable.showFDASheetOnDetail) { FDAGrantSheet() }
```

## Files touched

- **New:**
  - `Packages/PermissionsScanners/Sources/PermissionsScanners/MediaUseObserverCMIO.swift`
  - `Packages/PermissionsScanners/Sources/PermissionsScanners/MockMediaUseObserver.swift`
  - `PermissionPulse/PermissionPulse/MediaUseCoordinator.swift`
  - `Packages/PermissionsUI/Sources/PermissionsUI/PermissionsSection.swift`
  - `Packages/PermissionsUI/Sources/PermissionsUI/SectionHeader.swift`
  - `Packages/PermissionsUI/Sources/PermissionsUI/FDAGrantSheet.swift`
  - `Packages/PermissionsScanners/Tests/PermissionsScannersTests/MockMediaUseObserverTests.swift`
  - `Packages/PermissionsUI/Tests/PermissionsUITests/MenuBarSymbolNameTests.swift`
  - `Packages/PermissionsUI/Tests/PermissionsUITests/AppViewModelMediaStateTests.swift`
  - `docs/14-mic-cam-icon-slice.md` (this file)

- **Modified:**
  - `Packages/PermissionsCore/Sources/PermissionsCore/Scanners.swift` — added `MediaUseEvent`, `MediaUseObserver`.
  - `Packages/PermissionsUI/Sources/PermissionsUI/AppViewModel.swift` — added `micInUse`, `cameraInUse`, `mediaDataSource`, `showFDASheetOnDetail`, `menuBarSymbolName`.
  - `Packages/PermissionsUI/Sources/PermissionsUI/DetailWindowView.swift` — full ScrollView rewrite + sheet binding.
  - `Packages/PermissionsUI/Sources/PermissionsUI/BackgroundItemsSection.swift` — drop `Section`, custom-header VStack, card background.
  - `Packages/PermissionsUI/Sources/PermissionsUI/LaunchAgentsSection.swift` — same.
  - `Packages/PermissionsUI/Sources/PermissionsUI/PermissionsEmptyStateView.swift` — Grant button now flips `showFDASheetOnDetail` via `@Environment(AppViewModel.self)` instead of calling `SystemSettingsLink.openFullDiskAccess()` directly.
  - `Packages/PermissionsUI/Sources/PermissionsUI/MenuBarContentView.swift` — attention rows route through `presentFDASheet()`.
  - `PermissionPulse/PermissionPulse/PermissionPulseApp.swift` — `MenuBarExtra` `label:` closure form, `AppDelegate` owns and starts a `MediaUseCoordinator`.
  - `docs/09-roadmap.md` — mark v0.4.1 done.
  - `docs/04-data-sources.md` — replace mic/cam description with the actual implementation.

## Test coverage

- `MockMediaUseObserverTests` — 3 cases (sequence, idempotent stop, event equality).
- `MenuBarSymbolNameTests` — 8 cases covering all priority transitions (idle, mic-only, cam-only, both, error-beats-mic-cam, btm-error-alone, schema-mismatch, both-errors).
- `AppViewModelMediaStateTests` — 8 cases (defaults, assignment propagation, clearing, sheet flag round trip).

Test counts: 67 (v0.4.0) → 86 (v0.4.1):
- `PermissionsCore`: 12 (unchanged)
- `PermissionsScanners`: 36 → 39 (+3 mock observer)
- `PermissionsUI`: 13 → 29 (+8 symbol name, +8 media state)
- `PermissionsStore`: 6 (unchanged)

## Icon priority

| State | Symbol |
|---|---|
| `tccScanError != nil` or `btmScanError != nil` | `exclamationmark.shield.fill` |
| `micInUse && cameraInUse` | `video.badge.waveform` |
| `cameraInUse` only | `video.fill` |
| `micInUse` only | `mic.fill` |
| neither | `shield.lefthalf.filled` |

Error always wins — the user needs to know FDA is not granted before they care which device is being used.

## Deferred to later slices

- **Per-app consumer attribution** (which app is using the mic/camera right now). CMIO does not directly expose it. `lsof` parsing or `libproc` PID enumeration are options for v0.4.2.
- **Surface mic/cam state inside the detail window** (e.g., a "Currently in use by …" row). v0.4.2 candidate.
- **Snapshot store table for mic/cam events** (history view). v0.5.0+ if useful.
- **Custom Asset catalog template image** with the orange error-badge baked in, if the system templating doesn't read distinctly enough on transparent menu bars. Defer until there's a concrete visual complaint.

## Tahoe-specific risks (documented)

- **CMIO + CoreAudio property listener APIs.** Public, no entitlement, used by countless utilities for years. If Apple breaks them in a Tahoe point release, the observer falls back to "no events emitted" — `micInUse`/`cameraInUse` stay `false` — icon stays at idle/error. No crash.
- **Sheet inside `MenuBarExtra(style: .window)`.** Documented as flaky cross-version. Mitigated by routing through the detail window (sheet is presented by `DetailWindowView`, not `MenuBarContentView`). If even the detail-window path breaks on a future Tahoe, fallback is wrapping `FDAGrantSheet` as an `NSHostingController` in an `NSWindow.beginSheet` call.
- **`NSLock.lock()` is unavailable from async contexts in Swift 6.** `MediaUseObserverCMIO.stop()` uses `lock.withLock { }` instead. Same pattern works in the sync paths.
- **Preview drift.** Section previews now wrap in `ScrollView { VStack { ... } }` instead of `List { ... }` to match production layout. Easy to forget on future preview edits.

## Done means

- All four package test suites pass (`swift test` on each) — 86 tests total.
- `xcodebuild -scheme PermissionPulse -configuration Debug build` succeeds.
- Launching the app on Tahoe with FDA granted: menu-bar icon is `shield.lefthalf.filled`. Open Zoom with mic + cam → icon transitions to `video.badge.waveform` within 1–2s. Stop the meeting → icon returns to `shield.lefthalf.filled`.
- Launching the app without FDA: menu-bar icon shows `exclamationmark.shield.fill`. Click the dropdown attention row → detail window opens, `FDAGrantSheet` appears with steps and "Open System Settings" / Cancel buttons. Click Open Settings → System Settings opens to the Full Disk Access pane; sheet dismisses.
- Detail window: no Mock badge appears in section headers when scan errors are present. Layout is plain `ScrollView` (no `List`-style row chrome). Refresh toolbar button still works.
