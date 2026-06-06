# 02 — v1 Scope

All v1 features ship in the free, open-source build. There is no paid tier.

## In scope for v1

### Screen 1 — Permission Inbox

Menu-bar drop-down + detail window section. Apps grouped by the TCC service they hold:

- Accessibility
- Screen Recording
- Full Disk Access (FDA)
- Microphone
- Camera
- Automation (AppleEvents target)
- Files & Folders (per-folder grants)

**Acceptance:** Given FDA is granted and TCC.db is readable, the Inbox lists every app in each category with: app name, bundle ID, icon, granted date (from `last_modified`), and a "Reveal in System Settings" deep link.

### Screen 2 — What Changed

Lists changes between today's snapshot and yesterday's, and a separate "last 7 days" view.

- **New grants:** "Zoom added Screen Recording 3 days ago"
- **New background items:** "Foo.app added a login item yesterday"
- **Removed grants** (when an app or permission disappears)

**Acceptance:** With at least two daily snapshots in the database, the view lists the deltas accurately, sorted newest first.

### Screen 3 — Risk Explanations

Plain-English description of what each TCC service actually allows. Static content; ships with the app.

**Acceptance:** Tapping any service header shows the explanation. Content reviewed once per macOS major.

### Screen 4 — Stale App Review

Apps that hold powerful permissions but haven't been launched in ≥ 90 days.

We approximate "last launched" with a combination of `URL.contentModificationDateKey` on the `.app` bundle and `mdls -name kMDItemLastUsedDate`, picking the most recent of the two.

**Acceptance:** Lists apps where (permission ∈ {Accessibility, Screen Recording, FDA}) AND (last-touched > 90 days). The threshold defaulted to a 90-day constant initially and became **user-configurable in v0.7.0** (30–365 days, Preferences → Snapshots).

### Screen 5 — One-Click Fixes

Deep links into the correct System Settings pane. Uses `x-apple.systempreferences:` URLs. Maintained per macOS major (Sonoma, Sequoia, Tahoe all use compatible URLs as of 2026-05).

**Acceptance:** Every grant has a "Reveal" button that opens the exact pane and section. No 404s.

### Screen 6 — Weekly Digest Notification

Once per week, on Monday 09:00 local time. Local notification only. Summary: "N new permissions, M new background items, K stale apps."

**Acceptance:** Notification fires when run for 7+ days. Summary numbers match the underlying snapshot diffs. User can disable in preferences.

## Explicitly out of scope for v1

- **No edit.** Permission Pulse never writes to TCC.db, BTM files, LaunchAgents directories, or any system database. All "fixes" are deep links into System Settings.
- **No remote sync.** Snapshot DB is local-only. No iCloud, no cross-Mac history.
- **No multi-user.** Single user / single login.
- **No iOS companion.**
- **No commercial features.** No license gating, no paid tier, no upgrade prompts.
- **No analytics or telemetry.**
- **No malware classification.** We do not say "this app is bad" — only "this app has these permissions, and here is what they let it do."

## Stretch — possibly v1, more likely v1.1

- **Export to JSON/Markdown** for the user's own records. (Not yet shipped.)
- **Search and filter** in the Inbox. (Shipped — the detail window has a toolbar search that filters every page.)
- **Quick revoke helper** showing the bundle ID for `tccutil reset` next to the System Settings deep link. (Not yet shipped.)

## Anti-scope — never in this product

- Cleaning, optimization, "free up RAM" features.
- Hosted/cloud anything.
- Reading file *contents* (we only read metadata, paths, plists).
- Modifying anything outside our own application support directory.
