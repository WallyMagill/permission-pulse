# Permission Pulse

> macOS permission hygiene for humans. See what your Mac is allowing — and what changed.

![latest release](https://img.shields.io/github/v/release/WallyMagill/permission-pulse?sort=semver)
![license](https://img.shields.io/badge/license-MIT-blue)
![macOS](https://img.shields.io/badge/macOS-14.6%2B-lightgrey)
![signing](https://img.shields.io/badge/signing-unsigned%20%2F%20ad--hoc-orange)

macOS asks for powerful permissions (Screen Recording, Accessibility, Full Disk Access, microphone, camera, login items). After a few months nobody remembers what they granted. Apple's System Settings panes are split by category, never show history, and never explain what a permission actually allows.

Permission Pulse is a menu-bar app that gives you the missing view:

- **Permission Inbox** — every app grouped by what it can do (Accessibility, Screen Recording, FDA, Mic, Camera, Automation, Files & Folders). On macOS 27 and later, Apple no longer exposes per-user permission records to any app, so the inbox covers the system-level permissions only: Accessibility, Full Disk Access, Input Monitoring, and Screen Recording.
- **Background Items** — Launch Agents, Launch Daemons, and BTM-managed login items / helpers, including disabled ones.
- **What Changed** — "Zoom added Screen Recording 3 days ago," "Foo.app added a login item yesterday." Daily and weekly diffs, with per-row dismiss/snooze. History records itself: the app rescans on wake, at the start of each day, and when you open it.
- **Live Mic/Cam Indicator** — the menu-bar icon shows when something is using your microphone or camera right now.
- **Plain-English Risks** — what does Screen Recording actually let an app see?
- **Stale App Review** — apps with powerful permissions you haven't opened in 90+ days (threshold is configurable).
- **One-click Fixes** — deep links to the right System Settings pane.
- **Weekly Digest** — an opt-in local notification with what's new.
- **Overview** — one landing page with anything needing attention, per-section counts, and the last scan time.
- **Export** — save the current permission state as JSON or Markdown to a location you choose.
- **Launch at Login** — optional, from Settings → General.

Read-only. No cleaner-tier nonsense. No analytics. No phoning home. Free and open-source under MIT.

## Status

**v0.7.1 is the latest published release. v0.7.2 is an unreleased candidate.** The v0.7.2 source currently implements an Overview landing page, the TCC permission inbox, Launch Agents / Launch Daemons / BTM background-item scanners, the live mic/cam indicator, daily and weekly "What Changed" diffs with per-row dismiss/snooze, automatic rescans (wake, new day, stale open) with coverage-aware history, plain-English risk explanations, stale-app review, one-click System Settings deep links, export to JSON/Markdown, launch at login, a settings window (retention + stale threshold + digest schedule + reset), an opt-in weekly digest notification, and the app's first icon. It is not a supported release until its remaining human gates pass and the version is actually tagged and published. See [`docs/09-roadmap.md`](docs/09-roadmap.md) for the full milestone history and what remains before a tagged `v1.0.0`.

The published v0.7.1 asset remains immutable. If v0.7.2 passes the release gates and is published, its release notes will supersede the development-signed v0.7.1 artifact prospectively; until then, the repository's verified v0.7.2 archive is only a local release candidate. Maintainers must use the single manual build-and-verification path in [`docs/06-distribution.md`](docs/06-distribution.md); CI verifies the same artifact shape but never tags, publishes, or uploads a release.

Builds are **unsigned / ad-hoc-signed** — there is no paid Apple Developer ID behind this project — so the first launch needs the Gatekeeper "Open Anyway" step below. Nothing about the app is gated, paid, or phones home.

## Install

1. Download `PermissionPulse-vX.Y.Z.app.zip` from the [Releases page](https://github.com/WallyMagill/permission-pulse/releases) and unzip it (Finder unzips with a double-click).
2. Drag **PermissionPulse.app** into `/Applications`.
3. **First launch:** double-click the app. macOS shows an "Apple could not verify…" dialog — Permission Pulse is not notarized because there is no paid Apple Developer ID behind it. Click **Done** (not "Move to Trash"), then open **System Settings → Privacy & Security**, scroll down to the *"Permission Pulse" was blocked* notice, and click **Open Anyway**. Confirm the follow-up dialog (macOS asks you to authenticate). After the first launch it opens normally.
   - On **macOS 14 (Sonoma)** the older shortcut still works: right-click the app → **Open** → **Open**. macOS 15 (Sequoia) and later removed that shortcut for unsigned apps.
   - Terminal alternative: `xattr -d com.apple.quarantine /Applications/PermissionPulse.app` removes the quarantine flag so the app opens directly.
4. On the first-run prompt, grant **Full Disk Access** in System Settings → Privacy & Security → Full Disk Access; macOS may ask you to quit and reopen the app for it to take effect. FDA is required to read the TCC database (app permissions) and the BTM background-items store — Permission Pulse only ever *reads* these files, never writes to them. The Launch Agents and live mic/cam features work without FDA.
5. **After updating to a new version:** macOS ties a Full Disk Access grant to the exact signature of the app that received it, and every ad-hoc-signed release has a different one. Replacing the app with a new version therefore turns the grant off. If Permission Pulse reports that Full Disk Access is missing after an update, turn its toggle back on in System Settings → Privacy & Security → Full Disk Access (off and on again if it already looks on), then quit and reopen the app.

## Privacy

Permission Pulse makes no network connections. It has no analytics, no telemetry, and no crash reporting. The only things that leave the app are links you click: they open your browser (for example, the "Report" link on a schema-mismatch banner opens a new GitHub issue) or System Settings.

What it reads, all read-only:

- The system permission database, `/Library/Application Support/com.apple.TCC/TCC.db`.
- The per-user permission database, `~/Library/Application Support/com.apple.TCC/TCC.db`, on macOS 26 and earlier (macOS 27 does not expose it).
- The Background Task Management store, the `BackgroundItems-v*.btm` files under `/private/var/db/com.apple.backgroundtaskmanagement/`.
- Launch item property lists in `~/Library/LaunchAgents`, `/Library/LaunchAgents`, and `/Library/LaunchDaemons`, plus launchd's enabled/disabled overrides in `/private/var/db/com.apple.xpc.launchd/`.
- Spotlight's last-used date for apps that hold permissions (via `/usr/bin/mdls`), falling back to the app bundle's modification date.
- Whether a microphone or camera is in use right now (CoreAudio and CoreMediaIO device state; it never opens a device).

What it writes:

- `~/Library/Application Support/com.wallymagill.permissionpulse/` (the `snapshots.db` history database and its `-wal` / `-shm` files).
- Its own preferences (the `com.wallymagill.permissionpulse` defaults domain).
- Export files, only where you choose in the save dialog.

Turning on Launch at Login registers the app with macOS through `SMAppService`; turning on the weekly digest schedules a local notification.

## Verify the download

Each release ships `PermissionPulse-vX.Y.Z.app.zip.sha256` next to the archive. With both files in the same folder:

```bash
shasum -a 256 -c PermissionPulse-vX.Y.Z.app.zip.sha256
codesign -dv --verbose=2 /Applications/PermissionPulse.app
```

The first command prints `PermissionPulse-vX.Y.Z.app.zip: OK`. The second should include `Signature=adhoc` and no `Authority=` lines: release builds are ad-hoc signed, not signed by a Developer ID. Builds are not reproducible, so a checksum of your own build will not match the release.

## Uninstall

1. In Permission Pulse's Settings → General, turn off **Launch at Login**.
2. In System Settings → Privacy & Security → Full Disk Access, select Permission Pulse and remove it with the **−** button. Do this before deleting the app.
3. Quit Permission Pulse and move `/Applications/PermissionPulse.app` to the Trash.
4. Delete its data and preferences:

```bash
rm -rf ~/Library/Application\ Support/com.wallymagill.permissionpulse
defaults delete com.wallymagill.permissionpulse
```

## Known limitations

- **macOS 27 shows less.** Apple no longer exposes per-user permission records (Camera, Microphone, Files and Folders, Automation, Contacts, Calendar, Photos, Reminders, Bluetooth, App Management, Media Library) to any app. Only Accessibility, Full Disk Access, Input Monitoring, and Screen Recording are visible there.
- **Full Disk Access turns off after every update**, because each ad-hoc-signed build has a different signature. Install step 5 restores it.
- **No auto-update.** Check the [Releases page](https://github.com/WallyMagill/permission-pulse/releases) for new versions.
- **Untested on Intel and on macOS 14 and 15.** The Intel slice is built but has not been run on Intel hardware.
- **English only.**
- **No Developer ID**, so Gatekeeper warns on first launch (install step 3).

## Requirements

- macOS 14.6 or later (the app's deployment target). Developed and tested on **macOS 26 (Tahoe) and macOS 27, Apple Silicon** — earlier macOS versions are untested. macOS 27 narrows what the Permission Inbox can show (see above); Background Items, Launch Agents, and the live mic/cam indicator are unaffected.
- Shipped as a universal binary (Apple Silicon + Intel); the Intel slice is built, but execution and UI behavior remain explicitly unverified without real Intel hardware.
- No runtime dependencies beyond macOS itself.

## Build from source

Requires Xcode 26.5 or later.

```bash
git clone https://github.com/WallyMagill/permission-pulse.git && cd permission-pulse
open PermissionPulse/PermissionPulse.xcodeproj   # build with ⌘B, or from the CLI:
xcodebuild -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build
```

Tests, release packaging, and CI are described in [`docs/07-build-and-test.md`](docs/07-build-and-test.md).

## How it works (one paragraph)

Permission Pulse runs as a menu-bar app. At launch, on wake from sleep, at the start of each calendar day, and when you open it after more than a minute, it scans (a) the TCC database for granted permissions, (b) `LaunchAgents` and `LaunchDaemons`, (c) BTM-managed background items, and (d) the system device-use APIs (CoreMediaIO + CoreAudio) for current mic/cam usage. A snapshot is stored whenever a scan's evidence differs from the last stored one, in a local SQLite database (via GRDB) under `~/Library/Application Support/com.wallymagill.permissionpulse/`. The "What Changed" view is a diff between the latest snapshot and the state at the start of today (and at the start of the day a week ago). Nothing leaves your machine.

Scanner results are labeled **complete**, **degraded**, or **failed**. A degraded read keeps the evidence that was available and names the omitted source category. Each snapshot records per-domain coverage (schema v6) as **complete**, **reduced** (permissions on macOS 27, where only the system-level records are readable), **degraded**, or **failed**. A domain is diffed only when both snapshots have the same full scope (complete and complete, or reduced and reduced), so a partial or failed read never shows up as a removal; Recent Changes names any domain it could not compare. A failed read keeps and labels last-known data when any exists; a first-run failure says that no successful data is available instead of presenting an empty list as complete. Stable app identities use `bundle:<bundle-id>` or `path:<standardized-path>`, so installed bundle-ID apps can participate in stale review while separate path-only clients never collapse together. Snapshot schema v5 preserves v4 history, records whether LaunchAgent disabled state was captured, and suppresses false disabled-only transitions across the upgrade boundary. Recent Changes renders TCC authorization transitions alongside other changes, and its contextual search covers every rendered row kind; Overview intentionally has no search field.

## Runtime settings and recovery

Snapshot retention and stale-app thresholds are live preferences. Permission Pulse captures both values once when each completed scan reaches snapshot and stale-app processing, so an edit applies at the next scan boundary and the captured values remain stable throughout that processing pass.

**Reset All Data** cancels Permission Pulse's weekly and test notifications, releases the open history store, removes `snapshots.db` plus its `-wal` and `-shm` sidecars, clears live and persisted preferences and dismissals, removes Permission Pulse-prefixed defaults while preserving macOS-owned window/status/split-view state, recreates a migrated history store, clears the current presentation state, and runs a recovery scan. Scans, resets, and overlapping reset requests are serialized. History deletion, defaults cleanup, and history recreation failures are reported by their actual phase; if storage reset succeeds but the recovery scan fails, Permission Pulse shows a separate warning and offers Refresh rather than claiming the scan succeeded.

When an enabled weekly digest's day or time changes, the selected value is saved immediately and superseded edits are debounced. Schedule mutations run serially, replace the pending weekly request, and publish the actual next-fire date. A scheduling failure keeps the selected day/time and shows an orange, retryable error. Digest change totals include TCC authorization transitions as well as background-item and launch-agent changes.

## Reporting a bug

[Open an issue](https://github.com/WallyMagill/permission-pulse/issues/new/choose) with your macOS version (the output of `sw_vers`), the app version (select `PermissionPulse.app` in Finder → File → Get Info, or name the release you downloaded), and the exact text of any banner the app shows. For a security problem, follow [`SECURITY.md`](SECURITY.md) instead of opening a public issue.

## Contributing

Issues and PRs welcome. Read [`docs/03-architecture.md`](docs/03-architecture.md) first to orient. By contributing you agree to license your contributions under MIT.

## License

[MIT](LICENSE).

## Next version

Before v0.7.2 is tagged, this page gets screenshots (light and dark) of the dropdown, Overview, Permission Inbox, Recent Changes, Stale Apps, and Digest settings, and the release itself goes through the human gates in [`docs/superpowers/prompts/v0.7.2-release-runbook.md`](docs/superpowers/prompts/v0.7.2-release-runbook.md). Later work is tracked in [`docs/09-roadmap.md`](docs/09-roadmap.md).
