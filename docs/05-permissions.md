# 05 — First-run UX and permissions

Permission Pulse asks for at most one OS-level permission: **Full Disk Access**. It is also delivered unsigned (no Developer ID), so the user must clear Gatekeeper on first launch.

## First-launch sequence

### 1. Gatekeeper

When the user double-clicks `PermissionPulse.app` the first time, macOS shows the "Apple could not verify..." dialog. On macOS 15 (Sequoia) and later — including Tahoe — the right-click → Open override no longer exists for unsigned apps, so the user must:

1. Dismiss that dialog with **Done** (not "Move to Trash").
2. Open **System Settings → Privacy & Security** and scroll to the *"Permission Pulse" was blocked* notice.
3. Click **Open Anyway** and authenticate when prompted.

On macOS 14 (Sonoma) the older right-click the app → **Open** → **Open** shortcut still works. The CLI alternative on any version: `xattr -d com.apple.quarantine /Applications/PermissionPulse.app`.

After this, normal double-clicks work.

**Why:** No paid Apple Developer ID exists for this project. Notarization requires one. This is the standard first-launch experience for unsigned OSS Mac tools.

**Where this is documented for users:** the README install section.

### 2. Welcome screen

The first time the app actually runs, the detail window opens with a small Welcome screen explaining:

- What Permission Pulse does (three sentences).
- That it is **read-only** and never modifies system data.
- That the next step is granting Full Disk Access — and what we use it for (read-only access to the TCC permission databases and the BTM background-items store). On macOS 27 only the system TCC database is readable; the per-user one is hidden from every app, Full Disk Access included.
- A "Skip for now" button (Launch Agents and live mic/cam remain available without FDA; TCC and direct BTM coverage may degrade or fail).

### 3. Full Disk Access prompt

The Welcome screen has a "Grant Full Disk Access" button that:

1. Opens `System Settings → Privacy & Security → Full Disk Access` via `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`.
2. Shows in-app instructions: "Click the **+** button, choose Permission Pulse, restart Permission Pulse."
3. On next launch, the FDA grant is detected and the Permission Inbox populates.

We do not auto-restart. The user restarts manually. (Auto-relaunch under Tahoe's tighter permissions is fragile.)

## What the app does with each permission

| Permission | Used for | What we read | What we never do |
|---|---|---|---|
| Full Disk Access | TCC and direct BTM reads | TCC `access` rows from the system database (and the per-user database on macOS 26 and earlier); the highest-versioned `BackgroundItems-v*.btm` archive, or on macOS 27 (store v18) every per-user `BackgroundItems-v18-<user UUID>.btm` file | Modify, copy, transmit, or invoke `sudo` for either source |

We never request:
- Microphone, Camera (we observe usage state via public APIs, we don't open devices).
- Contacts, Calendar, Reminders, Photos (we have no use for these).
- Accessibility (we do not synthesize input).
- Screen Recording (we do not capture the screen).
- Location, Bluetooth, anything else.

## Graceful degradation when FDA is denied

If FDA is not granted, the app still runs. The following surfaces remain functional:

- LaunchAgents/Daemons (no FDA required).
- Mic/Cam usage dot.
- "What Changed" comparing snapshots from before FDA was revoked.

Surfaces that degrade:

- Permission Inbox and direct BTM coverage can be unavailable because their protected sources require FDA. Permission Pulse never invokes `sudo` and does not ship an `sfltool` fallback.
- If one user/system TCC source succeeds and another fails, the readable rows remain visible under a **Degraded data** banner naming the omitted source category. If all relevant sources fail, last-known rows remain visible and are labeled stale; with no prior success, the page explicitly says no successful scan is available.
- Stale App Review is recomputed only after a fully complete scan. During degraded or failed coverage, the previous computed list is not replaced from partial evidence.
- A snapshot is written whenever the evidence or coverage changes, and it records each domain's coverage (`complete`, `reduced`, `degraded`, or `failed`). A failed domain stores no rows. History compares a domain only when both snapshots have the same full scope (`complete`↔`complete` or `reduced`↔`reduced`), so incomplete coverage cannot create false historical removals.

## macOS 27

- **TCC.** macOS 27 moved the per-user TCC database out of `~/Library/Application Support/com.apple.TCC/` into a protected system location that Full Disk Access does not open. Permission Pulse treats that missing directory as a source this OS does not expose, not as a failure, and never escalates to reach it. With Full Disk Access it reads only the system database, so the Permission Inbox shows Accessibility, Full Disk Access, Input Monitoring, and Screen Recording, with the banner "System-level permissions only". Snapshots record TCC coverage as `reduced`; two reduced snapshots compare normally.
- **BTM.** Store version 18 splits background items into one `BackgroundItems-v18-<user UUID>.btm` file per user, plus an unsuffixed index file with no items. Permission Pulse reads every per-user file and fails the read if the index lists a user whose file is missing, rather than showing a partial list as complete.

## Sandbox and entitlements

App is **not sandboxed**. The sandbox forbids reading `/Library/Application Support/com.apple.TCC/TCC.db` even with FDA.

There is no entitlements file and the release verifier rejects any embedded entitlement, including `com.apple.security.get-task-allow`. Hardened Runtime is on. Library validation is on. We sign ad hoc (`-`) until a Developer ID lands.

## What the user can do without launching the app

Nothing. There is no CLI, no launchd-managed daemon, no system extension. Quit the app and Permission Pulse stops doing anything.

## What we leave behind on uninstall

- `~/Library/Application Support/com.wallymagill.permissionpulse/snapshots.db`, plus its `snapshots.db-wal` and `snapshots.db-shm` files.
- The `com.wallymagill.permissionpulse` defaults domain (preferences, dismissals, and macOS-written window state).
- Permission Pulse's row in System Settings → Privacy & Security → Full Disk Access. Remove it there before deleting the app.

"Reset All Data" in Preferences deletes the history files and Permission Pulse's own defaults but keeps the app installed. The README's Uninstall section lists the full removal steps.
