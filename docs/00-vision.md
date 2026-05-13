# 00 — Vision

## Why Permission Pulse exists

macOS asks for powerful permissions over time: Screen Recording, Accessibility, Full Disk Access, microphone, camera, Automation, Files & Folders, login items, background items. After three months, nobody remembers what they granted. Apple's System Settings panes are split by category, never show history, and never explain what a permission actually allows.

The result: most Macs accumulate quiet drift — apps that have permissions they no longer need, background items installed by uninstalled apps, login items the user doesn't recognize. There is no surface in macOS that says "here is what your Mac is currently allowing apps to do, here is what changed, here is what you probably forgot."

Permission Pulse is that surface.

## What it is

A menu-bar app that:

1. Reads the TCC database, LaunchAgents/Daemons, BTM-managed background items, and AVFoundation mic/cam usage.
2. Stores a daily snapshot locally in SQLite.
3. Shows what's currently granted, what changed since yesterday and last week, what looks stale, and a plain-English explanation of what each permission actually lets an app do.
4. Provides deep links to the correct System Settings pane for any change the user wants to make.

## What it is not

- **Not a cleaner.** It does not delete files, kill processes, or modify system state.
- **Not an antivirus.** It does not classify apps as malicious. It surfaces facts; the user judges.
- **Not a sandbox / firewall.** It does not block anything. It reports.
- **Not telemetry.** Nothing leaves the user's machine. No analytics, no opt-in pings.
- **Not a Mac App Store app.** Apple's sandbox makes the core read (TCC.db) impossible inside the sandbox. We do not engineer for MAS at any layer.

## The honest version of the pitch

Most users will install this once, look at what's granted, revoke a couple of things, and forget about it for a month. That's success. The weekly digest is the only reason to keep the app installed long-term — and the digest only matters because the underlying snapshot DB is doing its job quietly in the background.

Permission Pulse is free, MIT-licensed, and distributed on GitHub. There is no paid tier and no upgrade path. If someone forks it and ships a commercial version, that's allowed by the license — and probably evidence the idea has legs.
