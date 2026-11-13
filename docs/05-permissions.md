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

### 2. Welcome window

The first time the app actually runs, it opens a Welcome window (an AppKit-hosted window, reopened later from the dropdown's **Welcome Tour**) with two steps:

- What Permission Pulse does: read-only by design, change tracking, stale permission alerts, no network or analytics.
- **One permission to ask for:** Full Disk Access, and what we use it for (reading the system's permission records; Permission Pulse never writes outside its own data folder). On macOS 27 it adds that macOS only lets apps see system-level permissions: Accessibility, Full Disk Access, Input Monitoring and Screen Recording.
- A **Skip for Now** button (everything except permissions and background items still works without FDA).

### 3. Full Disk Access prompt

The Welcome window's Full Disk Access step has an **Open System Settings** button and numbered steps:

1. The button opens `System Settings → Privacy & Security → Full Disk Access`.
2. "Turn on Permission Pulse under Full Disk Access. If Permission Pulse isn't listed, click + and add it from Applications."
3. "Come back to this window." The window stays open and waits. When the user comes back to the app, Permission Pulse scans again: if access is on it says "Full Disk Access is on. You're all set."; if it still looks off it offers **Reopen Permission Pulse**, because macOS sometimes applies the grant only to a new process.

The app never restarts itself without that click. The skip button reads **Done** once the user has started the flow.

### 4. Full Disk Access lost later

macOS ties a Full Disk Access grant to the signature of the build that received it, and every ad-hoc-signed build has a different one, so each update turns access off. When a scan finds Permissions or Background Items refused for lack of access, the app classifies why:

- **First run** — no earlier snapshot ever captured either section. The Welcome window covers this.
- **Lost after an update** — an earlier snapshot captured them and this build differs from the last one that scanned (`lastLaunchedVersion`).
- **Revoked** — an earlier snapshot captured them in this same build.

For the last two, a "Full Disk Access was turned off" (or "Full Disk Access is off") window opens, outside the menu bar, at most once per build (`fdaPromptShownForVersion`). It shows this copy's path and the same steps, adding "If it already looks on, switch it off and on again", and runs the same wait / check / Reopen loop as the Welcome window. With change alerts on, a notification says the same. The Permissions empty state also explains the off-and-on-again step after an update.

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

- Permissions and direct BTM coverage can be unavailable because their protected sources require FDA. Permission Pulse never invokes `sudo` and does not ship an `sfltool` fallback. The dropdown and Overview say "Full Disk Access is off".
- If one user/system TCC source succeeds and another fails, the readable rows remain visible under a **Degraded data** banner naming the omitted source category. If all relevant sources fail, last-known rows remain visible and are labeled stale; with no prior success, the page explicitly says no successful scan is available, and Overview shows "—" with "Not readable" instead of a count.
- Stale Apps is recomputed after every scan once any snapshot exists, from the grants currently held: after a failed permissions scan those are the last-known rows; after a degraded one, the rows that were readable. The page carries the Permissions availability banner, and when no permissions scan has ever succeeded it says "No Permission Data" instead of "No Stale Apps".
- A snapshot is written whenever the evidence or coverage changes, and it records each domain's coverage (`complete`, `reduced`, `degraded`, or `failed`). A failed domain stores no rows. Each domain is compared only against an earlier snapshot whose coverage it can be compared with (see `docs/04-data-sources.md`, "Baselines and windows"), so incomplete coverage cannot create false historical removals; Recent Changes says why a domain was not compared.

## macOS 27

- **TCC.** macOS 27 moved the per-user TCC database out of `~/Library/Application Support/com.apple.TCC/` into a protected system location that Full Disk Access does not open. Permission Pulse treats that missing directory as a source this OS does not expose, not as a failure, and never escalates to reach it. With Full Disk Access it reads only the system database, so the Permissions page shows Accessibility, Full Disk Access, Input Monitoring, Screen Recording, Remote Desktop, and Endpoint Security, with the banner "System-level permissions only". Snapshots record TCC coverage as `reduced`; two reduced snapshots compare normally, and history recorded on macOS 26 (`complete`) is compared with a macOS 27 scan for the system-level services only, which Recent Changes states. A search for a hidden service explains that macOS 27 hides it and offers its System Settings pane; the dropdown, Overview, the app inspector, and Stale Apps state the reduced scope.
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
