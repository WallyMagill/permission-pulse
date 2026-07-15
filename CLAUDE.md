# CLAUDE.md — project rules for AI sessions

Future Claude sessions: read this file before touching the code. It encodes decisions and constraints that are easy to miss from reading the source alone.

## What this project is

**Permission Pulse** — a free, MIT-licensed, open-source macOS menu-bar app for permission hygiene. Read-only inspection of TCC permissions, LaunchAgents, BTM background items, and mic/cam usage, plus a daily diff. Distributed via GitHub Releases as a verified, ad-hoc-signed `.app` archive (`PermissionPulse-vX.Y.Z.app.zip`) that a maintainer publishes manually; no paid Apple Developer ID.

**v0.7.2** is the configured supported release line; do not publish it until all required workstream gates pass. v0.7.1 remains an immutable historical release whose development-signed artifact is superseded by v0.7.2. All v1-scope features are implemented. `docs/09-roadmap.md` is the source of truth for milestone status; `docs/03-architecture.md` and `docs/04-data-sources.md` describe the implemented system.

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
- **SwiftUI first.** `MenuBarExtra` for the dropdown; singleton `Window(id:)` scenes (not `WindowGroup`) for the detail and Preferences windows so `openWindow(id:)` reuses the existing window instead of spawning duplicates; plus a zero-size `WindowGroup` trampoline that works around the Tahoe `openSettings` bug (see "Known macOS Tahoe quirks"). Drop to AppKit only when SwiftUI genuinely cannot express what we need (right-click menus, custom button rendering, draggable popovers, one-shot dialogs like the Welcome window). Every AppKit drop must have a `// AppKit: <reason>` comment.
- **`@Observable` ViewModels.** Never `ObservableObject`.
- **`SMAppService` for login items.** Never `LSSharedFileList` (deprecated).
- **GRDB.swift v7.x** for the snapshot store. Daily snapshots in `~/Library/Application Support/com.wallymagill.permissionpulse/snapshots.db`.
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
| TCC.db schema reads | Apple can rename columns in point releases | Read-only SQLite via GRDB. Version-check the schema before depending on a column. |
| BTM enumeration | No public API. `BackgroundItems-v*.btm` filename has bumped before. | Hide behind a `BTMScanner` protocol. Ship two implementations: direct `.btm` parsing (FDA, no sudo, fragile) and `sfltool dumpbtm` (sudo, text-parsed, more stable). Degrade gracefully. |
| `SMAppService` | Bundled-helper plist layout is the trap | Hand-test on a real machine before committing. |
| LaunchAgents enumeration | Mostly stable | `PropertyListDecoder` over `~/Library/LaunchAgents/`, `/Library/LaunchAgents/`, `/Library/LaunchDaemons/`. No FDA needed. |
| `sfltool` / `tccutil` output parsing | Output format undocumented | Golden-output test fixtures. Re-record on each macOS major. |
| Mic/cam current use | Public APIs | CoreMediaIO + CoreAudio `…DeviceIsRunningSomewhere` property listeners (`MediaUseObserverCMIO`) — **not** AVFoundation. Drives the menu-bar dot. |
| `LastUsedProbeHybrid` (Spotlight via `mdls`) | Spotlight metadata returns `(null)` on many apps even when they've been used recently. Sandbox-on path will need replacement. | Hybrid fallback to `URL.contentModificationDateKey`. Skip the app if both miss (under-flag, never over-flag). Future-tag: replace `Process(/usr/bin/mdls)` with `MDItemCreate` in-process when sandboxing turns on. |
| Snapshot store schema v3 | GRDB migration drift if Apple changes underlying TCC/BTM enum bits | Per-domain `*_kind` TEXT + nullable `*_raw` INTEGER captures `unknown(rawValue:)` losslessly. Migration is purely additive — v2 tables untouched. |
| `UNUserNotificationCenter` on ad-hoc-signed bundles | An ad-hoc-signed `.app` may register oddly with the notification system. The system prompt and delivered banner *should* show "Permission Pulse" (the `INFOPLIST_KEY_CFBundleDisplayName`) but may fall back to a generic bundle label. | Hand-test on Tahoe before any release that ships the weekly digest. If the label is wrong and unfixable without a Developer ID, ship the slice without the digest and defer to a follow-up. Never add entitlements to "fix" this — crosses the Developer-ID line. |

## UserDefaults keys (current through v0.7.2)

In addition to `hasSeenWelcome`, `lastSnapshotDate`, `lastReviewedSnapshotID` from v0.3.x–v0.5.0, v0.7.0 added the keys below (v0.7.1 and v0.7.2 added no new keys):

- `com.wallymagill.permissionpulse.snapshotRetentionDays` — Int (7…365, default 90)
- `com.wallymagill.permissionpulse.staleThresholdDays` — Int (30…365, default 90)
- `com.wallymagill.permissionpulse.digestEnabled` — Bool (default false)
- `com.wallymagill.permissionpulse.digestWeekday` — Int (1…7, default 2 = Monday)
- `com.wallymagill.permissionpulse.digestHour` — Int (0…23, default 9)
- `com.wallymagill.permissionpulse.digestMinute` — Int (0…59, default 0)
- `com.wallymagill.permissionpulse.dismissedDiffEntries` — JSON `[String: Date]` (semantic-key → expiry; `.distantFuture` = forever)
- `com.wallymagill.permissionpulse.dismissedStaleApps` — `[String]` (bundleIDs the user skipped forever)

"Reset All Data" wipes everything matching `com.wallymagill.permissionpulse.*` while preserving `NSWindow`/`NSStatusItem`/`NSSplitView` keys macOS auto-writes under our bundle domain.

## Known macOS Tahoe (26) quirks

- **`openSettings` is broken inside `MenuBarExtra` on Tahoe.** Declare a hidden zero-size `WindowGroup` trampoline *first* in `App.body` (before `MenuBarExtra` and the singleton `Window(id:)` scenes — there is no `Settings` scene), and route every "open a window from the menu bar" call via `@Environment(\.openWindow)`. See https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items.
- **Tahoe 26.1+ restricts FDA for unsigned CLI binaries.** Permission Pulse is an `.app` bundle, so this does not bite us. But: never ship a bundled CLI helper that needs FDA.
- **Transparent menu bar** has visual implications. The menu-bar icon must render cleanly on both light and dark backgrounds. Use an SF Symbol with no fill if possible.
- **TCC `csreq` tightened** to match cdHash for some services (Input Monitoring confirmed). When attributing a TCC entry to a bundle, match by bundle ID first and verify with cdHash where present.

## Distribution constraints

- GitHub Releases only. `scripts/package-release.sh` is the sole supported packaging entry point. CI builds, tests, analyzes, then packages, ad-hoc-signs, and independently verifies a non-published artifact from a clean checkout. Tagging, GitHub Release creation, and upload remain manual. `docs/06-distribution.md` is the authoritative release procedure.
- Ad-hoc-signed, not Developer ID signed or notarized. First-launch UX must tolerate the Gatekeeper "unverified developer" dialog cleanly; the README documents the current Privacy & Security → Open Anyway flow.
- No Sparkle in v1. When a "Check for Updates…" menu item is added it must simply open `https://github.com/WallyMagill/permission-pulse/releases` in the browser — it is **not wired up yet**. When a Developer ID is acquired, we revisit Sparkle.
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
