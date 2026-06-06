# Thread A — App Quality & Completeness Audit + Remediation

**Date:** 2026-06-06
**Status:** Design — pending user review
**Baseline:** v0.7.1
**Scope decision:** *App-only* quality (option C = exhaustive). CI, release automation, packaging, and the macOS-floor/infra questions are **out of scope** for this thread. UI styling / design-system work is **Thread B**.

## Goal

Reach a state where the app is *confident, well-rounded, and high quality* on its own terms: the data it shows is **correct**, it **fails loudly** instead of silently, it is a **well-behaved Mac accessibility citizen**, its **flows and states** hold together, and it is **feature-complete** for a read-only permission-hygiene tool — without violating any project hard rule.

This spec is the synthesis of five parallel read-only audits run 2026-06-06 against v0.7.1: functional correctness/data-fidelity, robustness/silent-failure, UX states + localization, accessibility, and feature completeness.

## Cross-cutting theme

The dominant quality risk is **silent failure / misleading-empty**: for a tool whose entire value is trustworthy accuracy, the worst failure mode is one that looks identical to "all clear." Three independent audits hit this. Eliminating it is the spine of P0.

## Hard-rule guardrails (reaffirmed — apply to every item)

- **Read-only.** No item may write to TCC.db, BTM, LaunchAgents, or any system file. "Revoke"/"disable" features may only *display* instructions or *copy* a command — never execute. Export writes only to the user's chosen location.
- No `sudo` / privilege escalation, no kernel/system extensions.
- No telemetry, no paid gating, no cloud.
- Preserve "under-flag, never over-flag": where the app deliberately skips ambiguous data, keep that — but make sure the user can tell "skipped/failed" from "genuinely nothing."
- All new user-facing strings via `String(localized:)`.

---

## Workstream 1 — Trust & correctness (P0)

The must-fix set. These make the app either *wrong* or *silently broken*.

| ID | Problem | Fix approach | Primary files | Sev | Eff |
|----|---------|--------------|---------------|-----|-----|
| C1 | "Yesterday" diff baseline uses rolling `now − 24h`, but snapshots write once per **calendar day** → the diff intermittently compares against the wrong snapshot or shows "nothing yet" depending on time of day. Week window has the same fractional-day edge. | Compute the diff cutoffs on **calendar-day boundaries** (start-of-yesterday, start-of-7-days-ago) to match the once-per-day write cadence. | `PermissionPulse/PermissionPulse/SnapshotCoordinator.swift` (cutoffs ~138-148, day guard ~66) | HIGH | M |
| C2 | If the snapshot store fails to open, or a diff query throws, Recent Changes / Stale Apps show the "come back tomorrow" empty state **forever** — broken looks like first-launch. | Introduce explicit *unavailable* / *error* states distinct from *empty*. Surface a store-init failure to the user (reuse the `SchemaMismatchBanner` visual pattern); add a `diffQueryError`/`snapshotUnavailable` signal on `AppViewModel` and render a real error state in `DiffTabView` / Stale Apps. | `PermissionPulseApp.swift` (~122-138), `SnapshotCoordinator.swift` (computeDiffs ~146-167), `AppViewModel.swift`, `DiffTabView.swift`, `StaleAppsTabView.swift` | HIGH | M |
| C3 | Launch Agent scan errors are structurally invisible — `LaunchAgentScanResult` has no error field, so a failed scan reads as "no launch agents." | Add `error: ScannerError?` to `LaunchAgentScanResult`; add `viewModel.launchAgentScanError`; thread to the section + menu-bar attention banner exactly like TCC/BTM. Raise directory-level read failures from `.debug` to `.error` (keep per-plist skips at `.debug`). | `ScanCoordinator.swift` (~85-121), `AppViewModel.swift`, `LaunchAgentScannerFS.swift` (~66-103), `LaunchAgentsSection.swift`, `MenuBarContentView.swift` (attention banner) | HIGH | M |
| C4 | "Reset all data" can silently no-op: if the path lookup fails, the sheet closes and nothing happens, no feedback. A failed store re-init also leaves the coordinator pointing at a deleted DB. | Convert the `try?` in `performReset` to `do/catch` + user-visible error. On re-init failure, explicitly `nil` the `snapshotCoordinator` so no writes target the deleted path, and surface the failure. | `PermissionPulseApp.swift` (~197), `ResetAllDataService.swift` (~65-71) | HIGH | S |
| C5 | Every TCC `DatabaseError` (corrupt / locked / disk-full) is mapped to "grant Full Disk Access" — wrong advice that sends users on a wild goose chase when FDA is already granted. | Map by SQLite result code: `SQLITE_AUTH`/`SQLITE_NOPERM` → `permissionDenied`; `SQLITE_CORRUPT` → `schemaMismatch`/"database appears corrupt"; `SQLITE_BUSY` → a "temporarily unavailable, try again" message. | `TCCScannerSQLite.swift` (~243-247), possibly a new `ScannerError` case | HIGH | M |
| C6 | If CoreMediaIO/CoreAudio listener registration fails, the device is dropped and the menu-bar dot silently reports "not in use" — a false negative on the headline real-time feature. | Track failed-registration count; expose a "media monitoring may be incomplete" signal so the UI/menu can indicate uncertainty rather than asserting "not in use." At minimum, surface the partial-failure state; don't claim a clean negative. | `MediaUseObserverCMIO.swift` (~65-93), `AppViewModel.swift` | HIGH | M |
| C7 | Stale Apps copy is hardcoded "haven't used in 90+ days" in two places, but the threshold is user-configurable (30–365) since v0.7.0 — the text lies after the user changes it. | Interpolate `preferencesStore.staleThresholdDays` into the copy. | `StaleAppsTabView.swift` (~21), `DetailWindowView.swift` (~564) | MEDIUM | S |

**Tests:** C1 gets explicit boundary tests (snapshot taken late yesterday vs. early-morning open; the existing test seeds `-36h` and sidesteps the bug). C2/C3/C4/C5/C6 get state/mapping tests asserting the *error* path produces a distinct visible signal, not the empty state.

---

## Workstream 2 — Data fidelity

The data is being silently merged or dropped. Fix the *capture* now; the deeper *representation* work (auth_value change tracking, sub-service granularity) stays the v0.8.x "model fidelity" slice and is referenced, not duplicated, here.

| ID | Problem | Fix approach | Primary files | Sev | Eff |
|----|---------|--------------|---------------|-----|-----|
| D1 | Path-only TCC grants (`client_type==1`, empty bundleID) collapse together: the **scanner dedupe key is path-aware but the diff/dismiss identity key is bundleID-only** (`filesAndFolders\|\|`). Two distinct CLI tools merge into one; dismissing one hides all. | Unify the identity key — make the store/diff/`DiffEntryKey` keys fall back to `bundlePath` exactly as the scanner does, so scanner and diff agree. | `SnapshotStore.swift` (~481-483), `DiffEntryKey.swift` (~17-20), cross-check `TCCScannerSQLite.swift` (~89-96) | HIGH | M |
| D2 | Limited Photos access (`auth_value==3`, now the default prompt option) is dropped entirely — only `==2` is stored. | Capture `auth_value` into `PermissionGrant` and store `>= 2` (allowed + limited), preserving the distinction losslessly. This is the data-capture half of the v0.8.x model-fidelity work; representing it as a "changed" diff is the v0.8.x slice. | `PermissionGrant.swift`, `TCCScannerSQLite.swift` (~184), `SnapshotStore.swift` (tcc schema) | MEDIUM | M |
| D3 | BTM disposition bitmask flattened to enabled/disabled; `disposition_raw` is always NULL, so the raw bits are unrecoverable. | Always preserve the raw value into `disposition_raw` even for known cases; keep the friendly enum for display. | `BTMScannerDirect.swift` (~169-172), `SnapshotStore.swift` (~522-528) | MEDIUM | S |
| D4 | LaunchAgent `KeepAlive`-as-dictionary silently decodes to `false`; the `Disabled` key isn't read at all (a disabled agent looks active). | Decode `KeepAlive` as bool *or* dictionary (treat any dict form as "conditional keep-alive = true/observed"); decode and surface `Disabled`. Update the test that currently pins the lossy behavior. | `LaunchAgentScannerFS.swift` (~128-130), `LaunchAgentItem.swift`, tests | MEDIUM | S |
| D5 | Snapshot date columns declared `.double` but GRDB serializes `Date` as TEXT — comparisons work only by lucky fixed-width formatting; a numeric writer would silently corrupt ordering/pruning. | Either correct the column type to match TEXT storage, or store explicit epoch doubles and read them back; add a guard test pinning the round-trip + ordering. | `SnapshotStore.swift` (~30/55/73, ordering ~198/209/220) | LOW | S |

**Note on the v0.8.x boundary:** D2 captures `auth_value` so nothing is lost; rendering granted→denied/limited as a *changed* diff row (instead of remove+add) and `.filesAndFolders` sub-service granularity remain the separately-tracked **v0.8.x model-fidelity slice** (`docs/09-roadmap.md`). This spec deliberately does the capture, not the representation, to avoid ballooning.

---

## Workstream 3 — Robustness / no silent failure

Remaining swallowed-error paths beyond P0.

| ID | Problem | Fix | Files | Sev | Eff |
|----|---------|-----|-------|-----|-----|
| R1 | `pruneSnapshots` is `try?` — failures discarded, DB can grow unbounded silently. | `do/catch` + `.error` log. | `SnapshotCoordinator.swift` (~87) | MEDIUM | S |
| R2 | No guard against a user Refresh racing the initial launch scan → possible duplicate snapshot rows (the day-guard reads UserDefaults the first scan hasn't written yet). | `guard !viewModel.scanInProgress else { return }` at the top of `rescan()`. | `PermissionPulseApp.swift` (~157-162) | MEDIUM | S |
| R3 | Unknown enum `kind` on read throws → cascades to nil diff (same UI as "no data"). | Resolved by C2's error state; ensure the unknown-kind throw is classified as an error state, not empty. | `SnapshotStore.swift` (~512-555) | MEDIUM | S |
| R4 | `mdls` abnormal kill can leak a `CheckedContinuation` (mitigated by the 2s timeout). | Wrap in `withTaskCancellationHandler` that terminates the process and always resumes the continuation. | `LastUsedProbeHybrid.swift` (~54-82) | LOW | M |

---

## Workstream 4 — Accessibility (semantic)

Behavioral accessibility = Thread A. Visual accessibility (contrast, Dynamic Type scaling, transparency) = Thread B.

| ID | Problem | Fix | Files | Sev | Eff |
|----|---------|-----|-------|-----|-----|
| A1 | Menu-bar icon encodes 4 states by symbol swap only; VoiceOver can't read the state. | Add `menuBarAccessibilityLabel` to `AppViewModel`; set `statusItem.button?.setAccessibilityLabel(...)` wherever the symbol is applied. | `AppViewModel.swift` (~100-111), App/MenuBarExtra call site | HIGH | S |
| A2 | Dismiss/snooze and skip menus use bare `ellipsis.circle` with `.menuIndicator(.hidden)` and no label → invisible to VoiceOver; the core diff action is unreachable. | Add `.accessibilityLabel`/`.accessibilityHint` to the `Menu`; reconsider hiding the indicator. | `ChangeRow.swift` (~30-44), `StaleAppsTabView.swift` (~89-98) | HIGH | S |
| A3 | Custom selected state (sidebar, Preferences tabs) not announced; keyboard/VoiceOver users can't tell which view is active. | `.accessibilityAddTraits(.isSelected)` (and remove when deselected); for the Preferences tab bar, prefer a segmented `Picker` for free semantics. | `DetailWindowView.swift` (sidebar ~254-335), `PreferencesWindowView.swift` (~57-89) | HIGH | S–M |
| A4 | Refresh spinner uses `repeatForever` rotation, not gated on Reduce Motion (vestibular trigger). | Gate animation on `@Environment(\.accessibilityReduceMotion)`. | `DetailWindowView.swift` (~620-632) | HIGH | S |
| A5 | **Decorative-icon / grouping sweep** (one pass): ~16 places announce raw SF Symbol names or split rows into noisy focus stops. | Add `.accessibilityHidden(true)` to decorative `Image(systemName:)`; `.accessibilityElement(children: .combine)` on `StatRow`; `.accessibilityAddTraits(.isHeader)` on section headers; `.accessibilityHint` on service pills. | `TappableRow.swift`, `MenuBarContentView.swift`, `DetailSheetStyle.swift`, `WelcomeWindowView.swift`, `SchemaMismatchBanner.swift`, `PermissionsEmptyStateView.swift`, `DiffTabView.swift` | MEDIUM/LOW | S (batch) |

**Tests:** accessibility is largely verified by inspection + manual VoiceOver pass; add unit assertions where labels are computed (e.g. `menuBarAccessibilityLabel` cases).

---

## Workstream 5 — UX states & flows

| ID | Problem | Fix | Files | Sev | Eff |
|----|---------|-----|-------|-----|-----|
| U1 | **No loading/scanning state** — `scanInProgress` only gates the Reset button. Mid-scan, the three inventory lists show their empty states, indistinguishable from a finished empty result. | Drive a skeleton/`ProgressView` on the three sections + a "Scanning…" menu-bar header from `scanInProgress`; wire `RefreshToolbarButton` to it too. | `MenuBarContentView.swift`, the three sections, `DetailWindowView.swift`, `AppViewModel.swift` | HIGH | M |
| U2 | "Dismiss" (forever) on a change is permanent, unlabeled, unconfirmed, no undo — unlike the stale-app "Skip forever" flow which explains itself. | Relabel "Dismiss forever"; match the stale-app pattern (explain the only un-dismiss path is Reset, or add undo). Add post-action feedback ("Snoozed 7 days · Undo") for dismiss/snooze/skip. | `ChangeRow.swift` (~30-44), `DiffTabView.swift`, `StaleAppsTabView.swift` | MEDIUM | M |
| U3 | FDA grant → relaunch recovery is messaging-only; if the user grants and returns without relaunching, the denied state persists with no nudge. | Add a "Quit & Reopen" affordance and/or a foreground re-check that detects the grant. | `PermissionsEmptyStateView.swift`, `MenuBarContentView.swift`, app | MEDIUM | M |
| U4 | Dismiss/snooze and skip actions are undiscoverable (low-prominence ellipsis). | A one-line hint on Recent Changes / Stale Apps pages, or a more visible affordance. | `DiffTabView.swift`, `StaleAppsTabView.swift` | MEDIUM | S |
| U5 | Welcome (incl. the "read-only / no network / never modifies" reassurance) is unreachable after "Skip for now." | A "Show Welcome / About" entry (menu or Preferences). | `MenuBarContentView.swift` or `PreferencesWindowView.swift`, app | LOW | S |
| U6 | Mock data sources are the initial default and the Mock badge is suppressed in the detail window (`showsHeader: false`) → a brief unmarked mock paint, mildly conflicting with the mock-vs-real discipline. | Gate detail content on first-scan-complete, or surface a Mock marker independent of `showsHeader`. | `AppViewModel.swift` (~56-58), `DetailWindowView.swift` | MEDIUM | S |

---

## Workstream 6 — Feature additions (read-only, in-scope)

| ID | Feature | Design | Read-only? | Files | Eff | Verdict |
|----|---------|--------|-----------|-------|-----|---------|
| F1 | **Export to JSON/Markdown** | "Export…" action → `NSSavePanel`; serialize current `[PermissionGrant]/[LaunchAgentItem]/[BTMItem]/[StaleApp]` (all `Sendable`/`Codable`) to JSON and a human Markdown report. Current-state snapshot (not full history). Already in scope §02. | Yes (user-chosen location, hard-rule-allowed) | new `PermissionsExport` util + a menu/toolbar action | M | BUILD |
| F2 | **Copy `tccutil reset` command** | In `AppPermissionsDetailSheet`, a "Copy revoke command" button → `NSPasteboard` with e.g. `tccutil reset ScreenCapture com.foo.bar`. Display/copy only, with a caption: "Permission Pulse won't run this — paste it into Terminal yourself." Needs a reverse `PermissionService` → tcc-service-name map. | Yes (copies text; user runs it) | `AppPermissionsDetailSheet.swift`, `PermissionService.swift` | S | BUILD |
| F3 | **Menu-bar "Rescan now"** | A `MenuRowButton` in the dropdown wired to the existing `ScanCoordinator.rescan()`; reflect `scanInProgress`. The dropdown is the primary surface and currently has no refresh. | Yes | `MenuBarContentView.swift`, app | S | BUILD |
| F4 | **Risk-summary line** | *Augment* (keep the raw counts, add one line below) the menu-bar overview with a hygiene signal: "3 apps hold Full Disk Access, 2 Input Monitoring," using the existing `riskSeverity` ranking (consider promoting it from `PermissionsUI` to `PermissionsCore` near `riskDescription`). One line, not a dashboard. | Yes | `MenuBarContentView.swift`, possibly `PermissionsCore` | S–M | BUILD |
| F5 | **"First seen by Permission Pulse" date** (the narrow, useful slice of a history view) | Compute earliest snapshot containing a grant/item via existing `SnapshotStore` queries; show alongside the macOS `last_modified` date (which resets on re-grant and is misleading alone). | Yes | `SnapshotStore.swift`, detail sheets | S–M | MAYBE (include per scope C) |
| F6 | **Reveal-in-Finder consistency** | Add "Reveal in Finder" to `AppPermissionsDetailSheet` and the stale-app row (stale apps already resolve `bundle_path`), matching LaunchAgents. | Yes (`activateFileViewerSelecting`) | `AppPermissionsDetailSheet.swift`, `StaleAppsTabView.swift` | S | MAYBE (include per scope C) |

**Each feature with new strings goes through `String(localized:)`. F1/F2/F4 add the first `NSSavePanel`/`NSPasteboard` usages — flag as `// AppKit: <reason>` per project rule.**

---

## Workstream 7 — Localization stragglers

~95% already localized. Remaining bare literals (all S):

- `MockBadge.swift` `"Mock"`, `LiveBadge.swift` `"Live"` — user-visible badges.
- `LaunchAgentDetailSheet.swift` `"Yes"/"No"` values; `ChangeRow.swift` `"on"/"off"` flip tokens.
- `AppPermissionsDetailSheet.swift` `"(unset)"` (inconsistent with the localized sibling in `LaunchAgentDetailSheet`).

---

## Out of scope / deferred (deliberate)

- **Thread B (UI/UX overhaul):** badge contrast (white-on-green fails 4.5:1), **Dynamic Type** (every font is a fixed `system(size:)` — systemic `L` fix), Reduce Transparency behavior of Vibrancy surfaces, and overall visual consistency. These are design-system decisions and are handed to the next thread.
- **v0.8.x model-fidelity slice (already roadmapped):** representing TCC `auth_value` changes as *changed* diff rows, `.filesAndFolders` sub-service granularity, notification-click → Recent Changes routing. (Workstream 2 does the *capture* that unblocks these.)
- **Infra:** CI coverage of app-target tests, release automation, macOS-floor decision — separate effort per the scope decision.
- **Anti-scope (won't build):** full snapshot-history timeline browser; TCC code-signing/trust inspection (drifts toward "is this app bad," which the project forbids).

## Suggested implementation sequencing (for the plan)

1. **P0 trust/correctness** (Workstream 1) — highest value, unblocks honest behavior.
2. **Fidelity + robustness** (2 + 3) — stop losing/merging data; close remaining silent paths.
3. **Accessibility sweep** (4) — mostly one batch pass.
4. **UX states** (5) — loading state first.
5. **Features** (6) — export, then the small read-only affordances.
6. **Localization** (7) — fold in alongside the views being touched.

## Testing strategy

- Swift Testing across packages (XCTest only where unavoidable). Every behavioral fix gets a regression test; specifically: C1 time-of-day boundary, C2/C3 error-vs-empty state, D1 identity-key unification, D2 auth_value capture, D4 KeepAlive-dict/Disabled, D5 date round-trip + ordering guard.
- Manual passes that can't be unit-tested: VoiceOver sweep (Workstream 4), the FDA grant→relaunch loop (U3), export round-trip (F1). Add these as checklist items to `scripts/smoke-test.sh`.
- Maintain the existing ~161 package + ~27 app-target test counts as a floor; expect a meaningful increase.
