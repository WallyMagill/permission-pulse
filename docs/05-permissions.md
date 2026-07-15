# 05 — First-run UX and permissions

Permission Pulse asks for at most one OS-level permission: **Full Disk Access**. It is also delivered unsigned (no Developer ID), so the user must clear Gatekeeper on first launch.

## First-launch sequence

### 1. Gatekeeper

When the user double-clicks `Permission Pulse.app` the first time, macOS shows the "Apple could not verify..." dialog. On macOS 15 (Sequoia) and later — including Tahoe — the right-click → Open override no longer exists for unsigned apps, so the user must:

1. Dismiss that dialog with **Done** (not "Move to Trash").
2. Open **System Settings → Privacy & Security** and scroll to the *"Permission Pulse" was blocked* notice.
3. Click **Open Anyway** and authenticate when prompted.

On macOS 14 (Sonoma) the older right-click the app → **Open** → **Open** shortcut still works. The CLI alternative on any version: `xattr -d com.apple.quarantine "/Applications/Permission Pulse.app"`.

After this, normal double-clicks work.

**Why:** No paid Apple Developer ID exists for this project. Notarization requires one. This is the standard first-launch experience for unsigned OSS Mac tools.

**Where this is documented for users:** the README install section.

### 2. Welcome screen

The first time the app actually runs, the detail window opens with a small Welcome screen explaining:

- What Permission Pulse does (three sentences).
- That it is **read-only** and never modifies system data.
- That the next step is granting Full Disk Access — and what we use it for (read-only access to the user/system TCC databases and the BTM background-items store).
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
| Full Disk Access | User/system TCC and direct BTM reads | TCC `access` rows and the highest-versioned `BackgroundItems-v*.btm` archive | Modify, copy, transmit, or invoke `sudo` for either source |

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
- A degraded or failed domain suppresses the entire daily snapshot, so incomplete coverage cannot create false historical removals.

## Sandbox and entitlements

App is **not sandboxed**. The sandbox forbids reading `/Library/Application Support/com.apple.TCC/TCC.db` even with FDA.

There is no entitlements file and the release verifier rejects any embedded entitlement, including `com.apple.security.get-task-allow`. Hardened Runtime is on. Library validation is on. We sign ad hoc (`-`) until a Developer ID lands.

## What the user can do without launching the app

Nothing. There is no CLI, no launchd-managed daemon, no system extension. Quit the app and Permission Pulse stops doing anything.

## What we leave behind on uninstall

- `~/Library/Application Support/com.wallymagill.permissionpulse/snapshots.db`
- Standard `NSUserDefaults` entries under `com.wallymagill.permissionpulse`

We add a "Reset all data" command in Preferences that deletes both. Documented in the README.
