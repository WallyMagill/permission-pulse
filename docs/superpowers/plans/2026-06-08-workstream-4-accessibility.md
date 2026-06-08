# Workstream 4 — Semantic Accessibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Permission Pulse a well-behaved macOS accessibility citizen for VoiceOver, Full Keyboard Access, and Reduce Motion — without touching visual styling (contrast, Dynamic Type, Reduce Transparency are Thread B).

**Architecture:** Five groupings (A1–A5) of accessibility-modifier additions on existing SwiftUI views. A1 (the menu-bar state label) is a computed property on `AppViewModel` with a real unit test; A2–A5 are view-layer `.accessibility*` modifiers verified by build + a manual VoiceOver pass (views are not unit-tested in this codebase — only view models are). Each task's code-quality review uses the **a11y-architect** agent.

**Tech Stack:** Swift 6.0 (MainActor-by-default), SwiftUI + AppKit, Swift Testing, Xcode 26.

**Source spec:** `docs/superpowers/specs/2026-06-06-app-quality-audit-design.md` (Workstream 4). The full a11y audit had ~22 findings; the two VISUAL ones (LiveBadge/MockBadge white-on-green contrast, and the pervasive fixed `system(size:)` Dynamic-Type gap) are explicitly **deferred to Thread B** and are NOT in this plan.

**Conventions:**
- Commit attribution disabled — no `Co-Authored-By` trailer.
- All user-facing / VoiceOver strings via `String(localized:)`.
- "Append modifier X to element Y" means: open the file, locate element Y (named precisely), and add the modifier — the modifier line IS the complete change. SourceKit "No such module" warnings are known false positives — trust `swift build`/`xcodebuild`.
- Package tests: `swift test --package-path Packages/PermissionsUI`. App build/tests via `xcodebuild`.

---

## File Structure

**Task 1 (A1 — menu-bar state label):**
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/AppViewModel.swift` (+`menuBarAccessibilityLabel`)
- Modify: `PermissionPulse/PermissionPulse/PermissionPulseApp.swift:26` (attach to the MenuBarExtra `Image`)
- Test: `Packages/PermissionsUI/Tests/PermissionsUITests/AppViewModelAccessibilityTests.swift` (new)

**Task 2 (A2 — label the action menus):**
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/ChangeRow.swift` (ellipsis `Menu` label/hint; hide indicator images)
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/StaleAppsTabView.swift` (ellipsis `Menu` label/hint)

**Task 3 (A3 — selected-state traits):**
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/DetailWindowView.swift` (`SidebarButton`)
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/PreferencesWindowView.swift` (`tabButton`)

**Task 4 (A4 — Reduce Motion):**
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/DetailWindowView.swift` (`RefreshToolbarButton`)

**Task 5 (A5 — decorative-icon / grouping / header sweep):**
- Modify: `MenuBarContentView.swift`, `DetailSheetStyle.swift`, `DetailWindowView.swift`, `TappableRow.swift`, `WelcomeWindowView.swift`, `SchemaMismatchBanner.swift`, `PermissionsEmptyStateView.swift`, `DiffTabView.swift` (all in `Packages/PermissionsUI/Sources/PermissionsUI/`)

---

## Task 1: A1 — Announce the menu-bar icon's state to VoiceOver

**Problem:** The menu-bar icon encodes four states purely by SF Symbol swap (`menuBarSymbolName`). VoiceOver reads only the default "Permission Pulse" — a blind user can't tell mic-in-use / unreviewed-changes / error apart. Add a parallel `menuBarAccessibilityLabel` and attach it to the icon.

**Files:** as listed above.

- [ ] **Step 1: Write the failing test**

Create `Packages/PermissionsUI/Tests/PermissionsUITests/AppViewModelAccessibilityTests.swift`:

```swift
import Foundation
import Testing
@testable import PermissionsUI

@Suite @MainActor struct AppViewModelAccessibilityTests {
    @Test func defaultLabelIsAppName() {
        #expect(AppViewModel().menuBarAccessibilityLabel == String(localized: "Permission Pulse"))
    }

    @Test func errorTakesPrecedence() {
        let vm = AppViewModel(tccScanError: .permissionDenied(reason: "x"))
        #expect(vm.menuBarAccessibilityLabel.contains("action needed"))
    }

    @Test func cameraInUseAnnounced() {
        let vm = AppViewModel(cameraInUse: true)
        #expect(vm.menuBarAccessibilityLabel.contains("camera"))
    }

    @Test func micInUseAnnounced() {
        let vm = AppViewModel(micInUse: true)
        #expect(vm.menuBarAccessibilityLabel.contains("microphone"))
    }
}
```

- [ ] **Step 2: Run the test to verify it FAILS**

Run: `swift test --package-path Packages/PermissionsUI --filter AppViewModelAccessibilityTests 2>&1 | tail -20`
Expected: FAIL to compile — `menuBarAccessibilityLabel` doesn't exist.

- [ ] **Step 3: Add `menuBarAccessibilityLabel` to `AppViewModel`**

In `AppViewModel.swift`, add directly AFTER the existing `menuBarSymbolName` computed property (mirror its exact state precedence: error → unreviewed → both → camera → mic → idle; the error check must include `launchAgentScanError`, matching `menuBarSymbolName`):

```swift
    // VoiceOver-readable mirror of `menuBarSymbolName` — the icon's state is
    // otherwise conveyed only by SF Symbol swap, which a VoiceOver user can't
    // perceive. Same precedence as the symbol. (A1)
    public var menuBarAccessibilityLabel: String {
        if tccScanError != nil || btmScanError != nil || launchAgentScanError != nil {
            return String(localized: "Permission Pulse — scan error, action needed")
        }
        if hasUnreviewedChanges {
            return String(localized: "Permission Pulse — unreviewed changes")
        }
        if micInUse && cameraInUse {
            return String(localized: "Permission Pulse — microphone and camera in use")
        }
        if cameraInUse { return String(localized: "Permission Pulse — camera in use") }
        if micInUse { return String(localized: "Permission Pulse — microphone in use") }
        return String(localized: "Permission Pulse")
    }
```

- [ ] **Step 4: Run the test to verify it PASSES**

Run: `swift test --package-path Packages/PermissionsUI --filter AppViewModelAccessibilityTests 2>&1 | tail -20`
Expected: PASS (4 tests).

- [ ] **Step 5: Attach the label to the menu-bar icon**

In `PermissionPulse/PermissionPulse/PermissionPulseApp.swift`, the `MenuBarExtra`'s `label:` closure is:

```swift
        } label: {
            Image(systemName: appDelegate.viewModel.menuBarSymbolName)
        }
```

Replace the `Image` line with the same image plus the accessibility label:

```swift
        } label: {
            Image(systemName: appDelegate.viewModel.menuBarSymbolName)
                .accessibilityLabel(appDelegate.viewModel.menuBarAccessibilityLabel)
        }
```

- [ ] **Step 6: Build app + run UI suite**

Run: `swift build --package-path Packages/PermissionsUI 2>&1 | tail -3` → builds.
Run: `xcodebuild build -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse -destination 'platform=macOS,arch=arm64' 2>&1 | tail -5` → BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add Packages/PermissionsUI/Sources/PermissionsUI/AppViewModel.swift PermissionPulse/PermissionPulse/PermissionPulseApp.swift Packages/PermissionsUI/Tests/PermissionsUITests/AppViewModelAccessibilityTests.swift
git commit -m "a11y: announce menu-bar icon state to VoiceOver (A1)"
```

---

## Task 2: A2 — Label the dismiss/snooze and skip action menus

**Problem:** `ChangeRow` (Recent Changes) and `StaleAppsTabView` (Stale Apps) hide their actions behind a bare `Image(systemName: "ellipsis.circle")` `Menu` with `.menuIndicator(.hidden)` — VoiceOver announces "ellipsis circle" with no hint that it opens dismiss/snooze/skip. Also `ChangeRow`'s leading indicator images announce raw SF Symbol names. This is the core diff-review workflow, so it's the highest-impact VoiceOver fix.

**Files:** `ChangeRow.swift`, `StaleAppsTabView.swift`.

> Build + manual verification (views aren't unit-tested). Manual: with VoiceOver on, the menu announces "Options, menu" with the hint, and the row's leading +/− icon is no longer read aloud.

- [ ] **Step 1: Label the ChangeRow menu and hide its indicator images**

In `ChangeRow.swift`:
- On the `Menu { ... } label: { Image(systemName: "ellipsis.circle") ... }` (the dismiss/snooze menu), append after the `Menu`'s modifiers (e.g. after `.menuIndicator(.hidden)`):
```swift
        .accessibilityLabel(String(localized: "Options"))
        .accessibilityHint(String(localized: "Dismiss or snooze this change"))
```
- On the leading indicator `Image(systemName:)` (the `plus.circle.fill` / `minus.circle.fill` / `arrow.triangle.2.circlepath.circle.fill` status glyph rendered before the description text), append:
```swift
        .accessibilityHidden(true)
```
(The adjacent description text — "Granted…", "Revoked…", "New background item…" — already conveys the meaning, so the glyph is decorative noise for VoiceOver.)

- [ ] **Step 2: Label the StaleAppsTabView skip menu**

In `StaleAppsTabView.swift`, the `StaleAppRow`'s `Menu { Button("Skip forever") ... } label: { Image(systemName: "ellipsis.circle") ... }` — append after the `Menu`'s modifiers (after `.fixedSize()` / `.menuIndicator(.hidden)`):
```swift
        .accessibilityLabel(String(localized: "Options"))
        .accessibilityHint(String(localized: "Skip this app forever"))
```

- [ ] **Step 3: Build + verify**

Run: `swift build --package-path Packages/PermissionsUI 2>&1 | tail -3` → builds.
Run: `swift test --package-path Packages/PermissionsUI 2>&1 | grep -E "Test run|✘|error:" | tail -3` → all pass (no behavioral change to the tested view models).

- [ ] **Step 4: Commit**

```bash
git add Packages/PermissionsUI/Sources/PermissionsUI/ChangeRow.swift Packages/PermissionsUI/Sources/PermissionsUI/StaleAppsTabView.swift
git commit -m "a11y: label dismiss/snooze and skip action menus for VoiceOver (A2)"
```

---

## Task 3: A3 — Announce selected state on custom sidebar + preferences tabs

**Problem:** `SidebarButton` (detail-window sidebar) and `tabButton` (Preferences) are custom `.plain` `Button`s whose selected state is conveyed only by color/fill. VoiceOver and Full Keyboard Access users can't tell which item/tab is active. Add the `.isSelected` trait.

**Files:** `DetailWindowView.swift` (`SidebarButton`), `PreferencesWindowView.swift` (`tabButton`).

> Build + manual verification. Manual: VoiceOver announces "selected" on the active sidebar item and Preferences tab.

- [ ] **Step 1: Add the selected trait to `SidebarButton`**

In `DetailWindowView.swift`, `SidebarButton.body` ends its `Button { ... }` with `.buttonStyle(.plain)` then `.onHover { isHovering = $0 }`. Append after `.onHover { ... }`:

```swift
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
```
(`isSelected` is the existing `private var isSelected: Bool { currentSelection == target }`.)

- [ ] **Step 2: Add the selected trait to the Preferences `tabButton`**

In `PreferencesWindowView.swift`, `tabButton(_:title:symbol:)` returns a `Button { ... }.buttonStyle(.plain)`. The local `isSelected` is already computed at the top of the function. Append after `.buttonStyle(.plain)`:

```swift
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
```

- [ ] **Step 3: Build + verify**

Run: `swift build --package-path Packages/PermissionsUI 2>&1 | tail -3` → builds.
Run: `swift test --package-path Packages/PermissionsUI 2>&1 | grep -E "Test run|✘|error:" | tail -3` → all pass.

- [ ] **Step 4: Commit**

```bash
git add Packages/PermissionsUI/Sources/PermissionsUI/DetailWindowView.swift Packages/PermissionsUI/Sources/PermissionsUI/PreferencesWindowView.swift
git commit -m "a11y: announce selected state on sidebar and preferences tabs (A3)"
```

---

## Task 4: A4 — Gate the refresh spinner on Reduce Motion

**Problem:** `RefreshToolbarButton` (in `DetailWindowView.swift`) plays a continuous `repeatForever` rotation while refreshing — a canonical vestibular-disorder trigger — without checking Reduce Motion.

**Files:** `DetailWindowView.swift` (`RefreshToolbarButton`).

> Build + manual verification. Manual: with System Settings → Accessibility → Display → Reduce Motion ON, the refresh icon does not spin continuously.

- [ ] **Step 1: Read `RefreshToolbarButton` and gate its animation**

Open `DetailWindowView.swift` and locate `private struct RefreshToolbarButton`. It applies a continuous rotation when `isRefreshing` via an animation like `.linear(duration: 0.9).repeatForever(autoreverses: false)`. Make two changes:

1. Add the environment value near the struct's other `@State`/properties:
```swift
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
```
2. Gate the repeating animation so it does not loop under Reduce Motion. Wherever the `.animation(...)` / `.linear(...).repeatForever(...)` is applied to the rotating image, make the repeating variant conditional on `!reduceMotion`. Concretely, replace the repeat-forever animation expression with:
```swift
        reduceMotion ? .default : .linear(duration: 0.9).repeatForever(autoreverses: false)
```
so that when Reduce Motion is on, the icon uses a plain (non-repeating) animation and does not spin continuously. If the spin is driven by a `.rotationEffect` + `.animation(_:value:)` pair, the conditional goes in the `.animation` argument; preserve the existing `value:` and the `isRefreshing` rotation state.

> If `RefreshToolbarButton`'s animation structure differs materially from this (e.g. it uses `withAnimation` or a `TimelineView`), adapt to the same intent — no continuous repeating rotation when `reduceMotion` is true — and note what you did. If unclear, ask.

- [ ] **Step 2: Build + verify**

Run: `swift build --package-path Packages/PermissionsUI 2>&1 | tail -3` → builds.
Run: `xcodebuild build -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse -destination 'platform=macOS,arch=arm64' 2>&1 | tail -3` → BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Packages/PermissionsUI/Sources/PermissionsUI/DetailWindowView.swift
git commit -m "a11y: gate refresh spinner on Reduce Motion (A4)"
```

---

## Task 5: A5 — Decorative-icon, grouping, and header-trait sweep

**Problem:** ~14 decorative `Image(systemName:)` elements announce raw SF Symbol names to VoiceOver; `StatRow` reads as three separate focus stops; uppercased section labels lack the `.isHeader` trait (breaking the VoiceOver Headings rotor); `ServicePillButton` and `TappableRow` lack hints. This is one mechanical batch.

**Files:** `MenuBarContentView.swift`, `DetailSheetStyle.swift`, `DetailWindowView.swift`, `TappableRow.swift`, `WelcomeWindowView.swift`, `SchemaMismatchBanner.swift`, `PermissionsEmptyStateView.swift`, `DiffTabView.swift`.

> Build + manual verification. Apply each modifier to the named element. For decorative images whose meaning is carried by adjacent text, add `.accessibilityHidden(true)`.

- [ ] **Step 1: Hide decorative icons & add grouping/headers in `MenuBarContentView.swift`**

- `BrandBadge` — the `Image(systemName: "shield.lefthalf.filled")` overlay: append `.accessibilityHidden(true)`.
- `PulseDot` — the whole `ZStack` of two `Circle`s is decorative (adjacent text conveys state). Add `.accessibilityHidden(true)` to `PulseDot`'s `body` (on the `ZStack`).
- `ActivityRow` — the leading `Circle().fill(event.markerColor)`: append `.accessibilityHidden(true)` (the "· \(descriptor)" text carries the meaning). Also add `.accessibilityElement(children: .combine)` to `ActivityRow`'s outer `HStack` so the row reads as one phrase.
- `StatRow` — add `.accessibilityElement(children: .combine)` to its outer `HStack` (so it reads "Permissions, 12" as one element, not three focus stops).
- `SectionLabel` — the `Text(title.uppercased())`: append `.accessibilityAddTraits(.isHeader)`.
- `AttentionBanner` — the leading `Image(systemName: "exclamationmark.triangle.fill")` and the trailing `Image(systemName: "chevron.right")`: append `.accessibilityHidden(true)` to BOTH (the button's title/subtitle text carries the meaning).

- [ ] **Step 2: Hide decorative icons & add headers/hints in `DetailSheetStyle.swift`**

- `SheetSectionLabel` — the `Text(title.uppercased())`: append `.accessibilityAddTraits(.isHeader)`.
- `SheetGradientTile` — the overlay `Image(systemName: symbol)`: append `.accessibilityHidden(true)` (it's the no-real-icon placeholder; the item name is adjacent).
- `ServicePillButton` — on the `Button { ... }` (after `.onHover { ... }`): append
```swift
        .accessibilityHint(String(localized: "Opens \(service.displayName) in System Settings"))
```

- [ ] **Step 3: Header trait + hide footer dot in `DetailWindowView.swift`**

- `SidebarSection` — the `Text(header.uppercased())`: append `.accessibilityAddTraits(.isHeader)`.
- `sidebarFooter` — the leading `ZStack` of two `Circle`s (the status dot; `footerText` conveys the state): append `.accessibilityHidden(true)`.

- [ ] **Step 4: `TappableRow.swift` — hide chevron, add hint**

- The trailing `Image(systemName: "chevron.right")`: append `.accessibilityHidden(true)`.
- On the row's `Button` (the `.plain` button wrapping `content()`): append `.accessibilityHint(String(localized: "Opens details"))`.

- [ ] **Step 5: Hide decorative icons in the remaining small views**

- `WelcomeWindowView.swift` — in `bulletRow`, the `Image(systemName: icon)`: append `.accessibilityHidden(true)`.
- `SchemaMismatchBanner.swift` — the `Image(systemName: "exclamationmark.triangle.fill")`: append `.accessibilityHidden(true)` (the headline/body text carries the meaning).
- `PermissionsEmptyStateView.swift` — the "Grant Access" button's leading `Image(systemName: "arrow.up.right.square")`: append `.accessibilityHidden(true)`. Also the large state glyphs (`Image(systemName: "lock.shield")` in `permissionDeniedView`, and the `clock.badge.exclamationmark` in `temporarilyUnavailableView`): append `.accessibilityHidden(true)` to each (decorative; headlines carry meaning).
- `DiffTabView.swift` — the empty-state illustration images (`Image(systemName: "clock.arrow.circlepath")` in `emptyNoPriorState`, `Image(systemName: "checkmark.seal.fill")` in `emptyContentState`, and the `exclamationmark.triangle.fill` in the `unavailableState` helper added in W1): append `.accessibilityHidden(true)` to each.

- [ ] **Step 6: Build + verify the whole UI package**

Run: `swift build --package-path Packages/PermissionsUI 2>&1 | tail -5` → builds (no errors).
Run: `swift test --package-path Packages/PermissionsUI 2>&1 | grep -E "Test run|✘|error:" | tail -3` → all pass.
Run: `xcodebuild build -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse -destination 'platform=macOS,arch=arm64' 2>&1 | tail -3` → BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add Packages/PermissionsUI/Sources/PermissionsUI/MenuBarContentView.swift Packages/PermissionsUI/Sources/PermissionsUI/DetailSheetStyle.swift Packages/PermissionsUI/Sources/PermissionsUI/DetailWindowView.swift Packages/PermissionsUI/Sources/PermissionsUI/TappableRow.swift Packages/PermissionsUI/Sources/PermissionsUI/WelcomeWindowView.swift Packages/PermissionsUI/Sources/PermissionsUI/SchemaMismatchBanner.swift Packages/PermissionsUI/Sources/PermissionsUI/PermissionsEmptyStateView.swift Packages/PermissionsUI/Sources/PermissionsUI/DiffTabView.swift
git commit -m "a11y: hide decorative icons, group rows, mark section headers (A5)"
```

---

## Final verification (after all tasks)

```bash
swift test --package-path Packages/PermissionsUI 2>&1 | tail -3
xcodebuild test -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse -destination 'platform=macOS,arch=arm64' -only-testing:PermissionPulseTests 2>&1 | grep -E "✔ Test run with|TEST SUCCEEDED|TEST FAILED" | tail -2
xcodebuild build -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse -destination 'platform=macOS,arch=arm64' 2>&1 | tail -3
```
Expected: all green + BUILD SUCCEEDED. Plus a manual VoiceOver + Reduce Motion pass on the menu bar, detail window, and a detail sheet (add to `scripts/smoke-test.sh`'s human checklist).

---

## Self-Review (completed during planning)

**Spec coverage:** A1→Task 1, A2→Task 2, A3→Task 3, A4→Task 4, A5→Task 5. All five Workstream-4 groupings covered. The two VISUAL a11y findings (badge contrast, Dynamic Type) are explicitly deferred to Thread B and intentionally NOT here.

**Dependencies / ordering:** Task 1 first (it's the testable one and touches `AppViewModel`/app entry). Tasks 2–5 are independent view edits; Task 5 touches `DetailWindowView`/`MenuBarContentView` which Tasks 3/4 also touch (different elements) — run 3 and 4 before 5, or accept that they edit different elements of the same files (sequential subagent execution avoids conflicts). No shared symbols.

**Type consistency:** the only new symbol is `AppViewModel.menuBarAccessibilityLabel` (Task 1), referenced once in `PermissionPulseApp.swift`. Everything else is SwiftUI `.accessibility*` modifiers on existing elements — no new types.

**Testability honesty:** A1 is unit-tested (the computed label on the view model). A2–A5 are SwiftUI view modifiers with no unit-test seam in this codebase (views are not unit-tested; view models and stores are) — they are build-verified, and the plan adds a manual VoiceOver / Reduce Motion pass to the smoke-test checklist. The code-quality reviews use the **a11y-architect** agent to judge label quality, trait correctness, and that decorative-hiding doesn't suppress meaningful content.
