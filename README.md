# Permission Pulse

> macOS permission hygiene for humans. See what your Mac is allowing — and what changed.

![status](https://img.shields.io/badge/status-pre--alpha-orange)
![license](https://img.shields.io/badge/license-MIT-blue)
![macOS](https://img.shields.io/badge/macOS-14%2B-lightgrey)

macOS asks for powerful permissions (Screen Recording, Accessibility, Full Disk Access, microphone, camera, login items). After a few months nobody remembers what they granted. Apple's System Settings panes are split by category, never show history, and never explain what a permission actually allows.

Permission Pulse is a menu-bar app that gives you the missing view:

- **Permission Inbox** — every app grouped by what it can do (Accessibility, Screen Recording, FDA, Mic, Camera, Automation, Files & Folders).
- **What Changed** — "Zoom added Screen Recording 3 days ago," "Foo.app added a login item yesterday."
- **Plain-English Risks** — what does Screen Recording actually let an app see?
- **Stale App Review** — apps with powerful permissions you haven't opened in 90+ days.
- **One-click Fixes** — deep links to the right System Settings pane.
- **Weekly Digest** — a small local notification with what's new.

Read-only. No cleaner-tier nonsense. No analytics. No phoning home. Free and open-source under MIT.

## Status

Pre-alpha. Scaffolding in progress. No public release yet — see [`docs/09-roadmap.md`](docs/09-roadmap.md) for milestones.

## Install (once released)

1. Download the latest `.dmg` from the [Releases page](https://github.com/WallyMagill/permission-pulse/releases).
2. Drag **Permission Pulse.app** into `/Applications`.
3. **First launch:** right-click the app and choose **Open**, then click Open in the dialog. macOS will warn the developer is unverified — Permission Pulse is not notarized because there is no paid Apple Developer ID behind it. After the first launch, double-clicking works normally.
4. On the first prompt inside the app, grant **Full Disk Access** in System Settings → Privacy & Security → Full Disk Access. This is required to read the TCC database that lists app permissions. Permission Pulse never writes to that file — only reads.

## Build from source

See [`docs/07-build-and-test.md`](docs/07-build-and-test.md).

## How it works (one paragraph)

Permission Pulse runs as a menu-bar app. On launch it scans (a) the TCC database for granted permissions, (b) `LaunchAgents` and `LaunchDaemons`, (c) BTM-managed background items, and (d) AVFoundation for current mic/cam usage. Each daily snapshot is stored in a local SQLite database under `~/Library/Application Support/com.wallymagill.permissionpulse/`. The "What Changed" view is a diff between today's snapshot and yesterday's (and last week's). Nothing leaves your machine.

## Contributing

Issues and PRs welcome. Read [`docs/03-architecture.md`](docs/03-architecture.md) first to orient. By contributing you agree to license your contributions under MIT.

## License

[MIT](LICENSE).
