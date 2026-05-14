# 09 — Roadmap

Honest, not aspirational. Each milestone is a single shipped binary on GitHub Releases.

## v0.1.0 — Scaffold (✅ done 2026-05-13, not yet tagged)

- Xcode project + four SwiftPM packages with smoke tests passing. ✅
- Menu-bar icon and detail window render mock data clearly labeled as mock. ✅
- CI green (build + test) on macOS-latest, both SwiftPM jobs and xcodebuild app job. ✅
- No real scanners wired yet (deliberate). ✅

The `v0.1.0` git tag will be cut at the same time as the v0.2.0 release, since the scaffold milestone has no user-facing artifact worth distributing on its own.

## v0.2.0 — First real scanner (✅ done 2026-05-13)

- `LaunchAgentScannerFS` implemented and shipping real data into the UI. ✅
- Snapshot store has a `launch_agents` table + diff API (not yet wired into the UI; What Changed view lands in v0.5.0). ✅
- Per-section badges: Launch Agents shows "Live", Permissions still shows "Mock" pending v0.3.0. ✅

See `docs/10-first-slice.md` for the spec.

## v0.3.0 — TCC scanner (✅ done 2026-05-14)

- `TCCScannerSQLite` implemented (reads user + system TCC.db). ✅
- 16-case `PermissionService` enum with TCC-service-string mapping. ✅
- Permission Inbox renders real TCC data when FDA is granted. ✅

See `docs/11-tcc-slice.md` for the spec.

## v0.3.1 — FDA UX closure (✅ done 2026-05-14)

- Welcome window on first launch with deep-link into System Settings → Full Disk Access. ✅
- Empty-state CTA in the Permissions section when FDA is denied. ✅
- Schema-mismatch banner at top of detail window. ✅
- Menu-bar attention row when FDA is denied or schema unrecognized. ✅
- Refresh toolbar button on the detail window. ✅

See `docs/12-fda-ux-slice.md` for the spec.

## v0.4.0 — BTM scanner (✅ done 2026-05-14)

- `BTMScannerDirect` reads `BackgroundItems-v*.btm` via `NSKeyedUnarchiver`. ✅
- `BackgroundItemsSection` renders enabled and disabled login items / helpers. ✅
- Generalized `PermissionsEmptyStateView` + `SchemaMismatchBanner` across TCC and BTM domains. ✅
- Menu-bar attention row rolls TCC + BTM FDA denials into one CTA. ✅
- `BTMScannerSFL` fallback (sudo-required, manual user step) deferred.

See `docs/13-btm-slice.md` for the spec.

## v0.4.1 — Mic/cam current use + menu-bar icon

- `MediaUseScannerAVFoundation` for live observation of mic/cam usage.
- State-driven `MenuBarExtra` icon overhaul (orange dot for mic, green for camera, mixed when both).

## v0.5.0 — What Changed and Stale review

- Diff queries against the snapshot store.
- "What Changed" view with yesterday and last-week tabs.
- Stale App Review.

## v0.6.0 — One-click fixes and risk explanations

- Per-permission deep links into System Settings (verified on Sonoma + Sequoia + Tahoe).
- Risk Explanations content (static, ships with the app).

## v0.7.0 — Polish, weekly digest, preferences

- Weekly notification.
- Preferences pane (digest on/off, snapshot retention, "Reset all data").

## v1.0.0 — First public release

- All v1 scope items shipped and tested.
- README screenshots taken.
- GitHub Releases announcement post.
- Optionally Show HN / Product Hunt.

## v1.1 (post-launch)

- Search and filter in the Inbox.
- Export to JSON/Markdown.
- Configurable stale-app threshold.
- Homebrew tap.
- Localization for at least one non-English locale.

## v2 (speculative)

- Sparkle 2 auto-updater (requires Developer ID — separate decision).
- Notarized signed builds (requires Developer ID).
- Per-Mac historical comparison (still local-only — no cloud).
- More scanners as APIs become available.

## Out of plan, ever

- iCloud sync of snapshot data.
- Cloud telemetry of any kind.
- Mac App Store version.
- Removing or modifying any permission programmatically.
