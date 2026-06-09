# Thread B — Visual / UX Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reusable SwiftUI design system (type scale, spacing, radii, semantic color, contrast-safe badges, Reduce-Transparency-aware surfaces) and migrate every Permission Pulse surface onto it so the app reads as one polished, consistent, accessibility-aware Mac application.

**Architecture:** Tokens-first. Task 1 adds a pure `WCAGContrast` helper to `PermissionsCore` and a `DesignSystem/` group to `PermissionsUI` (Typography, Spacing, Radii, Palette, Surfaces) plus the contrast-fixed badges — all additive, fully tested. Tasks 2–6 migrate one surface group per task to those tokens with a visual check between each. Task 7 adds the manual visual checklist. No domain/logic changes; no new third-party dependency.

**Tech Stack:** Swift 6, SwiftUI (semantic `Font.TextStyle`, `Color`, `ViewModifier`, `@Environment(\.accessibilityReduceTransparency)`, `.dynamicTypeSize`), Swift Testing, macOS Tahoe.

**Spec:** `docs/superpowers/specs/2026-06-09-thread-b-visual-overhaul-design.md`.

---

## Migration mapping (shared reference for Tasks 2–6)

Every surface task applies this mapping. The goal: **no `.font(.system(size:))`, no ad-hoc padding/cornerRadius literals remain** in the migrated file — all draw from tokens.

**Fonts** (`.font(.system(size: N, weight: W))` → role):

| Old size (approx) | Token |
|---|---|
| 22 semibold (page titles) | `.ppFont(.pageTitle)` |
| 17 semibold / 14 semibold / `.headline` (card & sheet headers) | `.ppFont(.cardHeader)` |
| 13 (primary row text) | `.ppFont(.body)` |
| 12 / 12.5 (secondary text) | `.ppFont(.secondary)` |
| 11 / 11.5 (counts, dates, captions) | `.ppFont(.metadata)` |
| 10 / 11 + `.caption2` (badges, shortcut glyphs) | `.ppFont(.badge)` |
| uppercased tracked section labels | `.ppSectionLabel()` (replaces the inline `.font + .tracking + .textCase + .isHeader` cluster) |

**Spacing** (`.padding(N)`, `spacing: N`, `Spacer(minLength: N)`): map to the nearest `PPSpacing` step — `2→.xxs, 4→.xs, 8→.sm, 12→.md, 16→.lg, 24→.xl, 32→.xxl`. Off-scale values (5,6,7,9,10,11,14) round to the nearest step (e.g. 5/6/7→`.sm` or `.xs` per visual intent, 9/10/11→`.sm`/`.md`, 14→`.md`/`.lg`). Keep the layout visually equivalent — this is consolidation, not a redesign.

**Radii** (`cornerRadius: N`): `5/6/7 → PPRadius.small`, `8/10/11 → PPRadius.medium`, `12/14 → PPRadius.large`.

**Color:**
- Category/wayfinding tints (`.blue/.purple/.teal/.orange/.pink` used as section identity) → `PPColor.permissions/launchAgents/backgroundItems/recentChanges/staleApps`.
- Status (`.green/.orange/.red` used for success/attention/danger) → `PPColor.success/warning/danger`.
- Interactive selection/buttons/pills → keep `Color.accentColor` (already correct; do NOT convert these to a fixed color).
- The brand badge gradient → `PPColor.brandGradient`.
- Text foreground stays on the system `.primary/.secondary/.tertiary` ShapeStyles (already adaptive).

**Cards:** `.vibrancyCard()` / inline `.background(.regularMaterial, in: RoundedRectangle(...))` → the rebuilt Reduce-Transparency-aware `.vibrancyCard()` (Task 1 makes it RT-aware in place, so most callers need no change beyond confirming they use it).

**Each migrated surface keeps existing accessibility modifiers** (`.accessibilityHidden`, `.accessibilityLabel/Hint`, `.isHeader`, `.combine`, the Reduce-Motion refresh logic) — Thread A added these; do not remove them.

---

## Task 1: Design-system foundation

**Files:**
- Create: `Packages/PermissionsCore/Sources/PermissionsCore/WCAGContrast.swift`
- Create: `Packages/PermissionsCore/Tests/PermissionsCoreTests/WCAGContrastTests.swift`
- Create: `Packages/PermissionsUI/Sources/PermissionsUI/DesignSystem/Typography.swift`
- Create: `Packages/PermissionsUI/Sources/PermissionsUI/DesignSystem/Spacing.swift`
- Create: `Packages/PermissionsUI/Sources/PermissionsUI/DesignSystem/Radii.swift`
- Create: `Packages/PermissionsUI/Sources/PermissionsUI/DesignSystem/Palette.swift`
- Create: `Packages/PermissionsUI/Sources/PermissionsUI/DesignSystem/Surfaces.swift`
- Create: `Packages/PermissionsUI/Tests/PermissionsUITests/DesignSystemTests.swift`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/MockBadge.swift`, `LiveBadge.swift`
- Modify: the existing `vibrancyCard()` definition (grep for it) — make it Reduce-Transparency-aware.

- [ ] **Step 1: Write the failing WCAGContrast test**

Create `Packages/PermissionsCore/Tests/PermissionsCoreTests/WCAGContrastTests.swift`:

```swift
import Testing
@testable import PermissionsCore

@Suite("WCAGContrast")
struct WCAGContrastTests {
    @Test("black on white is 21:1") func extreme() {
        let r = WCAGContrast.ratio(foreground: (0, 0, 0), background: (1, 1, 1))
        #expect(abs(r - 21.0) < 0.1)
    }
    @Test("identical colors are 1:1") func identical() {
        let r = WCAGContrast.ratio(foreground: (0.5, 0.5, 0.5), background: (0.5, 0.5, 0.5))
        #expect(abs(r - 1.0) < 0.001)
    }
    @Test("ratio is symmetric") func symmetric() {
        let a = WCAGContrast.ratio(foreground: (0.1, 0.2, 0.3), background: (0.9, 0.8, 0.7))
        let b = WCAGContrast.ratio(foreground: (0.9, 0.8, 0.7), background: (0.1, 0.2, 0.3))
        #expect(abs(a - b) < 0.001)
    }
}
```

- [ ] **Step 2: Run it — verify it fails**

Run: `swift test --package-path Packages/PermissionsCore --filter WCAGContrastTests`
Expected: FAIL — `cannot find 'WCAGContrast' in scope`.

- [ ] **Step 3: Implement WCAGContrast (pure, in PermissionsCore)**

Create `Packages/PermissionsCore/Sources/PermissionsCore/WCAGContrast.swift`:

```swift
import Foundation

/// WCAG 2.x relative-luminance contrast ratio for sRGB color components in 0...1.
/// Pure math (no UI) so badge color pairs can be unit-tested. (Thread B)
public enum WCAGContrast {
    public static func relativeLuminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
        func linear(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    /// Contrast ratio (1...21). Order-independent.
    public static func ratio(
        foreground fg: (Double, Double, Double),
        background bg: (Double, Double, Double)
    ) -> Double {
        let l1 = relativeLuminance(fg.0, fg.1, fg.2)
        let l2 = relativeLuminance(bg.0, bg.1, bg.2)
        let hi = Swift.max(l1, l2)
        let lo = Swift.min(l1, l2)
        return (hi + 0.05) / (lo + 0.05)
    }
}
```

- [ ] **Step 4: Run it — verify it passes**

Run: `swift test --package-path Packages/PermissionsCore --filter WCAGContrastTests`
Expected: PASS — 3 tests.

- [ ] **Step 5: Create the spacing + radius tokens**

Create `Packages/PermissionsUI/Sources/PermissionsUI/DesignSystem/Spacing.swift`:

```swift
import CoreGraphics

/// The app's spacing rhythm. Every padding/spacing value draws from this. (Thread B)
public enum PPSpacing {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
}
```

Create `Packages/PermissionsUI/Sources/PermissionsUI/DesignSystem/Radii.swift`:

```swift
import CoreGraphics

/// Corner-radius scale. (Thread B)
public enum PPRadius {
    public static let small: CGFloat = 6
    public static let medium: CGFloat = 10
    public static let large: CGFloat = 14
}
```

- [ ] **Step 6: Create the typography tokens**

Create `Packages/PermissionsUI/Sources/PermissionsUI/DesignSystem/Typography.swift`:

```swift
import SwiftUI

/// Semantic type roles backed by Dynamic Type text styles so text scales with the
/// user's text-size setting. Apply with `.ppFont(_:)`. (Thread B)
public enum PPFont {
    case pageTitle
    case cardHeader
    case body
    case secondary
    case metadata
    case badge

    public var font: Font {
        switch self {
        case .pageTitle:  .system(.title2, weight: .semibold)
        case .cardHeader: .system(.headline)
        case .body:       .system(.body)
        case .secondary:  .system(.subheadline)
        case .metadata:   .system(.caption)
        case .badge:      .system(.caption2, weight: .semibold)
        }
    }
}

/// The maximum Dynamic Type size the fixed-width menu-bar dropdown allows, so it
/// scales modestly without breaking the 320pt layout. (Thread B hybrid policy)
public enum PPDynamicType {
    public static let dropdownMaximum: DynamicTypeSize = .xLarge

    /// Pure clamp used by the dropdown and unit-tested.
    public static func clampedForDropdown(_ requested: DynamicTypeSize) -> DynamicTypeSize {
        Swift.min(requested, dropdownMaximum)
    }
}

extension View {
    public func ppFont(_ role: PPFont) -> some View {
        font(role.font)
    }

    /// Uppercased, tracked, secondary section-label treatment (one definition,
    /// replacing the per-view inline cluster). (Thread B)
    public func ppSectionLabel() -> some View {
        ppFont(.metadata)
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    /// Clamp Dynamic Type for the fixed-width dropdown.
    public func ppDropdownDynamicTypeClamp() -> some View {
        dynamicTypeSize(...PPDynamicType.dropdownMaximum)
    }
}
```

- [ ] **Step 7: Create the palette (category, status, brand, contrast-safe badges)**

Create `Packages/PermissionsUI/Sources/PermissionsUI/DesignSystem/Palette.swift`:

```swift
import SwiftUI

/// Semantic colors. Category + status are fixed (accent-independent); interactive
/// elements keep `Color.accentColor` (NOT defined here). (Thread B)
public enum PPColor {
    // Category / wayfinding
    public static let permissions = Color.blue
    public static let launchAgents = Color.purple
    public static let backgroundItems = Color.teal
    public static let recentChanges = Color.orange
    public static let staleApps = Color.pink

    // Status / semantic
    public static let success = Color.green
    public static let warning = Color.orange
    public static let danger = Color.red

    // Brand mark (fixed; a logo, not accent-driven)
    public static let brandGradient = LinearGradient(
        colors: [
            Color(red: 0.37, green: 0.55, blue: 1.0),
            Color(red: 0.04, green: 0.52, blue: 1.0),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// Contrast-safe badge styles: dark, saturated text on a pale tint fill. The fg/bg
/// are FIXED sRGB pairs (self-contained — they do not inherit the surface), so
/// contrast is identical in light and dark and is unit-verified ≥ 4.5:1. (Thread B)
public enum PPBadgeStyle {
    case mock
    case live

    public var foregroundRGB: (Double, Double, Double) {
        switch self {
        case .mock: (0.45, 0.22, 0.0)   // dark amber
        case .live: (0.0, 0.33, 0.13)   // dark green
        }
    }

    public var backgroundRGB: (Double, Double, Double) {
        switch self {
        case .mock: (0.99, 0.92, 0.82)  // pale amber
        case .live: (0.86, 0.96, 0.89)  // pale green
        }
    }

    public var foreground: Color {
        Color(.sRGB, red: foregroundRGB.0, green: foregroundRGB.1, blue: foregroundRGB.2)
    }
    public var background: Color {
        Color(.sRGB, red: backgroundRGB.0, green: backgroundRGB.1, blue: backgroundRGB.2)
    }
}
```

- [ ] **Step 8: Write the failing design-system test (badge contrast + clamp)**

Create `Packages/PermissionsUI/Tests/PermissionsUITests/DesignSystemTests.swift`:

```swift
import Testing
import SwiftUI
import PermissionsCore
@testable import PermissionsUI

@Suite("DesignSystem")
struct DesignSystemTests {
    @Test("every badge style passes WCAG AA (>= 4.5:1)")
    func badgeContrast() {
        for style in [PPBadgeStyle.mock, .live] {
            let ratio = WCAGContrast.ratio(
                foreground: style.foregroundRGB,
                background: style.backgroundRGB
            )
            #expect(ratio >= 4.5, "\(style) contrast \(ratio) < 4.5")
        }
    }

    @Test("dropdown clamp caps large sizes but passes small ones through")
    func clamp() {
        #expect(PPDynamicType.clampedForDropdown(.accessibility5) == .xLarge)
        #expect(PPDynamicType.clampedForDropdown(.small) == .small)
        #expect(PPDynamicType.clampedForDropdown(.xLarge) == .xLarge)
    }
}
```

- [ ] **Step 9: Run it — verify it fails**

Run: `swift test --package-path Packages/PermissionsUI --filter DesignSystemTests`
Expected: FAIL — `PPBadgeStyle` / `PPDynamicType` not found (until the package compiles the new files). If the contrast assertion fails for a chosen color pair, adjust that pair DARKER (foreground) / PALER (background) until ≥ 4.5 — the test is the gate.

- [ ] **Step 10: Restyle the badges onto the contrast-safe tokens**

Rewrite `MockBadge.swift` body (keep `public struct MockBadge: View`, `public init()`, and the localized text + `.accessibilityLabel` from W7):

```swift
        Text(String(localized: "Mock"))
            .ppFont(.badge)
            .foregroundStyle(PPBadgeStyle.mock.foreground)
            .padding(.horizontal, PPSpacing.xs)
            .padding(.vertical, PPSpacing.xxs)
            .background(PPBadgeStyle.mock.background, in: .capsule)
            .accessibilityLabel(String(localized: "Mock data"))
```

Rewrite `LiveBadge.swift` body equivalently with `PPBadgeStyle.live` and `String(localized: "Live")` / `"Live data"`.

- [ ] **Step 11: Make `vibrancyCard()` Reduce-Transparency-aware**

Grep for the definition: `grep -rn "func vibrancyCard" Packages/PermissionsUI/Sources`. Replace its implementation so it swaps the material for a solid fill when Reduce Transparency is on. Create/replace in `Packages/PermissionsUI/Sources/PermissionsUI/DesignSystem/Surfaces.swift` (move the definition here; delete the old one):

```swift
import SwiftUI

extension View {
    /// The app's single card surface. Uses a vibrancy material normally, and a
    /// solid contrast-equivalent fill when Reduce Transparency is on. (Thread B)
    public func vibrancyCard(cornerRadius: CGFloat = PPRadius.medium) -> some View {
        modifier(VibrancyCard(cornerRadius: cornerRadius))
    }
}

private struct VibrancyCard: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content.background(
            reduceTransparency
                ? AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
                : AnyShapeStyle(.regularMaterial),
            in: shape
        )
    }
}
```

If the existing `vibrancyCard()` took different parameters, preserve its call sites (most call `.vibrancyCard()` with no args — the default `cornerRadius` covers them). Delete the old definition so there is exactly one.

- [ ] **Step 12: Build both packages + run tests**

Run: `swift build --package-path Packages/PermissionsCore` → clean.
Run: `swift build --package-path Packages/PermissionsUI` → clean.
Run: `swift test --package-path Packages/PermissionsCore` → pass.
Run: `swift test --package-path Packages/PermissionsUI` → pass (new DesignSystemTests included).

- [ ] **Step 13: Commit**

```bash
git add Packages/PermissionsCore/Sources/PermissionsCore/WCAGContrast.swift \
        Packages/PermissionsCore/Tests/PermissionsCoreTests/WCAGContrastTests.swift \
        Packages/PermissionsUI/Sources/PermissionsUI/DesignSystem/ \
        Packages/PermissionsUI/Tests/PermissionsUITests/DesignSystemTests.swift \
        Packages/PermissionsUI/Sources/PermissionsUI/MockBadge.swift \
        Packages/PermissionsUI/Sources/PermissionsUI/LiveBadge.swift
git commit -m "feat(ui): design-system foundation — tokens, contrast-safe badges, RT-aware card (Thread B)"
```

---

## Task 2: Migrate the menu-bar dropdown

**Files:** Modify `Packages/PermissionsUI/Sources/PermissionsUI/MenuBarContentView.swift`.

- [ ] **Step 1: Apply the migration mapping** (see "Migration mapping" above) to every subview in this file: `header`, `PulseDot`, `BrandBadge` (use `PPColor.brandGradient`), `SectionLabel` (→ `.ppSectionLabel()`), `StatRow`, `ActivityRow`, `AttentionBanner` (status orange → `PPColor.warning`), `MenuRowButton`, the risk-summary line. Fonts → `.ppFont`, paddings → `PPSpacing`, radii → `PPRadius`, category tints → `PPColor`. Keep all existing accessibility modifiers.

- [ ] **Step 2: Apply the dropdown Dynamic Type clamp**

On the root `VStack` of `MenuBarContentView.body` (the one with `.frame(width: 320)`), add `.ppDropdownDynamicTypeClamp()`.

Representative before/after (header status text):
```swift
// before
Text(headerStatusText).font(.system(size: 11)).foregroundStyle(.secondary)
// after
Text(headerStatusText).ppFont(.metadata).foregroundStyle(.secondary)
```

- [ ] **Step 3: Build + verify behavioral tests green**

Run: `swift build --package-path Packages/PermissionsUI` → clean.
Run: `swift test --package-path Packages/PermissionsUI` → pass (91, unchanged).

- [ ] **Step 4: Visual check** (Xcode preview or run the app): dropdown at light + dark, default + large text (confirm clamp holds the 320pt width), Reduce Transparency on/off (cards stay legible). Adjust any spacing that reads off.

- [ ] **Step 5: Commit**

```bash
git add Packages/PermissionsUI/Sources/PermissionsUI/MenuBarContentView.swift
git commit -m "refactor(ui): migrate menu-bar dropdown to design system (Thread B)"
```

---

## Task 3: Migrate the detail window + sidebar

**Files:** Modify `Packages/PermissionsUI/Sources/PermissionsUI/DetailWindowView.swift`. Also `ScanningPlaceholder.swift`, `PermissionsEmptyStateView.swift`, `SchemaMismatchBanner.swift` if they carry ad-hoc fonts/spacing.

- [ ] **Step 1: Apply the migration mapping** to `DetailPageScaffold` (titles → `.ppFont(.pageTitle)`, inline meta/subtitle → `.ppFont(.metadata)/.secondary`), `DetailSidebar`/`SidebarSection` (→ `.ppSectionLabel()`), `SidebarButton` (category tints → `PPColor.*`; selection background stays `Color.accentColor`), `RefreshToolbarButton`/`PreferencesToolbarButton`/`ExportToolbarMenu` icon framing → `PPSpacing`/`PPRadius`, `EmptySearchView`, the launch-agent error block. Keep the W4 Reduce-Motion refresh logic and all `.accessibility*` intact.

- [ ] **Step 2: Migrate the empty/scanning state views** (`ScanningPlaceholder`, `PermissionsEmptyStateView`, `SchemaMismatchBanner`) — fonts/paddings → tokens; resizable surface, so NO clamp (full Dynamic Type).

Representative before/after (sidebar section header):
```swift
// before
Text(header.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary).accessibilityAddTraits(.isHeader)
// after
Text(header).ppSectionLabel()
```

- [ ] **Step 3: Build + tests green** — `swift build`/`swift test --package-path Packages/PermissionsUI` → pass.

- [ ] **Step 4: Visual check** — detail window + each sidebar page at light/dark, default + large text (text reflows, window grows — no clamp here), Reduce Transparency on/off; sidebar selection follows the system accent (change it in System Settings to confirm).

- [ ] **Step 5: Commit**

```bash
git add Packages/PermissionsUI/Sources/PermissionsUI/DetailWindowView.swift \
        Packages/PermissionsUI/Sources/PermissionsUI/ScanningPlaceholder.swift \
        Packages/PermissionsUI/Sources/PermissionsUI/PermissionsEmptyStateView.swift \
        Packages/PermissionsUI/Sources/PermissionsUI/SchemaMismatchBanner.swift
git commit -m "refactor(ui): migrate detail window + sidebar to design system (Thread B)"
```

---

## Task 4: Migrate the sheets

**Files:** Modify `DetailSheetStyle.swift` (the shared sheet components), `AppPermissionsDetailSheet.swift`, `LaunchAgentDetailSheet.swift`, `BackgroundItemDetailSheet.swift`, `FDAGrantSheet.swift`, `ResetConfirmationSheet.swift`.

- [ ] **Step 1: Migrate the shared sheet vocabulary first** in `DetailSheetStyle.swift`: `SheetSectionLabel` → built on `.ppSectionLabel()`; `SheetKVCard`/`SheetKVRow`, `SheetRiskPanel`, `SheetGradientTile` (→ `PPColor.brandGradient`), `ServicePillButton` (text → `.ppFont`, keep `Color.accentColor` fill), `SheetCloseFooter` → tokens. `sheetFormattedDate`/`sheetShortDate` are logic — leave them.

- [ ] **Step 2: Migrate each sheet's own layout** (`AppPermissionsDetailSheet` header/pills/automation card/action footer; the other sheets' fonts/paddings/radii) to tokens. Cards → the rebuilt `.vibrancyCard()`. Keep all W6 action-footer behavior (Copy Reset Commands / Reveal in Finder) and accessibility.

Representative before/after (sheet section label):
```swift
// before (SheetSectionLabel.body)
Text(title.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary).accessibilityAddTraits(.isHeader)
// after
Text(title).ppSectionLabel()
```

- [ ] **Step 3: Build + tests green** → pass.

- [ ] **Step 4: Visual check** — open each sheet (per-app permissions, launch agent, background item, FDA grant, reset confirmation) at light/dark, default + large text, Reduce Transparency on/off.

- [ ] **Step 5: Commit**

```bash
git add Packages/PermissionsUI/Sources/PermissionsUI/DetailSheetStyle.swift \
        Packages/PermissionsUI/Sources/PermissionsUI/AppPermissionsDetailSheet.swift \
        Packages/PermissionsUI/Sources/PermissionsUI/LaunchAgentDetailSheet.swift \
        Packages/PermissionsUI/Sources/PermissionsUI/BackgroundItemDetailSheet.swift \
        Packages/PermissionsUI/Sources/PermissionsUI/FDAGrantSheet.swift \
        Packages/PermissionsUI/Sources/PermissionsUI/ResetConfirmationSheet.swift
git commit -m "refactor(ui): migrate all detail sheets to design system (Thread B)"
```

---

## Task 5: Migrate Preferences + Welcome

**Files:** Modify `PreferencesWindowView.swift`, `WelcomeWindowView.swift`.

- [ ] **Step 1: Apply the migration mapping** to both: section headers → `.ppSectionLabel()`, body/secondary/metadata text → `.ppFont`, paddings/spacing → `PPSpacing`, radii → `PPRadius`, any status color → `PPColor`. Keep control bindings, the digest/notification logic, and the Welcome bullet rows' accessibility intact. Resizable surfaces → full Dynamic Type (no clamp).

Representative before/after (Welcome bullet text):
```swift
// before
Text(text).font(.body)
// after
Text(text).ppFont(.body)
```

- [ ] **Step 2: Build + tests green** → pass.
- [ ] **Step 3: Build app target** (these surfaces are window-hosted): `xcodebuild -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse -configuration Debug build 2>&1 | tail -3` → `BUILD SUCCEEDED`.
- [ ] **Step 4: Visual check** — Preferences (both tabs) + Welcome at light/dark, default + large text, Reduce Transparency on/off.
- [ ] **Step 5: Commit**

```bash
git add Packages/PermissionsUI/Sources/PermissionsUI/PreferencesWindowView.swift \
        Packages/PermissionsUI/Sources/PermissionsUI/WelcomeWindowView.swift
git commit -m "refactor(ui): migrate Preferences + Welcome to design system (Thread B)"
```

---

## Task 6: Migrate the list rows

**Files:** Modify `PermissionsSection.swift`, `LaunchAgentsSection.swift`, `BackgroundItemsSection.swift`, `StaleAppsTabView.swift`, `ChangeRow.swift`, `DiffTabView.swift`, `TappableRow.swift`, `AppGroupRow`/`AppIconResolver` framing if needed.

- [ ] **Step 1: Apply the migration mapping** to each row/list view: row titles → `.ppFont(.body)`, secondary/metadata lines → `.ppFont(.secondary)/.metadata`, section headers → `.ppSectionLabel()`, the count capsules and "new" pill → `.ppFont(.badge)` + tokenized padding/radius, status indicators (green/red/orange) → `PPColor.success/danger/warning`, card backgrounds → `.vibrancyCard()`, dividers/`Spacer` spacing → `PPSpacing`. Keep `TappableRow`'s interaction + all `.accessibility*`.

Representative before/after (a count capsule):
```swift
// before
Text(serviceCountLabel).font(.system(size: 11)).foregroundStyle(.secondary)
    .padding(.horizontal, 8).padding(.vertical, 2).background(Color.primary.opacity(0.06), in: Capsule())
// after
Text(serviceCountLabel).ppFont(.metadata).foregroundStyle(.secondary)
    .padding(.horizontal, PPSpacing.sm).padding(.vertical, PPSpacing.xxs).background(Color.primary.opacity(0.06), in: Capsule())
```

- [ ] **Step 2: Build + tests green** → pass.
- [ ] **Step 3: Visual check** — each list (Permissions, Launch Agents, Background Items, Stale Apps, Recent Changes) populated, at light/dark, default + large text, Reduce Transparency on/off.
- [ ] **Step 4: Commit**

```bash
git add Packages/PermissionsUI/Sources/PermissionsUI/PermissionsSection.swift \
        Packages/PermissionsUI/Sources/PermissionsUI/LaunchAgentsSection.swift \
        Packages/PermissionsUI/Sources/PermissionsUI/BackgroundItemsSection.swift \
        Packages/PermissionsUI/Sources/PermissionsUI/StaleAppsTabView.swift \
        Packages/PermissionsUI/Sources/PermissionsUI/ChangeRow.swift \
        Packages/PermissionsUI/Sources/PermissionsUI/DiffTabView.swift \
        Packages/PermissionsUI/Sources/PermissionsUI/TappableRow.swift
git commit -m "refactor(ui): migrate list/diff rows to design system (Thread B)"
```

---

## Task 7: Add the visual verification checklist

**Files:** Modify `scripts/smoke-test.sh`.

- [ ] **Step 1: Add a "Visual / design system" section** to the HUMAN-ONLY STEPS heredoc (after the W4 accessibility items J–N), then `bash -n scripts/smoke-test.sh` to confirm it parses:

```
  ─── Visual / design system (Thread B) ───

  O. Type scale & Dynamic Type. System Settings → Displays (or Accessibility →
     Display) → larger text. Detail window, sheets, Preferences, Welcome all
     scale and reflow cleanly. The menu-bar dropdown scales only modestly
     (clamped at xLarge) and never blows past its 320pt width.

  P. Light & dark. Toggle Appearance (System Settings → Appearance). Every
     surface — dropdown, detail window, sidebar, each sheet, Preferences,
     Welcome — looks intentional in BOTH; no washed-out or unreadable text.

  Q. Reduce Transparency. Accessibility → Display → Reduce Transparency ON.
     All cards/panels (vibrancyCard surfaces) switch to a solid background and
     stay legible; OFF restores the vibrancy material.

  R. Accent color. System Settings → Appearance → Accent color → pick a
     non-blue (e.g. Pink). Interactive elements (sidebar selection, buttons,
     pickers, service pills) follow it; the brand badge stays blue; category
     and status colors (green/red/orange) are unchanged.

  S. Badge contrast. The Mock / Live badges read clearly (dark text on a pale
     tint) in both light and dark — no white-on-color low-contrast text.

  T. Consistency sweep. Scan all surfaces side by side: section labels,
     spacing rhythm, card depth, and type sizes match everywhere. Nothing
     looks like a one-off.
```

- [ ] **Step 2: Commit**

```bash
git add scripts/smoke-test.sh
git commit -m "test(smoke): add Thread B visual verification checklist (O–T)"
```

---

## Final verification (after all tasks)

- [ ] Full build + suite:

```bash
xcodebuild -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse -configuration Debug build 2>&1 | tail -3
swift test --package-path Packages/PermissionsCore
swift test --package-path Packages/PermissionsUI
```
Expected: `BUILD SUCCEEDED`; Core + UI suites green (incl. the new WCAGContrast + DesignSystem tests).

- [ ] Confirm no migrated surface still uses `.font(.system(size:` — `grep -rn "system(size:" Packages/PermissionsUI/Sources` should return only intentional exceptions (numeric/glyph cases if any) — investigate each remaining hit.

- [ ] Run `scripts/smoke-test.sh` and walk the new O–T visual checklist (and the existing A–N) on a real Tahoe machine.

---

## Self-Review

**Spec coverage:** §1 foundation+type → Task 1 (Typography/Spacing/Radii + `.ppFont`/`.ppSectionLabel` + `PPDynamicType` clamp). §2 color/contrast/depth → Task 1 (Palette, contrast-safe `PPBadgeStyle` + WCAGContrast test, RT-aware `vibrancyCard`). Dynamic Type hybrid → Task 1 (clamp) + applied Task 2 (dropdown clamp) vs Tasks 3–6 (no clamp). Surfaces → Tasks 2 (dropdown), 3 (detail+sidebar), 4 (sheets), 5 (preferences+welcome), 6 (list rows). Verification → Task 1 tests + Task 7 checklist + final step. No-new-dependency → honored (pure math + SwiftUI only). All spec sections covered.

**Placeholder scan:** Task 1 has complete code. Tasks 2–6 are migration tasks whose actionable content is the shared "Migration mapping" table + per-file scope + a representative before/after each — that is the appropriate granularity for a mechanical token migration across ~18 files (embedding every line would be impractical and the mapping IS the spec). No "TBD"/"add error handling"/etc.

**Type consistency:** `WCAGContrast.ratio(foreground:background:)` defined Task1 S3, used S8 + S1 tests. `PPFont`/`.ppFont(_:)`/`.ppSectionLabel()` defined Task1 S6, used Tasks 2–6. `PPSpacing`/`PPRadius` defined Task1 S5, used Tasks 2–6. `PPColor`/`PPColor.brandGradient` defined Task1 S7, used Tasks 2–6. `PPBadgeStyle.{foreground,background,foregroundRGB,backgroundRGB}` defined Task1 S7, used S8 test + S10 badges. `PPDynamicType.{dropdownMaximum,clampedForDropdown}` + `.ppDropdownDynamicTypeClamp()` defined Task1 S6, used S8 test + Task2 S2. `vibrancyCard(cornerRadius:)` rebuilt Task1 S11, used Tasks 3/4/6. Names consistent throughout.
