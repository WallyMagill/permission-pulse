# Permission Pulse — project rules for AI sessions

Future agent sessions: read this file before touching the code. It encodes decisions and constraints that are easy to miss from reading the source alone.

## What this project is

**Permission Pulse** — a free, MIT-licensed, open-source macOS menu-bar app for permission hygiene. Read-only inspection of TCC permissions, LaunchAgents, BTM background items, and mic/cam usage, plus a change history ("Since Last Review" and "Last 7 days"). Distributed via GitHub Releases as a verified, ad-hoc-signed `.app` archive (`PermissionPulse-vX.Y.Z.app.zip`) that a maintainer publishes manually; no paid Apple Developer ID.

**v0.7.2** is the configured release candidate; do not publish it until all required workstream gates pass. v0.7.1 remains the latest published, immutable historical release until v0.7.2 is actually published. All v1-scope features are implemented. `docs/09-roadmap.md` is the source of truth for milestone status; `docs/03-architecture.md` and `docs/04-data-sources.md` describe the implemented system.

## Hard rules — never violate

Non-negotiable. Violating any of these is a session-level failure.

1. **Read-only filesystem.** The only paths Permission Pulse may write to are `~/Library/Application Support/com.wallymagill.permissionpulse/` and the user's chosen export location. Never write to `/Library`, `/System`, `/private/var`, `/Applications`, `~/Library/Application Support/com.apple.*`, or any TCC.db / BTM file. Never modify any file owned by another app.
2. **No `sudo`. No admin commands. No privilege escalation.** If a feature would require sudo, surface it as a manual step the user runs themselves; do not invoke it automatically.
3. **No kernel extensions. No system extensions.** Plain `.app` bundle only.
4. **No paid features. No license gating. No analytics.** All features in the build ship to everyone. No telemetry, no opt-in pings, no crash reporters that phone home.
5. **No vendored third-party code without a clear permissive license.** SwiftParseTCC at `slyd0g/SwiftParseTCC` has no LICENSE file — it is a schema reference only. Do not copy code from it.
6. **No secrets in the repo.** No API keys, no Developer ID certs, no notarization credentials, no signing keys. `.env.example` only.

## Stack — committed

Do not silently swap a stack component. If you think one is wrong, raise it as an open question.

- **Xcode project (native `.xcodeproj`)** for the app target. No Tuist, no XcodeGen.
- **Local SwiftPM packages** for all logic: `PermissionsCore`, `PermissionsScanners`, `PermissionsStore`, `PermissionsUI`. Each has its own test target.
- **Swift 6.3** under Xcode 26's new-project defaults: Approachable Concurrency = Yes, Default Actor Isolation = MainActor, Strict Concurrency Checking = Complete.
- **SwiftUI first.** `MenuBarExtra` for the dropdown; singleton `Window(id:)` scenes (not `WindowGroup`) for the detail and Preferences windows so `openWindow(id:)` reuses the existing window instead of spawning duplicates; plus a zero-size `WindowGroup` trampoline that works around the Tahoe `openSettings` bug (see "Known macOS Tahoe quirks") and also opens windows the app delegate requests through `AppViewModel.windowToOpen` (e.g. the detail window on a Finder reopen). Drop to AppKit only when SwiftUI genuinely cannot express what we need (right-click menus, custom button rendering, draggable popovers, one-shot dialogs like the Welcome and Full Disk Access recovery windows). Every AppKit drop must have a `// AppKit: <reason>` comment.
- **`@Observable` ViewModels.** Never `ObservableObject`.
- **`SMAppService` for login items.** Never `LSSharedFileList` (deprecated).
- **GRDB.swift v7.x** for the snapshot store. Change-driven snapshots (written when a scan's evidence or coverage differs from the latest one) in `~/Library/Application Support/com.wallymagill.permissionpulse/snapshots.db`.
- **Swift Testing** for all new tests. XCTest only for UI/perf tests Swift Testing can't yet express. Do not mix them in one target.
- **Localization-ready** from day one: every user-facing string goes through `String(localized:)`. v1 ships English-only.
- **Zero third-party UI deps** unless justified. GRDB is the only confirmed third-party dep at v1. KeyboardShortcuts (Sindre Sorhus) is acceptable if we add global hotkeys.

## Default-on coding rules

- **MainActor-by-default.** Xcode 26 infers MainActor for new types. Don't manually annotate; use `nonisolated` on the rare type (scanner, SQLite worker pool) that must run off the main actor.
- **No spurious `DispatchQueue.main.async`.** If you're already MainActor-isolated, you're already on the main thread.
- **`async/await` end-to-end.** Don't mix completion handlers with `async` unless interfacing with a system API that forces it.
- **Break up nested SwiftUI literals.** Extract subviews aggressively to avoid the type-checker explosion. If a `body` property is over 60 lines, split it.
- **`[weak self]` in `Task { }`** unless the Task is bounded and short-lived. Long-running `Task`s that capture `self` strongly leak the owning object.
- **Files ≤ 800 lines.** Prefer < 400. Split large modules.
- **Functions < 50 lines.**
- **No comments that restate the code.** Only comment when the *why* is non-obvious.

## Known fragile surfaces

These are the spots where AI codegen most often invents APIs or assumes behavior that doesn't match macOS reality. Verify with a print-and-inspect script before trusting a first draft.

| Surface | Risk | Mitigation |
|---|---|---|
| TCC.db schema reads | Apple can rename columns in point releases. **macOS 27 stopped exposing the per-user TCC.db to any app** (it moved into a protected system container FDA does not open); only the system DB is readable there. Its services are `PermissionService.systemLevel`: Accessibility, Full Disk Access, Input Monitoring, Screen Recording, Remote Desktop (`kTCCServiceRemoteDesktop`), and Endpoint Security (`kTCCServiceEndpointSecurityClient`). `PermissionService` has 18 cases. | Read-only SQLite via GRDB. Version-check the schema before depending on a column. A missing database directory, or on macOS 27+ a missing per-user `TCC.db`, is an unexposed source (`reduced` coverage), never a reason to escalate. A complete (macOS 26) baseline compared with a reduced (macOS 27) scan diffs only the `systemLevel` services. Grant diffs compare the authorization state (`auth_value`) only. |
| BTM enumeration | No public API. `BackgroundItems-v*.btm` filename has bumped before, and macOS 27 (v18) split it into one `BackgroundItems-v18-<user UUID>.btm` per user plus an index file. Item `type` values are private bits; `BTMItem.ItemType` names them from the paths each one registers: app `0x2`, login item `0x4`, app agent `0x8`, developer group `0x20`, Spotlight extension `0x40`, Dock tile extension `0x80`, QuickLook extension `0x800`, background tasks `0x2000`, legacy agent `0x10008`, legacy daemon `0x10010`. Anything else is `unknown(rawValue:)`. | Hide behind a `BTMScanner` protocol. The shipping path reads `.btm` files directly under FDA and never invokes `sudo` or `sfltool`. Degrade gracefully. Item identity is scope + identifier (`BTMItem.identityKey`), because one identifier registers once per scope. Diffs compare disposition and type only. |
| `SMAppService` | Bundled-helper plist layout is the trap. `requiresApproval` is a real status: the user must approve the app in System Settings → Login Items. | Hand-test on a real machine before committing. Preferences re-reads `SMAppService.mainApp.status` when the General tab appears and when the app becomes active, and offers Open Login Items for `requiresApproval`. |
| LaunchAgents enumeration | Mostly stable. Root-only (0700) daemon plists cannot be read, and launchd keeps its own enabled/disabled state outside the plist. | `PropertyListSerialization` over `~/Library/LaunchAgents/`, `/Library/LaunchAgents/`, `/Library/LaunchDaemons/`. No FDA needed. A plist that is permission-denied or unparseable is listed with `detailsReadable = false` (label = file name) and raises no warning. A dangling symlink or a label-less plist is skipped silently; other read errors are omitted with a warning. Disabled state comes from launchd's override files, `/private/var/db/com.apple.xpc.launchd/disabled.plist` (daemons) and `disabled.<uid>.plist` (agents), read-only, falling back to the plist's `Disabled` key; a missing file means no overrides. |
| TCC/BTM protected-data access | Direct reads require FDA and Apple can change private schemas or paths. | Validate schemas, under-flag uncertain evidence, and surface degraded coverage without adding a privileged fallback. |
| Mic/cam current use | Public APIs | CoreMediaIO + CoreAudio `…DeviceIsRunningSomewhere` property listeners (`MediaUseObserverCMIO`) — **not** AVFoundation. Listeners on the device lists (`MediaDeviceTracker`) follow devices added or removed after launch. Drives the menu-bar icon, where live mic/camera use outranks warnings and unreviewed changes. |
| `LastUsedProbeHybrid` (Spotlight via `mdls`) | Spotlight metadata returns `(null)` on many apps even when they've been used recently. Sandbox-on path will need replacement. | Probe only `.app` bundles (a bare binary's Spotlight date is its OS-update mtime). Hybrid fallback to `URL.contentModificationDateKey`, shown as "Last modified". Skip the app if both miss (under-flag, never over-flag). Future-tag: replace `Process(/usr/bin/mdls)` with `MDItemCreate` in-process when sandboxing turns on. |
| Snapshot store schema v7 | GRDB migration drift if Apple changes underlying TCC/BTM enum bits; a database written by a newer build | Per-domain `*_kind` TEXT + nullable `*_raw` INTEGER captures `unknown(rawValue:)` losslessly; v4 persists TCC `auth_value`; v5 persists LaunchAgent disabled state and its per-snapshot capture marker; v6 adds per-domain `*_coverage` (`complete`/`reduced`/`degraded`/`failed`) on `snapshots`; v7 adds `launch_agents.details_readable` (default 1) and nullable `launch_agents.file_name`. v4/v5/v6 databases migrate in place. `file_name` is not part of LaunchAgent equivalence, because pre-v7 rows hold NULL. Each domain picks its own baseline (`BaselineSelector`): the newest earlier snapshot whose coverage can be compared with the latest's, and pruning keeps those baselines. A `failed` domain stores no rows. A database with migrations this build does not know throws `SnapshotStoreOpenError.createdByNewerVersion`; `SQLITE_CORRUPT`/`SQLITE_NOTADB` throws `.corrupt`. The unmerged `codex/agent-access-*` branches also claim `v6`; they must renumber to `v8` if revived. |
| `UNUserNotificationCenter` on ad-hoc-signed bundles | An ad-hoc-signed `.app` may register oddly with the notification system. The system prompt and delivered banner *should* show "Permission Pulse" (the `INFOPLIST_KEY_CFBundleDisplayName`) but may fall back to a generic bundle label. | Hand-test on Tahoe before any release that ships the weekly digest or change alerts (both share one authorization request). If the label is wrong and unfixable without a Developer ID, ship the slice without the digest and defer to a follow-up. Never add entitlements to "fix" this — crosses the Developer-ID line. |

## UserDefaults keys (current through v0.7.2)

In addition to `hasSeenWelcome`, `lastSnapshotDate`, `lastReviewedSnapshotID` from v0.3.x–v0.5.0, v0.7.0 added the keys below (v0.7.1 added no new keys; v0.7.2 added the last three):

- `com.wallymagill.permissionpulse.snapshotRetentionDays` — Int (7…365, default 90)
- `com.wallymagill.permissionpulse.staleThresholdDays` — Int (30…365, default 90)
- `com.wallymagill.permissionpulse.digestEnabled` — Bool (default false)
- `com.wallymagill.permissionpulse.digestWeekday` — Int (1…7, default 2 = Monday)
- `com.wallymagill.permissionpulse.digestHour` — Int (0…23, default 9)
- `com.wallymagill.permissionpulse.digestMinute` — Int (0…59, default 0)
- `com.wallymagill.permissionpulse.dismissedDiffEntries` — JSON `[String: Date]` (semantic-key → expiry; `.distantFuture` = forever)
- `com.wallymagill.permissionpulse.dismissedStaleApps` — `[String]` (`bundle:<bundle-id>` or `path:<standardized-file-path>` stable keys; legacy raw bundle IDs migrate without losing dismissals)
- `com.wallymagill.permissionpulse.changeAlertsEnabled` — Bool (default false)
- `com.wallymagill.permissionpulse.lastLaunchedVersion` — String `"<short version> (<build>)"` of the last build that scanned (absent until the first scan)
- `com.wallymagill.permissionpulse.fdaPromptShownForVersion` — String, same format: the build that already opened the Full Disk Access recovery window (absent until it first opens)

"Reset All Data" wipes everything matching `com.wallymagill.permissionpulse.*` while preserving `NSWindow`/`NSStatusItem`/`NSSplitView` keys macOS auto-writes under our bundle domain.

## Known macOS Tahoe (26) quirks

- **`openSettings` is broken inside `MenuBarExtra` on Tahoe.** Declare a hidden zero-size `WindowGroup` trampoline *first* in `App.body` (before `MenuBarExtra` and the singleton `Window(id:)` scenes — there is no `Settings` scene), and route every "open a window from the menu bar" call via `@Environment(\.openWindow)`. See https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items.
- **Tahoe 26.1+ restricts FDA for unsigned CLI binaries.** Permission Pulse is an `.app` bundle, so this does not bite us. But: never ship a bundled CLI helper that needs FDA.
- **Transparent menu bar** has visual implications. The menu-bar icon must render cleanly on both light and dark backgrounds. Use an SF Symbol with no fill if possible.
- **TCC `csreq` tightened** to match cdHash for some services (Input Monitoring confirmed). When attributing a TCC entry to a bundle, match by bundle ID first and verify with cdHash where present.

## Distribution constraints

- GitHub Releases only. `scripts/package-release.sh` is the sole supported packaging entry point. CI builds, tests, analyzes, then packages, ad-hoc-signs, and independently verifies a non-published artifact from a clean checkout. Tagging, GitHub Release creation, and upload remain manual. `docs/06-distribution.md` is the authoritative release procedure.
- Ad-hoc-signed, not Developer ID signed or notarized. First-launch UX must tolerate the Gatekeeper "unverified developer" dialog cleanly; the README documents the current Privacy & Security → Open Anyway flow.
- No Sparkle in v1. "Check for Updates…" (in the menu-bar dropdown and Preferences → General → About) only opens `https://github.com/WallyMagill/permission-pulse/releases` in the browser — the app makes no network request. When a Developer ID is acquired, we revisit Sparkle.
- No code-signing materials in the repo. Ad-hoc signing requires no identity and is performed only by `scripts/package-release.sh` during local or CI packaging. Developer ID signing and notarization remain out of scope.

## Mock-vs-real data discipline

Every scanner implements a protocol. Each protocol has a `MockScanner` implementation that returns clearly-labeled fake data. The UI must visually mark mock data (e.g., a "Mock" badge) so it's impossible to confuse on-screen output with reality. We never ship a build where MockScanner is the default — that's an integration-test-only convenience.

## Localization

Every user-facing string goes through `String(localized:)`. Don't hardcode English in views. v1 ships en-US only; we add other locales when there is real demand.

## When to ask the user

Ask before:
- Externally visible decisions (name, bundle ID, license, repo host, paid services, distribution timing).
- Stack changes.
- A research finding that invalidates a hard rule above.
- Any time you are about to commit something that will be visible to the public.

Decide and proceed:
- Internal code organization.
- Naming of internal symbols.
- Test names and structure.
- Code-level refactoring inside an existing module.

## Pre-empt common Swift-codegen failure modes

- Spurious `@MainActor` followed by `DispatchQueue.main.async` (you're already on main).
- Mixing completion-handler APIs with `async`/`await` instead of bridging once at the boundary.
- Reaching for legacy AppKit when SwiftUI works, or `LSSharedFileList` when `SMAppService` is correct.
- Type-checker explosion in deeply nested SwiftUI literals — break the view up.
- `[weak self]` rules in `Task` closures and `@StateObject` vs `@State` confusion under `@Observable`.
- Inventing TCC.db column names. Confirm by `sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db '.schema access'` before depending on one.
