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
- That the next step is granting Full Disk Access — and what we use it for ("we read the TCC database so we can list which apps you've granted permissions to").
- A "Skip for now" button (the rest of the app works without FDA; only the Permission Inbox is degraded).

### 3. Full Disk Access prompt

The Welcome screen has a "Grant Full Disk Access" button that:

1. Opens `System Settings → Privacy & Security → Full Disk Access` via `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`.
2. Shows in-app instructions: "Click the **+** button, choose Permission Pulse, restart Permission Pulse."
3. On next launch, the FDA grant is detected and the Permission Inbox populates.

We do not auto-restart. The user restarts manually. (Auto-relaunch under Tahoe's tighter permissions is fragile.)

## What the app does with each permission

| Permission | Used for | What we read | What we never do |
|---|---|---|---|
| Full Disk Access | TCC.db reads (system + user) | The `access` table | Modify, copy, or transmit the file |

We never request:
- Microphone, Camera (we observe usage state via public APIs, we don't open devices).
- Contacts, Calendar, Reminders, Photos (we have no use for these).
- Accessibility (we do not synthesize input).
- Screen Recording (we do not capture the screen).
- Location, Bluetooth, anything else.

## Graceful degradation when FDA is denied

If FDA is not granted, the app still runs. The following surfaces remain functional:

- LaunchAgents/Daemons (no FDA required).
- BTM via `sfltool` fallback (user-driven sudo only; not auto).
- Mic/Cam usage dot.
- "What Changed" comparing snapshots from before FDA was revoked.

Surfaces that degrade:

- Permission Inbox shows an empty state with a clear "Grant Full Disk Access to view permissions" banner and a button to re-open the System Settings pane.
- Stale App Review hides categories that depend on TCC data (Accessibility, Screen Recording, FDA itself).

## Sandbox and entitlements

App is **not sandboxed**. The sandbox forbids reading `/Library/Application Support/com.apple.TCC/TCC.db` even with FDA.

Entitlements (`PermissionPulse.entitlements`):

- `com.apple.security.app-sandbox` → `false`
- `com.apple.security.cs.allow-jit` → `false` (Hardened Runtime on, no JIT needed)
- `com.apple.security.cs.disable-library-validation` → `false`
- `com.apple.security.files.user-selected.read-write` → not needed for v1
- `com.apple.security.network.client` → `false` for v1 (no network access)

Hardened Runtime is on. Library validation is on. We sign ad-hoc (`-`) until a Developer ID lands.

## What the user can do without launching the app

Nothing. There is no CLI, no launchd-managed daemon, no system extension. Quit the app and Permission Pulse stops doing anything.

## What we leave behind on uninstall

- `~/Library/Application Support/com.wallymagill.permissionpulse/snapshots.db`
- Standard `NSUserDefaults` entries under `com.wallymagill.permissionpulse`

We add a "Reset all data" command in Preferences that deletes both. Documented in the README.
