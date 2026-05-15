# 16 — Seventh slice: one-click fixes and risk explanations

**Status:** Implemented v0.6.0 — 2026-05-15.

## Why this slice

- v0.5.0 closed the recurrence story (snapshots, diffs, stale review). The Permissions section still answered only "what have I granted?" — it didn't tell the user *what each grant actually means in practice*, and revoking required hunting through System Settings menus. v0.6.0 closes that gap on both fronts.
- Risk Explanations and deep links serve the same workflow — "should I revoke this, and how?" — so they ship as one slice rather than two. The user opens a permission row, reads what the grant lets the app do, and either dismisses the sheet or clicks Open in Settings to land on the exact pane they need.
- Future slices (v0.7.0 weekly digest, configurable thresholds) build on this foundation — a digest that notifies "you have 3 stale apps with grants" is only actionable if the user has a one-click path to review each.

## Preconditions verified

- All sixteen `Privacy_*` URL anchors verified to open the correct Settings pane on macOS Tahoe (26). The `x-apple.systempreferences:com.apple.preference.security?Privacy_<Anchor>` URL form has been stable since Big Sur, but the anchor names have drifted across macOS versions historically. If a future macOS renames one, `NSWorkspace.shared.open` falls back to the top-level Privacy pane rather than failing — graceful degradation.
- `Identifiable` conformance on `PermissionGrant` does not collide with any existing protocol use in `PermissionsCore`, `PermissionsScanners`, or `PermissionsStore`. Moving the conformance into `PermissionsCore` avoids the retroactive-conformance warning Swift 6 emits when a downstream module extends an upstream type.

## What shipped

1. **`PermissionService.riskDescription`** in `PermissionsCore`. Sixteen TCC services, each with a two-to-three-sentence plain-English explanation of what the grant lets the holding app do. No jargon, no scaremongering — just "Screen Recording lets the app capture anything on your displays — including video-call content and any text on screen." Tested for non-empty, ≥60 chars (catches stub TODOs), and distinct across services (catches paste errors).
2. **`SystemSettingsLink.open(for: PermissionService)`** in `PermissionsUI`. Per-service deep link mapping for all sixteen services, e.g. `Privacy_ScreenCapture` for screen recording, `Privacy_AllFiles` for FDA, `Privacy_ListenEvent` for input monitoring. The legacy `openFullDiskAccess()` is preserved as a thin wrapper around the new entry point. `openPrivacyPane()` exposes the top-level fallback for callers that don't have a specific service. Tested for non-nil URLs across every service, distinct anchors, and a pinned FDA anchor.
3. **`PermissionDetailSheet`** in `PermissionsUI`. Triggered by tapping any row in `PermissionsSection`. Layout matches the v0.4.1 `FDAGrantSheet`:
   - **Header**: `NSWorkspace.shared.icon(forFile:)` for the app, plus display name and service name.
   - **Risk body**: the `riskDescription` paragraph inside a soft `.regularMaterial` card.
   - **Meta**: bundle ID, automation target (when `service == .automation`), and last-modified timestamp.
   - **Footer**: Close + "Open in Settings" buttons. The Settings button deep-links to the right pane via `SystemSettingsLink.open(for:)` and dismisses the sheet.
4. **Tappable `PermissionsSection` rows.** Each row becomes a `Button(style: .plain)` with a `Rectangle().contentShape` so the entire row registers taps. A small `info.circle` glyph on the trailing edge of each row signals interactivity without crowding the data. The sheet is driven by local `@State` rather than view-model state — the trigger lives in-view and doesn't need to be exposed across modules.
5. **`PermissionGrant: Identifiable`** in `PermissionsCore`. Identity = `"<service>|<bundleID>|<automationTarget>"` — same key the diff engine uses. Enables the `.sheet(item:)` binding to re-fire correctly when a different row of the same service is selected.
6. **`AppIconResolver`** in `PermissionsUI`. TCC's `client_type = 0` rows store only a bundle ID, so the scanner often leaves `AppIdentity.bundlePath` nil — without a path the UI defaulted to the dashed-app placeholder even for installed apps. The resolver tries `bundlePath` (if the file exists), then `NSWorkspace.urlForApplication(withBundleIdentifier:)`, then falls back to `app.dashed`. Used by `PermissionDetailSheet` and `StaleAppsTabView`.
7. **`TappableRow`** in `PermissionsUI`. Reusable row wrapper with hover-state cursor (`NSCursor.pointingHand` push/pop), a faint `Color.primary.opacity(0.06)` background highlight on hover and press, and a trailing `chevron.right` glyph indicating "tap for detail." Parent containers gain `.clipShape(RoundedRectangle(...))` so the hover bg doesn't bleed past the rounded card corners. Replaces the ambiguous `info.circle` glyph that the previous draft used.
8. **`LaunchAgentDetailSheet`** in `PermissionsUI`. Launch Agents are property-list-defined background helpers, not apps — the sheet shows the launchd properties (program, arguments, `runAtLoad`, `keepAlive`) plus the source-directory path with a "Reveal in Finder" button that selects `<sourceDirectory>/<label>.plist` if present, else the parent folder. No System Settings deep-link is appropriate; launch agents aren't surfaced there.
9. **`BackgroundItemDetailSheet`** in `PermissionsUI`. Header icon is resolved through `NSWorkspace.urlForApplication(withBundleIdentifier:)` when a `bundleIdentifier` is available, falling back to a per-type SF Symbol (`app.fill` / `gearshape.2.fill` / `folder.fill` / `questionmark.circle.fill`). Properties card shows type / scope / identifier / bundle ID / team ID / modification date / parent. Footer "Open Login Items" deep-links into System Settings → General → Login Items via `SystemSettingsLink.openLoginItems()`.
10. **All three sections use `TappableRow`** — Permissions, Launch Agents, Background Items. Consistent hover behavior, consistent chevron affordance.

## Data flow

```
User taps a row in PermissionsSection
        │
        ▼
selectedGrant: PermissionGrant?    ← local @State
        │
        ▼
.sheet(item: $selectedGrant) { PermissionDetailSheet(grant:) }
        │
        ├─→ riskDescription paragraph rendered from PermissionsCore content
        │
        └─→ "Open in Settings" → SystemSettingsLink.open(for: grant.service)
                                   → NSWorkspace.shared.open(URL)
                                   → System Settings → Privacy & Security → <pane>
```

## Files touched

- **New:**
  - `Packages/PermissionsCore/Sources/PermissionsCore/PermissionRiskDescription.swift`
  - `Packages/PermissionsCore/Tests/PermissionsCoreTests/PermissionRiskDescriptionTests.swift`
  - `Packages/PermissionsUI/Sources/PermissionsUI/PermissionDetailSheet.swift`
  - `Packages/PermissionsUI/Sources/PermissionsUI/AppIconResolver.swift`
  - `Packages/PermissionsUI/Sources/PermissionsUI/TappableRow.swift`
  - `Packages/PermissionsUI/Sources/PermissionsUI/LaunchAgentDetailSheet.swift`
  - `Packages/PermissionsUI/Sources/PermissionsUI/BackgroundItemDetailSheet.swift`
  - `Packages/PermissionsUI/Tests/PermissionsUITests/SystemSettingsLinkTests.swift`
  - `docs/16-one-click-fixes-and-risk-slice.md` (this file)

- **Modified:**
  - `Packages/PermissionsCore/Sources/PermissionsCore/PermissionGrant.swift` — added `Identifiable` conformance with `id` = identity key.
  - `Packages/PermissionsCore/Sources/PermissionsCore/LaunchAgentItem.swift` — added `Identifiable` (id = `"<source>|<label>"`).
  - `Packages/PermissionsCore/Sources/PermissionsCore/BTMItem.swift` — added `Identifiable` (id = `identifier`).
  - `Packages/PermissionsUI/Sources/PermissionsUI/SystemSettingsLink.swift` — per-service deep links + top-level Privacy pane fallback + Login Items deep link.
  - `Packages/PermissionsUI/Sources/PermissionsUI/PermissionsSection.swift` — rows wrapped in `TappableRow` with chevron + hover; `.sheet(item:)` binding.
  - `Packages/PermissionsUI/Sources/PermissionsUI/LaunchAgentsSection.swift` — rows wrapped in `TappableRow`; `.sheet(item:)` to `LaunchAgentDetailSheet`.
  - `Packages/PermissionsUI/Sources/PermissionsUI/BackgroundItemsSection.swift` — rows wrapped in `TappableRow` with the existing `DispositionBadge` in the trailing slot; `.sheet(item:)` to `BackgroundItemDetailSheet`.
  - `Packages/PermissionsUI/Sources/PermissionsUI/StaleAppsTabView.swift` — switched to `AppIconResolver` so installed apps with no `bundlePath` still show their real icon.
  - `docs/09-roadmap.md` — mark v0.6.0 done.

## Test coverage

- `PermissionRiskDescriptionTests` — 3 cases (non-empty, ≥60 chars, distinct across services).
- `SystemSettingsLinkTests` — 4 cases (every service produces a Privacy_* URL, distinct anchors, FDA pinned, fallback URL).

Test counts: 115 (v0.5.0) → 122 (v0.6.0), +7 net.

## Risks (Tahoe-specific + slice-specific)

| # | Risk | Mitigation |
|---|---|---|
| 1 | **`Privacy_*` anchor drift across macOS versions.** Apple has renamed some anchors silently in the past. | If an anchor is no longer recognized, System Settings opens to the top-level Privacy pane rather than failing. Anchors documented in the source for easy patching. `openPrivacyPane()` is exposed as a manual fallback. Sonoma + Sequoia verification deferred until cross-version testing infra exists. |
| 2 | **`Identifiable` retroactive conformance.** Adding it in `PermissionsUI` would trigger a Swift 6 warning. | Moved into `PermissionsCore` (the owning module). Future-proof if Swift adopts stricter retroactive-conformance rules. |
| 3 | **Sheet over a long Permissions list.** Tapping a row near the bottom of the list scrolls the underlying view when the sheet dismisses. | Default `.sheet` behavior on macOS; minor visual artifact, no functional impact. Deferred. |
| 4 | **Information-density on each row.** Adding the `info.circle` glyph slightly increases visual noise. | The glyph is `.foregroundStyle(.tertiary)` so it recedes; signals interactivity without competing with the primary text. |
| 5 | **Risk-description tone drift over time.** Translated locales or future copy edits could make some services sound more or less scary than others, biasing user decisions. | Single-source paragraphs in `PermissionRiskDescription.swift` keep voice consistent. The `riskDescriptionsAreDistinct` test catches accidental duplication; the ≥60-char floor catches stub TODOs. |

## Deferred to later slices

- **Sonoma + Sequoia anchor verification.** v0.6.x candidate when cross-version testing is set up (a VM matrix, probably).
- **One-click revoke from within Permission Pulse.** Apple does not expose programmatic TCC revocation to unsigned apps; the user must complete the toggle in System Settings. Won't change in v1.
- **Per-row "I trust this app" mute.** Once a user has reviewed a grant and decided to keep it, dismissing the same row from future review prompts. v0.7.0 candidate.
- **Sparkline of grant age in the detail sheet** — visual on how long the user has held a permission. Speculative; v1.x.
- **Risk content for `kTCCServiceFileProviderDomain` / `kTCCServiceLiverpool`** and the other `knownSkipped` services — out of scope, we skip these intentionally at the scanner.

## Done means

- All five package suites + the app target test bundle pass — 122 tests total.
- `xcodebuild -scheme PermissionPulse -configuration Release build` succeeds; resulting `.app` has `CFBundleShortVersionString = 0.6.0` and `CFBundleVersion = 8`.
- Launch the app on Tahoe. Click any row in the Permissions section. The detail sheet opens with the app icon, name, service, the corresponding risk paragraph, bundle ID, last-modified date, and Close + "Open in Settings" buttons.
- Click "Open in Settings" inside the sheet. System Settings opens to the Privacy & Security pane for that specific service (Microphone, Camera, Screen Recording, etc). The sheet dismisses.
- All v0.5.0 surfaces unchanged: snapshot writes, What Changed mode, Stale apps tab, menu-bar icon priority including `bell.badge.fill` for unreviewed changes.
