# Thread B — Mac-native Visual / UX Consistency Overhaul (Design Spec)

**Status:** Design approved 2026-06-09; ready for implementation planning.
**Scope:** App UI only (all surfaces in `PermissionsUI` + the app target's window chrome). No scanner/store/model logic changes. Read-only hard rules unaffected — this is presentation only.

## Context

Thread A (Workstreams 1–7, merged to `main`) made Permission Pulse functionally solid, honest, accessible (semantically), and localized. What it lacks is a **design system**: every font is a hand-picked `.system(size:)`, paddings and corner radii are chosen ad-hoc per view, colors are applied inconsistently, there is no Dynamic Type, some badges fail WCAG AA contrast, and the vibrancy surfaces ignore Reduce Transparency. The app already has a coherent *visual language* (blue brand badge, vibrancy cards, tinted rounded SF-Symbol tiles, accent-blue sidebar) — it is just expressed inconsistently. Thread B formalizes that language into reusable tokens and applies it uniformly so the app reads as one polished, intentional Mac application.

This is the visual companion to Thread A and was explicitly requested: *"look like a mac application … polished, organized, matching everywhere."*

## Goals

- One **type scale** (semantic, Dynamic-Type-aware) replacing all scattered `.system(size:)` values.
- One **spacing scale** and one **radius scale** replacing ad-hoc paddings/corner radii.
- A semantic **color system** (text / category / status roles) that is light- and dark-correct and respects the user's system accent for interactive elements while keeping a fixed blue brand mark.
- **WCAG AA contrast** on every badge/label (the white-on-green/orange badges are the known offenders).
- **Reduce Transparency** support on all vibrancy/material surfaces.
- **Hybrid Dynamic Type**: scalable in resizable windows/sheets; clamped in the fixed-width menu-bar dropdown.
- Visual consistency across **every** surface: menu-bar dropdown, detail window + sidebar, all sheets, Preferences, Welcome, and the shared list rows.

## Non-goals (out of scope / deferred)

- No information-architecture or feature changes — purely visual/stylistic. (Behavior, copy, and flows are Thread A's domain and are frozen here except where a token swap touches them.)
- No new third-party dependency. Specifically **no snapshot-testing library** (respects the project's zero-third-party-UI-deps rule; GRDB remains the only third-party dep).
- No redesign of the app's structure/navigation (sidebar sections, window set, menu layout stay as they are).
- F5 (first-seen date) remains deferred to its own slice; unrelated to Thread B.

## Locked decisions

| Decision | Choice | Rationale |
|---|---|---|
| Visual direction | **Refine the current direction** | Lowest risk, preserves Thread A work, the app already has a tasteful native-with-brand language; the problem is consistency, not direction. |
| Dynamic Type | **Hybrid** | Semantic scalable styles in resizable surfaces; clamped scaling in the 320pt dropdown so it never blows out. |
| Build approach | **A — tokens-first, surface-by-surface** | Incremental, reviewable, visually checkable per surface; matches the per-task subagent+review workflow. |
| Accent | **Respect system accent for interactive elements; fixed blue brand logo; fixed category + semantic status colors** | Native (follows the user's macOS accent) without losing the blue identity; status/category colors must stay semantic. |

---

## Section 1 — Design-system foundation + typography

### Location & shape

A new `DesignSystem/` group in `PermissionsUI`:

```
Packages/PermissionsUI/Sources/PermissionsUI/DesignSystem/
├── Typography.swift   // PPFont roles + .ppFont(_:) modifier + clamp helper
├── Spacing.swift      // PPSpacing scale
├── Palette.swift      // semantic Color roles (text/category/status/surface)
├── Radii.swift        // PPRadius scale
└── Surfaces.swift     // card/vibrancy modifier (Reduce-Transparency aware) + badge style
```

Plain Swift constants + `Font`/`Color` extensions + `ViewModifier`s. No asset catalog required (semantic colors are code-defined and resolve per appearance). The existing one-offs — `vibrancyCard()`, `SheetSectionLabel`, the badge views, the sidebar section-label treatment — are **folded into** this system (re-expressed in terms of tokens), not left as parallel definitions.

### Typography — roles

Type is expressed as **semantic text styles** (so it scales), surfaced through a `PPFont` role set and a `.ppFont(_:)` view modifier. Six roles cover the app, mapping the current ad-hoc sizes (10 / 11 / 11.5 / 12 / 12.5 / 13 / 14 / 17 / 22) onto a single scale:

| Role | Backing text style | Default weight | Replaces (current) | Used for |
|---|---|---|---|---|
| `pageTitle` | `.title2` | semibold | `system(size: 22, semibold)` | detail-page titles |
| `cardHeader` | `.headline` | (default) | `system(size: 13–14, medium/semibold)`, `.headline` | section/card headers |
| `body` | `.body` | (default) | `system(size: 13)` | primary row text |
| `secondary` | `.subheadline` | (default) | `system(size: 12–12.5)` | supporting/secondary text |
| `metadata` | `.caption` | (default) | `system(size: 11–11.5)` | counts, dates, captions |
| `badge` | `.caption2` | semibold | `caption2`, `system(size: 10–11)` | Mock/Live, "new" pills, shortcut glyphs |

The uppercased-tracked **section-label** treatment (already used in the sidebar/overview/sheets) becomes one reusable modifier (`.ppSectionLabel()`) built on `metadata` + `.tracking` + `.textCase(.uppercase)` + `.accessibilityAddTraits(.isHeader)`.

### Dynamic Type — hybrid mechanism

- **Resizable surfaces** (detail window, all sheets, Preferences, Welcome): roles scale natively via their backing text styles. No cap.
- **Menu-bar dropdown** (fixed 320pt width): apply `.dynamicTypeSize(...DynamicTypeSize.xLarge)` (clamp) at the dropdown root so text scales modestly but the layout cannot break. The roles are identical; only the clamp differs.
- A small `clampedDynamicTypeSize(_:max:)` helper (or direct modifier usage) is the single place the cap is expressed. **Testable**: a pure function mapping an input size to the clamped size is unit-tested.

---

## Section 2 — Color, contrast, depth

### Color roles (semantic, light/dark-correct)

- **Text** — `textPrimary` / `textSecondary` / `textTertiary` map to the system `.primary` / `.secondary` / `.tertiary` (already adaptive). Named roles applied consistently; no raw `.foregroundStyle(.secondary)` drift.
- **Category tints** (wayfinding, fixed) — Permissions `blue`, Launch Agents `purple`, Background Items `teal`, Recent Changes `orange`, Stale Apps `pink`. Defined once as `PPColor.category(...)`; these are navigation colors and are independent of the system accent.
- **Status / semantic** (fixed, contrast-checked) — `success` green, `warning`/attention orange, `danger` red. Independent of accent (red = removed, green = added must never shift).
- **Accent** — interactive elements (sidebar selection, buttons, pickers, service pills) use `Color.accentColor` (the user's macOS accent). The **brand badge** uses a fixed blue gradient (`PPColor.brandGradient`) — a logo, not an accent-driven element.

### Badge contrast (the known AA failure)

Mock (white-on-orange), Live (white-on-green), and the "new" pill (white-on-orange) risk failing WCAG AA (4.5:1) for their small text. **Primary fix: a tinted-fill + colored-text** badge treatment (the pattern the service pills already use — e.g. dark-green text on a low-opacity green fill), which both passes contrast and reads more refined. (Darkening the solid fills is the fallback only if a specific tinted badge reads poorly in context.) Every badge is expressed through one `ppBadge(style:)` modifier whose color pairs are **contrast-verified by a unit test** (computed contrast ratio ≥ 4.5:1 against the role's resolved light and dark values).

### Depth, surfaces, Reduce Transparency

- One **card surface** — `vibrancyCard()` is rebuilt as the single card treatment (consistent material, radius `PPRadius.medium`, one standard shadow). Sheets, rows, and panels all use it.
- **Reduce Transparency** — the card/material surfaces read `@Environment(\.accessibilityReduceTransparency)` and swap the material for a solid, contrast-equivalent fill when it's enabled. Today they don't; this closes the gap in one place.
- **Brand badge shadow** and other depth cues become standard tokens, not per-view magic numbers.

### Spacing & radii

- **Spacing scale** — `PPSpacing`: `xxs 2 / xs 4 / sm 8 / md 12 / lg 16 / xl 24 / xxl 32`. Replaces the ad-hoc 5/6/7/9/10/11/14… paddings.
- **Radius scale** — `PPRadius`: `small 6 / medium 10 / large 14`. Replaces the scattered 5/6/7/8/10/11… corner radii.

Exact numeric values above are the starting scale; minor tuning is allowed during implementation **provided every surface draws from the scale** (no new one-off values).

---

## Section 3 — Surface rollout + verification

### Rollout (Approach A — one surface per task, visual check between each)

1. **Foundation** — build `DesignSystem/` (Typography, Spacing, Palette, Radii, Surfaces) + the shared badge / section-label / card treatments. Additive only; no surface changes yet. Carries the clamp + contrast unit tests.
2. **Menu-bar dropdown** (`MenuBarContentView`) — header, overview `StatRow`s, risk-summary line, recent `ActivityRow`s, `AttentionBanner`, footer `MenuRowButton`s → tokens; clamped Dynamic Type at the dropdown root; contrast-fixed badges.
3. **Detail window + sidebar** (`DetailWindowView`) — `DetailPageScaffold`, `DetailSidebar`/`SidebarButton`/`SidebarSection`, toolbar buttons, empty/scanning states (`ScanningPlaceholder`, `EmptySearchView`, `PermissionsEmptyStateView`, `SchemaMismatchBanner`) → tokens; full Dynamic Type; selection uses `Color.accentColor`.
4. **Sheets** (`AppPermissionsDetailSheet`, `LaunchAgentDetailSheet`, `BackgroundItemDetailSheet`, `FDAGrantSheet`, `ResetConfirmationSheet`, shared `DetailSheetStyle`) → unify on the shared card / section-label / spacing tokens; `ServicePillButton` aligned to the badge/pill token.
5. **Preferences + Welcome** (`PreferencesWindowView`, `WelcomeWindowView`) → tokens; consistent control/row rhythm.
6. **List rows** (`PermissionsSection`, `LaunchAgentsSection`, `BackgroundItemsSection`, `StaleAppsTabView`, `ChangeRow`, `DiffTabView`, `TappableRow`) → shared row rhythm + tokens.

Each surface task: migrate to tokens → build → existing tests stay green → light/dark + Dynamic-Type + Reduce-Transparency eyeball via `#Preview` → commit.

### Verification

- **Behavioral regression guard** — the existing 213 package + app-target tests stay green throughout (they're logic/a11y, not visual, so they catch behavior regressions while we restyle).
- **New unit tests** (Foundation task): the Dynamic Type clamp helper; a contrast assertion test computing the WCAG ratio for every `ppBadge` fg/bg pair (≥ 4.5:1). These are the automatable parts and pin the exact bug class being fixed.
- **`#Preview`s per surface** in light + dark for development-time eyeballing.
- **Smoke-test visual checklist** — add a "Visual / design system" section to `scripts/smoke-test.sh`'s HUMAN-ONLY STEPS: every surface checked at light + dark, default + large Dynamic Type, and Reduce Transparency on/off. This is the primary "is it actually polished" gate (only a human can judge that), and it pairs with the W4 accessibility checklist already there.

### Risks / mitigations

- **Type-checker explosion** when restyling deeply nested SwiftUI literals → keep extracting subviews (already a project rule); migrating per-surface keeps diffs small.
- **Dropdown layout at large text** → the clamp caps it; the visual checklist verifies the cap is comfortable.
- **Dark-mode regressions from hardcoded colors** → semantic roles + the per-surface light/dark `#Preview` check.
- **"Refine" scope creep into a redesign** → non-goals fence this; if a surface tempts a layout change, that's a separate proposal, not Thread B.

---

## Success criteria

- No `Text(...).font(.system(size:))` or ad-hoc padding/cornerRadius literals remain in migrated surfaces — all draw from `DesignSystem` tokens.
- Text scales with the system text-size setting in windows/sheets and is clamped (not broken) in the dropdown.
- Every badge/label passes WCAG AA (4.5:1), asserted by test.
- Vibrancy surfaces respond to Reduce Transparency.
- Interactive elements follow the system accent; the brand mark stays blue.
- Every surface looks visually consistent (shared type/spacing/color/depth) in both appearances — confirmed via the smoke-test visual checklist.
