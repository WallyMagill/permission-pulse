# Permission Pulse

> macOS permission hygiene for humans. See what your Mac is allowing — and what changed.

![latest release](https://img.shields.io/github/v/release/WallyMagill/permission-pulse?sort=semver)
![license](https://img.shields.io/badge/license-MIT-blue)
![macOS](https://img.shields.io/badge/macOS-14.6%2B-lightgrey)
![signing](https://img.shields.io/badge/signing-unsigned%20%2F%20ad--hoc-orange)

macOS asks for powerful permissions (Screen Recording, Accessibility, Full Disk Access, microphone, camera, login items). After a few months nobody remembers what they granted. Apple's System Settings panes are split by category, never show history, and never explain what a permission actually allows.

Permission Pulse is a menu-bar app that gives you the missing view:

- **Permission Inbox** — every app grouped by what it can do (Accessibility, Screen Recording, FDA, Mic, Camera, Automation, Files & Folders).
- **Background Items** — Launch Agents, Launch Daemons, and BTM-managed login items / helpers, including disabled ones.
- **What Changed** — "Zoom added Screen Recording 3 days ago," "Foo.app added a login item yesterday." Daily and weekly diffs, with per-row dismiss/snooze.
- **Live Mic/Cam Indicator** — the menu-bar icon shows when something is using your microphone or camera right now.
- **Plain-English Risks** — what does Screen Recording actually let an app see?
- **Stale App Review** — apps with powerful permissions you haven't opened in 90+ days (threshold is configurable).
- **One-click Fixes** — deep links to the right System Settings pane.
- **Weekly Digest** — an opt-in local notification with what's new.

Read-only. No cleaner-tier nonsense. No analytics. No phoning home. Free and open-source under MIT.

## Status

**v0.7.1 — released on [GitHub Releases](https://github.com/WallyMagill/permission-pulse/releases).** Every v1-scope feature is implemented and shipping: the TCC permission inbox, Launch Agents / Launch Daemons / BTM background-item scanners, the live mic/cam indicator, daily and weekly "What Changed" diffs with per-row dismiss/snooze, plain-English risk explanations, stale-app review, one-click System Settings deep links, a preferences pane (retention + stale threshold + reset), and an opt-in weekly digest notification. See [`docs/09-roadmap.md`](docs/09-roadmap.md) for the full milestone history and the short list of polish work remaining before a tagged `v1.0.0`.

Builds are **unsigned / ad-hoc-signed** — there is no paid Apple Developer ID behind this project — so the first launch needs the Gatekeeper "Open Anyway" step below. Nothing about the app is gated, paid, or phones home.

## Install

1. Download `PermissionPulse-vX.Y.Z.app.zip` from the [Releases page](https://github.com/WallyMagill/permission-pulse/releases) and unzip it (Finder unzips with a double-click).
2. Drag **Permission Pulse.app** into `/Applications`.
3. **First launch:** double-click the app. macOS shows an "Apple could not verify…" dialog — Permission Pulse is not notarized because there is no paid Apple Developer ID behind it. Click **Done** (not "Move to Trash"), then open **System Settings → Privacy & Security**, scroll down to the *"Permission Pulse" was blocked* notice, and click **Open Anyway**. Confirm the follow-up dialog (macOS asks you to authenticate). After the first launch it opens normally.
   - On **macOS 14 (Sonoma)** the older shortcut still works: right-click the app → **Open** → **Open**. macOS 15 (Sequoia) and later removed that shortcut for unsigned apps.
   - Terminal alternative: `xattr -d com.apple.quarantine "/Applications/Permission Pulse.app"` removes the quarantine flag so the app opens directly.
4. On the first-run prompt, grant **Full Disk Access** in System Settings → Privacy & Security → Full Disk Access; macOS may ask you to quit and reopen the app for it to take effect. FDA is required to read the TCC database (app permissions) and the BTM background-items store — Permission Pulse only ever *reads* these files, never writes to them. The Launch Agents and live mic/cam features work without FDA.

## Requirements

- macOS 14.6 or later (the app's deployment target). Developed and tested only on **macOS 26 (Tahoe), Apple Silicon** — earlier macOS versions are untested.
- Shipped as a universal binary (Apple Silicon + Intel); the Intel slice is built but untested.
- No runtime dependencies beyond macOS itself.

## Build from source

See [`docs/07-build-and-test.md`](docs/07-build-and-test.md).

## How it works (one paragraph)

Permission Pulse runs as a menu-bar app. On launch it scans (a) the TCC database for granted permissions, (b) `LaunchAgents` and `LaunchDaemons`, (c) BTM-managed background items, and (d) the system device-use APIs (CoreMediaIO + CoreAudio) for current mic/cam usage. Each daily snapshot is stored in a local SQLite database (via GRDB) under `~/Library/Application Support/com.wallymagill.permissionpulse/`. The "What Changed" view is a diff between today's snapshot and yesterday's (and last week's). Nothing leaves your machine.

## Contributing

Issues and PRs welcome. Read [`docs/03-architecture.md`](docs/03-architecture.md) first to orient. By contributing you agree to license your contributions under MIT.

## License

[MIT](LICENSE).
