# Thread C — Pure-Native Redesign (Design Spec)

**Status:** Design approved 2026-06-09; ready for implementation planning.
**Scope:** UI/UX redesign of every user-facing surface in `PermissionsUI` + the app target's scenes. Navigation, layout, and interaction-model changes are in scope (unlike Thread B). Scanner / store / model logic is untouched; the read-only hard rules are unaffected.

## Context

Thread A made the app functionally solid, honest, accessible, and localized. Thread B gave it a design system (tokens for type / spacing / color / radii / surfaces, AA-contrast badges, Reduce Transparency support) but explicitly fenced off layout, information-architecture, and workflow changes. Thread C is that deferred redesign: restructure every surface so Permission Pulse reads as a **pure system-native macOS app** — System Settings / Activity Monitor DNA — with one continuous glance → investigate → act workflow.

The May 2026 HTML mockups in `design-mockups/` are outdated and explicitly **not** an input to this design.

## Goals

- The app is visually and behaviorally indistinguishable from a well-made built-in macOS app.
- One continuous workflow: every count or status shown anywhere is clickable and lands the user where they can act on it.
- Replace the modal-sheet detail pattern with a non-modal, selection-driven inspector.
- Give the window a grouped source-list sidebar with an Overview landing page.
- Rebuild the dropdown as a short, fixed-shape glance surface whose rows deep-link into the window.
- Keep all Thread B tokens, contrast guarantees, and accessibility behavior intact underneath.

## Non-goals

- No scanner, store, or model changes. No new data sources.
- No new third-party dependencies (GRDB remains the only one).
- No changes to distribution, signing, or the unsigned-bundle constraints.
- No copy rewrite beyond what new layouts require (Thread A's honesty/localization discipline stands; all new strings go through `String(localized:)`).
- F5 (first-seen date) remains deferred.

## Locked decisions

| Decision | Choice | Rationale |
|---|---|---|
| Archetype | **Pure system-native** | Trust through familiarity — a security/hygiene tool should look like the OS. Standard sidebar, native lists, toolbars, inspector. Personality via clarity, not chrome. |
| Dropdown role | **Glance + handoff** | Short status rows (Wi-Fi/Battery-menu DNA); every row deep-links into the window. All depth lives in the window. |
| Detail model | **Trailing inspector** (`.inspector`) | Non-modal; selection drives it; arrow keys browse while the inspector follows. Freeform/Shortcuts pattern. Retires the per-item modal sheets. |
| Sidebar IA | **Grouped source list + Overview landing** | Overview on top, then PRIVACY (Permissions, Launch Agents, Background Items) and ACTIVITY (Changes with count badge, Stale Apps). |

## The workflow spine

```
menu-bar icon (idle / ● recording / attention)
   → dropdown (one-line answers: "3 changes", "Zoom using mic")
      → click any row = deep link
         → window opens at that section, relevant item pre-selected
            → inspector shows detail + read-only actions
               → mark reviewed / dismiss → counts decrement everywhere
```

State flows outward to the glance surfaces; clicks flow inward to the inspector. No dead ends: every surfaced number is a navigation affordance.

### Deep-link model

A small routing value (e.g. `AppRoute`) describes every destination: `.overview`, `.section(ScannerDomain)`, `.changes`, `.staleApps`, optionally carrying a pre-selected item identifier. The dropdown emits routes; the window consumes them (select sidebar section, set list selection, present inspector). Routing is plain testable logic in the ViewModel layer — no view code required to verify it.

---

## Surface 1 — Menu-bar icon

- Template SF Symbol rendering (light/dark safe on Tahoe's transparent menu bar).
- Three states: **normal** · **recording** (dot/fill variant while mic/cam in use, driven by the existing `MediaUseObserverCMIO`) · **attention** (subtle variant when unreviewed changes or new risks exist).
- No badge text in the menu bar itself; counts live in the dropdown.

## Surface 2 — Dropdown (glance + handoff)

Fixed-shape, short, scannable. Native menu styling: menu-row highlight, right-aligned key equivalents, separators. The Thread B Dynamic-Type clamp stays at the dropdown root.

1. **Header** — `Permission Pulse` + Live/Mock badge (mock-data marking is a hard rule and stays).
2. **Media row** (present only while active) — "Zoom is using the microphone ›" → routes to the app's row in Permissions.
3. **Status rows** — each is a deep link:
   - "⚠ N changes since yesterday ›" → Changes
   - "⧗ N stale permissions ›" → Stale Apps
   - "✓ N apps · no new risks ›" (or the risk-summary line when risks exist) → Overview
4. **Footer rows** — Open Permission Pulse ⌘O · Rescan Now ⌘R · Settings… ⌘, · About · Quit ⌘Q.

The current overview StatRows / recent ActivityRows / AttentionBanner are retired from the dropdown; their content moves to the window's Overview page.

## Surface 3 — Detail window

`NavigationSplitView` with a source-list sidebar and a trailing inspector.

### Sidebar

- Search field pinned at top (`.searchable(placement: .sidebar)`, System Settings placement) — filters the current section's list.
- `Overview` as a top-level item, then groups: **PRIVACY** (Permissions, Launch Agents, Background Items) and **ACTIVITY** (Changes — with unreviewed-count badge — and Stale Apps).
- Selection uses the system accent (Thread B behavior preserved). ⌘1–⌘6 jump to sections in sidebar order.

### Toolbar

Unified-title toolbar: **Rescan** (⟳, existing F3 behavior), **Export** (⤓ menu: JSON / Markdown, existing F1 behavior), **inspector toggle** (⌥⌘I). (Search lives in the sidebar, above.) Mock badge appears in the toolbar area when any scanner is mock.

### Overview page (landing)

Native grouped layout, top to bottom:
- **Needs attention** — risk items and unreviewed-change summary rows; each deep-links to its section/item.
- **Domain counts** — one row per domain (apps with permissions, launch agents, background items), each deep-linking.
- **Footer** — last scan time + data-source status (FDA granted/missing, schema state).

### Section pages (Permissions, Launch Agents, Background Items)

- Plain native lists (inset-grouped): icon tile, primary name, secondary detail (services / program / kind), trailing indicators (⚠ risk, ⧗ stale).
- **Selection drives the inspector** — single click selects and shows the inspector; ↑↓ arrows move selection and the inspector follows. No chevrons, no modal presentation.
- Type-to-select works (free with native `List` + selection).

### Inspector

One shared scaffold, one variant per item type (TCC app, launch agent, background item):
- **Header** — icon, display name, bundle ID / identifier.
- **Detail sections** — permissions with granted/denied state; plist details (program, args, run conditions); BTM status — whatever the type provides today via its sheet.
- **Provenance** — path, last-used (existing `LastUsedProbeHybrid` data).
- **Actions** (read-only, all existing behaviors): Reveal in Finder · Copy `tccutil` reset command · Open System Settings pane.

Changes and Stale rows drive the same inspector, resolved to the underlying app/agent when it still exists; when it doesn't (e.g. removed app), a minimal change-detail variant shows what changed and when.

### Changes page

- Grouped by day; semantic +/− rows (added green / removed red — fixed status colors from Thread B).
- Context menu per row: Dismiss for session / Dismiss forever (existing dismissal stores).
- **Mark All Reviewed** action (existing behavior) in the page header area.

### Stale Apps page

- Rows show last-used date prominently; context menu: Skip forever (existing store).

### Empty and edge states

- `ContentUnavailableView` for: empty search results, empty sections, scan-in-progress.
- **FDA missing** becomes a full-page state on Permissions ("Grant Full Disk Access…" button) → launches the FDA walkthrough, which remains a guided modal sheet (one-shot setup dialog — modality is appropriate there), restyled native.
- `SchemaMismatchBanner` persists as a native banner above the affected list.

### Retired

`AppPermissionsDetailSheet`, `LaunchAgentDetailSheet`, `BackgroundItemDetailSheet` (→ inspector). `ResetConfirmationSheet` (→ native confirmation alert in Settings). `DetailSheetStyle` folds into the inspector scaffold.

## Surface 4 — Settings window

Native Settings presentation (toolbar-tab pattern) **inside the existing `Window(id:)` + zero-size `WindowGroup` trampoline** — the Tahoe `openSettings` workaround is mechanism, not presentation; it stays exactly as is.

| Tab | Contents |
|---|---|
| **General** | Launch at login (`SMAppService`), menu-bar behavior |
| **Scanning** | Snapshot retention days, stale threshold days |
| **Digest** | Weekly digest toggle, weekday + time pickers |
| **Data** | Export current state, Reset All Data (native destructive confirmation alert) |

All tabs use standard grouped `Form`. Existing `PreferencesStore` keys and validation ranges unchanged.

## Surface 5 — Welcome window

Apple "What's New"-style onboarding: app icon, headline, 3–4 feature rows with SF Symbols and short descriptions, then a single FDA explanation step ("why we ask, what we never do" — honesty copy preserved), Continue → done. Re-openable from the menu bar (existing behavior). `hasSeenWelcome` key unchanged.

## Surface 6 — About & one-shot dialogs

- About stays a small native panel (existing AppKit drop, unchanged mechanism).
- Reset-all-data confirmation becomes a standard destructive alert.

## Motion & polish

- Inspector slide-in/out (system-provided), count badges animate via `.contentTransition(.numericText)`, list diffs animate on rescan.
- All motion respects Reduce Motion; all surfaces keep Thread B's Reduce Transparency handling.
- Hover/focus/selection states come from real native `List`/controls — no custom re-implementations.
- Window frame restoration preserved (existing autosave behavior).

## Technical shape

- **APIs:** `NavigationSplitView`, `.inspector`, `.searchable`, `ContentUnavailableView` — all native, fine on the Tahoe (26) target. No new dependencies.
- **Thread B tokens remain the styling vocabulary**; this thread changes structure, not tokens. Badge-contrast and clamp tests keep passing.
- **ViewModel layer:** `AppViewModel` gains route handling + list selection state; dropdown rows emit routes via `openWindow(id:)` + route assignment. MainActor-by-default; no new concurrency surface.
- **Mock-vs-real discipline:** Mock badge visible in dropdown header and window toolbar whenever any scanner is mock.
- **Localization:** every new string through `String(localized:)`.

## Verification

- Existing 213 package + app-target tests stay green throughout (behavioral guard).
- **New unit tests:** route model (dropdown row → expected route → expected sidebar section/selection); inspector item-resolution logic (change row → underlying item or fallback).
- `#Preview`s per surface in light + dark.
- Smoke-test checklist (`scripts/smoke-test.sh` HUMAN-ONLY STEPS) gains a Thread C section: deep-link from every dropdown row, arrow-key + inspector follow, ⌘1–⌘6, empty states, FDA full-page state, Settings tabs, Welcome flow, both appearances, Dynamic Type, Reduce Transparency/Motion.
- Manual VoiceOver spot-check on the new navigation (sidebar groups, inspector focus order) — extends the pending W4 pass.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| `.inspector` quirks inside a `MenuBarExtra`-owned `Window(id:)` scene on Tahoe | Prototype the window skeleton first (rollout step 1); if `.inspector` misbehaves, fall back to a hand-rolled trailing `HSplitView` panel with identical semantics. |
| Deep-link timing (window not yet open when route arrives) | Route is state on the ViewModel, consumed on window appear — not a fire-and-forget call. Unit-tested. |
| Sheet-to-inspector content overflow (sheets had room; inspector is ~280–320pt) | Inspector content is scrollable; provenance/actions designed for narrow width; verified per-type in the visual checklist. |
| Losing Thread A behaviors in the move (dismissals, mark-reviewed, export, rescan) | Each behavior is named in this spec and mapped to its new home; existing tests cover the underlying stores/logic. |
| Type-checker explosion on big new views | Extract subviews aggressively (project rule); one surface per task. |

## Rollout order

1. **Window skeleton** — `NavigationSplitView` + grouped sidebar + route model + inspector scaffold (prototype risk #1 here).
2. **Section pages + inspectors** — Permissions, Launch Agents, Background Items; retire the three item sheets.
3. **Overview page** + Changes + Stale Apps pages.
4. **Dropdown rebuild** (glance + handoff, deep links).
5. **Settings + Welcome + dialogs** restyle.
6. **Polish pass** — motion, empty states, keyboard, smoke-test checklist, VoiceOver spot-check.

## Success criteria

- Every dropdown row deep-links to the correct window section with the correct item selected.
- No modal sheet remains for item detail; inspector follows list selection, including via arrow keys.
- Sidebar shows grouped sections with a live unreviewed-count badge on Changes.
- Overview page answers "am I okay?" with every row clickable.
- Settings presents as native toolbar tabs; Welcome as native onboarding.
- All existing tests green + new route/resolution tests green.
- Smoke-test Thread C visual checklist passes in light/dark, Dynamic Type, Reduce Transparency/Motion.
