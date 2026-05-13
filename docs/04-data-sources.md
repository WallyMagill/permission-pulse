# 04 — Data sources

Each scanner is documented as: **what it reads, which API, what permission is needed, how fragile it is, what we do when it fails.**

## TCC database

**What:** Granted TCC permissions per app per service.

**Where:**
- User TCC: `~/Library/Application Support/com.apple.TCC/TCC.db`
- System TCC: `/Library/Application Support/com.apple.TCC/TCC.db`

**API:** Direct SQLite read via GRDB.

**Permission needed:** Full Disk Access. Without it, the file is unreadable.

**Schema (v1):** Query the `access` table:

- `service` (TEXT) — e.g. `kTCCServiceScreenCapture`, `kTCCServiceAccessibility`, `kTCCServiceSystemPolicyAllFiles`
- `client` (TEXT) — bundle ID
- `client_type` (INTEGER) — 0 = bundle ID, 1 = absolute path
- `auth_value` (INTEGER) — 0=denied, 1=unknown, 2=allowed, 3=limited
- `auth_reason` (INTEGER) — how it was granted
- `auth_version` (INTEGER)
- `csreq` (BLOB) — code signing requirement
- `indirect_object_identifier` (TEXT) — for Automation, the target app's bundle ID
- `flags` (INTEGER)
- `last_modified` (INTEGER) — Unix timestamp

**Fragility:** High. Apple has renamed/added columns in past macOS releases. We:
- Open the DB read-only.
- Probe the column list before reading; surface a "your macOS schema is unknown to this version of Permission Pulse" banner if we see unexpected columns.
- Pin a schema version per macOS major in `PermissionsCore`.

**Failure mode:**
- FDA not granted → show a clear "Grant Full Disk Access to enable the Permission Inbox" empty state. The rest of the app continues to function.
- Schema mismatch → show the banner above; still render columns we recognize.

---

## LaunchAgents and LaunchDaemons

**What:** Property-list-defined launch agents (per user) and daemons (system) that auto-run.

**Where:**
- `~/Library/LaunchAgents/`
- `/Library/LaunchAgents/`
- `/Library/LaunchDaemons/`
- `/System/Library/LaunchAgents/` and `/System/Library/LaunchDaemons/` (read for context but NOT shown by default — these are Apple-owned).

**API:** `FileManager.contentsOfDirectory(at:...)` + `PropertyListDecoder`.

**Permission needed:** None for `~/Library/LaunchAgents/` and the public `/Library/Launch*` paths. FDA NOT required.

**Schema:** Standard `launchd.plist` keys (`Label`, `Program`, `ProgramArguments`, `RunAtLoad`, `KeepAlive`).

**Fragility:** Low. The plist format is stable; the file locations have been the same since Lion.

**Failure mode:**
- File permissions denied on a specific plist → log and skip; continue with the rest.
- Malformed plist → log and skip.

---

## BTM (Background Task Management)

**What:** Apps registered with macOS's Background Task Management — the modern unified location for login items, agent daemons, and helper tools.

**Where:**
- `/private/var/db/com.apple.backgroundtaskmanagement/BackgroundItems-v*.btm` (binary plist)
- (alternative) `sudo sfltool dumpbtm` (text output)

**API:** Two implementations, both feasible:

1. **`BTMScannerDirect`** — `PropertyListDecoder` over the `.btm` binary plist. Needs FDA. No sudo. Schema is private and Apple has bumped the version suffix (`v7`, `v8`, …) on macOS majors. Preferred when it works.
2. **`BTMScannerSFL`** — `Process` shell-out to `sfltool dumpbtm` + text parse. Requires sudo prompt the user invokes manually (we do not invoke sudo automatically). Falls back when direct parsing fails.

**Permission needed:** Either FDA (direct) or admin-via-Terminal (SFL fallback — user-driven).

**Fragility:** Very high. No public API. Filename version bumps unannounced. Output format of `sfltool` is undocumented and has changed before.

**Failure mode:**
- Both scanners fail → show "BTM enumeration unavailable on this macOS — we'll add support as soon as we figure out the new format" empty state. The rest of the app continues to function. The user is told this is not their fault.

---

## Microphone / Camera current use

**What:** Which app is *currently* using the mic or camera, used to drive a menu-bar dot indicator (orange = mic, green = camera).

**API:** `AVCaptureDevice` observation. We never open the device ourselves.

**Permission needed:** None to *observe* (we don't open the device). We never request mic/cam access ourselves.

**Fragility:** Low-medium. Apple has changed the observation APIs once or twice but the current ones are stable.

**Failure mode:**
- API returns nothing → no dot shown; not an error.

---

## Last-launch date (for Stale App Review)

**What:** When the user last launched a given app.

**API:** No public macOS API for last-launch date per app. Proxies:
- `URL.contentModificationDateKey` on the `.app` bundle — close-enough for most apps.
- `mdls -name kMDItemLastUsedDate` (Spotlight metadata) — accurate, but requires shelling out.

**Permission needed:** None for the file proxy. None for `mdls` (unprivileged).

**Fragility:** Medium. Spotlight metadata can be stale or unindexed.

**Failure mode:** App is omitted from Stale review if no usable date is found. Better to under-flag than over-flag.

---

## Per-folder grants (Files & Folders)

**What:** TCC entries for specific user folders (Desktop, Documents, Downloads, iCloud Drive, etc.) — service `kTCCServiceSystemPolicyDesktopFolder` and friends.

**API:** Same TCC.db reader as above; service prefix filter.

**Permission needed:** FDA (read of TCC.db).

**Fragility:** Same as TCC.db.

**Failure mode:** Same as TCC.db.

---

## Permission summary

| Source | Permission required | Fragility | If unavailable |
|---|---|---|---|
| TCC.db | FDA | High | Inbox shows "needs FDA" empty state |
| LaunchAgents/Daemons (public) | None | Low | always works |
| BTM (direct .btm) | FDA | Very high | falls back to SFL or empty state |
| BTM (sfltool) | Manual sudo | High | falls back to empty state |
| Mic/Cam observation | None | Low-medium | menu-bar dot hidden |
| Last-launch date | None | Medium | app omitted from Stale review |
