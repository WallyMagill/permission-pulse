# 09 — Roadmap

Honest, not aspirational. Each milestone is a single shipped binary on GitHub Releases.

## v0.1.0 — Scaffold (✅ done 2026-05-13, never tagged)

- Xcode project + four SwiftPM packages with smoke tests passing. ✅
- Menu-bar icon and detail window render mock data clearly labeled as mock. ✅
- CI green (build + test) on macOS-latest, both SwiftPM jobs and xcodebuild app job. ✅
- No real scanners wired yet (deliberate). ✅

The scaffold milestone had no user-facing artifact worth distributing on its own, so a `v0.1.0` git tag was never cut — the first tag is `v0.2.0`, which folds in the scaffold.

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

## v0.4.1 — Mic/cam current use + menu-bar icon (✅ done 2026-05-14)

- `MediaUseObserverCMIO` (CoreMediaIO + CoreAudio, no entitlements) for live observation of mic/cam usage. ✅
- State-driven `MenuBarExtra` icon: error > both > camera > mic > idle. ✅
- `DetailWindowView` full ScrollView rewrite — fixes the v0.4.0 `List`-section badge + button rendering bugs. ✅
- `FDAGrantSheet` guided dialog before the System Settings deep-link. ✅

See `docs/14-mic-cam-icon-slice.md` for the spec.

## v0.5.0 — What Changed and Stale review (✅ done 2026-05-15)

- Migration v3: `tcc_grants` + `btm_items` tables under existing `snapshots` parent. `writeFullSnapshot` is the production entry. ✅
- `LaunchAgentsDiff` / `TCCGrantsDiff` / `BTMItemsDiff` carry added/removed/changed via `DomainChange<T>`. ✅
- `latestSnapshotID(atOrBefore:)` + `pruneSnapshots(olderThan:)` discovery + retention API. ✅
- `SnapshotCoordinator` sibling to `ScanCoordinator` / `MediaUseCoordinator`. Once-per-calendar-day write, 90-day retention. ✅
- `LastUsedProbe` protocol + `LastUsedProbeHybrid` (mdls → file mtime → skip). ✅
- What Changed window with Yesterday / Last week / Stale apps tabs, reached from a new menu-bar button. ✅
- 6th menu-bar icon state: `bell.badge.fill` for unreviewed changes. ✅

See `docs/15-what-changed-and-stale-slice.md` for the spec.

## v0.6.0 — One-click fixes and risk explanations (✅ done 2026-05-15)

- `PermissionService.riskDescription` — plain-English paragraph per TCC service explaining what the grant lets the app do. ✅
- `SystemSettingsLink.open(for: PermissionService)` — per-service deep links for all 16 services, verified on macOS Tahoe (26). Fallback to top-level Privacy pane if an anchor is no longer recognized. ✅
- `PermissionDetailSheet` — tap any Permissions row to open a sheet with the app icon, service, risk paragraph, meta details, and an "Open in Settings" deep-link button. ✅
- Sonoma + Sequoia cross-version anchor verification deferred to v0.6.x.

See `docs/16-one-click-fixes-and-risk-slice.md` for the spec.

## v0.6.1 — Tahoe Vibrant UI polish (✅ done 2026-05-17)

- `DetailWindowView` rebuilt as a `NavigationSplitView` — sidebar navigation (Permissions / Launch Agents / Background Items / Recent Changes / Stale Apps) replacing the single ScrollView. ✅
- Unified detail sheets and a shared `VibrancyCard` surface for the "Tahoe Vibrant" visual direction. ✅
- No new scanners or data — visual/navigation polish only. No dedicated slice doc; the UI direction is traced in the untracked `design-mockups/` HTML files. ✅

## v0.7.0 — Preferences, weekly digest, per-row dismiss (✅ released 2026-05-25; implemented 2026-05-16)

- Preferences pane (snapshot retention + stale threshold sliders, weekly digest controls, Reset All Data). ✅
- Weekly local notification opt-in via `UNUserNotificationCenter` + `WeeklyDigestCoordinator`. ✅
- Per-row Dismiss / Snooze 7 days on Recent Changes (semantic keys persist across snapshots). ✅
- Skip-stale-app-forever per stale row, filtered in `SnapshotCoordinator.computeStaleApps` so the badge count stays honest. ✅

See `docs/17-preferences-and-digest-slice.md` for the spec.

## v0.7.1 — Maintenance (✅ done 2026-05-25)

A small post-v0.7.0 code-review follow-up — no new features:

- `PreferencesWindowView` next-fire label uses `DateFormatter.localizedString(from:dateStyle:timeStyle:)` instead of allocating a fresh `DateFormatter` on each evaluation. ✅
- New regression-guard test (`PreferencesStoreTests.initDoesNotWriteFallbacksWhenDefaultsAreEmpty`): `didSet` must not fire during `@Observable` init under Tahoe, so a fresh launch with no prior keys leaves `UserDefaults` untouched. ✅
- Version bumped to `0.7.1` / build `11`. ✅

(The store/window fixes also visible in recent history — `computeDiff` no longer traps on duplicate identity keys, `latestSnapshotID` orders by `created_at`, singleton detail/preferences windows + Preferences toolbar entry — landed within the v0.7.0 tag range, not v0.7.1.)

## Unreleased since v0.7.1 (on `main`, plus `release/v0.7.2` until it merges)

Landed after the v0.7.1 tag; ships in the next release:

- Thread A app-quality workstreams W1–W4 (correctness, dead-code sweep, resilience, accessibility). ✅
- Thread B visual overhaul + Thread C native redesign: `OverviewPage`, non-modal inspectors replacing the detail sheets, native Settings-style Preferences tabs, singleton `Window(id:)` scenes. ✅
- Export to JSON/Markdown via `NSSavePanel` (`ExportToolbar`) — pulled forward from the old v1.1 list. ✅
- Launch at login via `SMAppService` (Preferences → General). ✅
- TCC `auth_value` change tracking in the diff engine and rendered authorization-transition rows, including consistent badge/search/dismiss/digest counts. ✅
- Stable `bundle:` / `path:` identities, installed bundle-path retention, and migrated stale-app dismissals. ✅
- Typed scanner coverage with complete/degraded/failed states, last-known failure behavior, and degraded snapshot suppression (superseded by per-domain coverage in the core-loop item below). ✅
- Snapshot schema v5 persists LaunchAgent disabled state with a compatibility marker that preserves v4 history and suppresses false upgrade transitions. ✅
- Section-aware search: Overview has no false affordance; Recent Changes searches every rendered TCC/BTM/LaunchAgent row kind. ✅
- Notification banners present while the app is frontmost (`NotificationPresentationDelegate`). ✅
- Core loop: scans run at launch, on wake, on calendar-day change, and on a stale open (`ScanScheduler`); snapshots are written when the evidence changes instead of once per day; snapshot schema v6 records per-domain coverage so one degraded or failed scanner no longer blocks history for the others; Recent Changes shows when history was last updated and names domains it could not compare; label-less launchd plists are treated as inert instead of malformed. See `docs/superpowers/specs/2026-10-10-core-loop-design.md`. ✅
- macOS 27 compatibility: Background Items reads the per-user store layout (`BackgroundItems-v18-<UUID>.btm`); Permissions treats the per-user TCC database, which macOS 27 no longer exposes to any app, as out of scope instead of a failed read — the banner says "System-level permissions only" and snapshots record `reduced` coverage. On macOS 27+ a per-user directory without a `TCC.db` is also treated as unexposed. ✅
- Launch Agents fidelity: a plist that cannot be read or parsed (e.g. a root-only 0700 daemon) is listed as "Details unreadable" instead of degrading the section; dangling symlinks are ignored; disabled state comes from launchd's override files (`/private/var/db/com.apple.xpc.launchd/disabled.plist`, `disabled.<uid>.plist`); rows show the program and scope, "Program not found" marks a job whose program is gone, and Recent Changes describes launch-agent changes in plain language. ✅
- Snapshot schema v7: `launch_agents.details_readable` and `launch_agents.file_name`; v4/v5/v6 databases migrate in place. A database written by a newer version or a corrupt one gets its own Recent Changes state instead of being opened; writes wait up to 5 s on a lock. ✅
- Background Items: every observed `type` value is named (login item, app agent, legacy agent and daemon, background tasks, Spotlight / QuickLook / Dock tile extensions); identity is scope + identifier; diffs compare disposition and type only. ✅
- Permissions: Remote Desktop and Endpoint Security grants (18 services; both are system-level and counted in Overview's risk line); "App not found on this Mac" badge for grants whose app is gone; diffs compare the authorization state only. ✅
- History: each section picks its own baseline, and pruning keeps those baselines. Recent Changes' first window is "Since Last Review" (replacing the old "Yesterday" window), marked reviewed on leaving the page, closing the window on it, or Mark All Reviewed; the first snapshot ever is the first baseline. Each section not compared says why; a macOS 26 history compared with a macOS 27 scan covers the system-level permissions only. One visible-change list feeds the page, badges, counts, change alerts, and the digest. ✅
- Notifications: opt-in change alerts (`changeAlertsEnabled`) after a scan writes a snapshot; the weekly digest is re-armed after every scan with a non-repeating trigger; the Preferences "Digest" tab is now "Notifications". ✅
- Full Disk Access: loss after an update or a revocation opens a recovery window once per build (`lastLaunchedVersion`, `fdaPromptShownForVersion`) that waits for the user to come back, checks again, and offers Reopen; the Welcome window runs the same loop. ✅
- App behavior: double-clicking the running app in Finder opens the detail window; only one copy runs at a time; launch-at-login shows its real status, including requires-approval; Check for Updates… (dropdown and Preferences → General → About, which shows the version) opens the Releases page in the browser; the dropdown footer's welcome item is "Welcome Tour"; the dropdown header shows "Updated <time>"; a copy running from App Translocation is told to move to Applications; live mic/camera use wins the menu-bar icon; mic and camera devices added or removed after launch are followed. ✅
- macOS 27 scope stated everywhere: hidden-service searches, the dropdown summary, Overview's "Permission coverage" row, the app inspector, and Stale Apps (banner and separate empty states for no data and no history). ✅
- Data: export records app and macOS versions, per-section scan coverage, and export `schemaVersion` 2; Preferences → Data can restore dismissed changes and skipped stale apps and has Copy Diagnostics; attention rows open the section they are about. ✅
- Stale Apps probes only `.app` bundles and says "Last modified" when the date came from the file. ✅

## v0.8.x — Remaining model fidelity (planned, deferred from v0.7.0)

Carried over from `docs/17` "Deferred to later slices":

- Sub-service preservation for `.filesAndFolders` / Photos / Bluetooth (the five folder-scope TCC strings currently collapse to one grant).
- Notification click → open Recent Changes (needs a `UNUserNotificationCenterDelegate` routing into `pendingDetailMode`).

## v1.0.0 — First public release

- All v1 scope items shipped and tested.
- README screenshots taken.
- GitHub Releases announcement post.
- Optionally Show HN / Product Hunt.

## v1.1 (post-launch)

- Homebrew tap.
- Localization for at least one non-English locale.
- (Configurable stale-app threshold already shipped in v0.7.0; contextual search already covers every searchable detail section while Overview stays search-free.)

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
