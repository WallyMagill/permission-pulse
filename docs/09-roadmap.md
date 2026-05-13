# 09 — Roadmap

Honest, not aspirational. Each milestone is a single shipped binary on GitHub Releases.

## v0.1.0 — Scaffold (target: this week)

- Xcode project + four SwiftPM packages with smoke tests passing.
- Menu-bar icon and detail window render mock data clearly labeled as mock.
- CI green (build + test).
- No real scanners wired yet.

## v0.2.0 — First real scanner

- `LaunchAgentScannerFS` implemented and shipping real data into the UI.
- Snapshot store writes a daily snapshot.
- Mock badges removed from the LaunchAgents column; everything else still mock.

See `docs/10-first-slice.md` for the spec.

## v0.3.0 — TCC scanner

- `TCCScannerSQLite` implemented.
- FDA permission flow + Welcome screen.
- Permission Inbox renders real TCC data.
- Schema-mismatch banner.

## v0.4.0 — BTM and mic/cam

- `BTMScannerDirect` + `BTMScannerSFL` fallback.
- `MediaUseScannerAVFoundation` for the menu-bar dot.

## v0.5.0 — What Changed and Stale review

- Diff queries against the snapshot store.
- "What Changed" view with yesterday and last-week tabs.
- Stale App Review.

## v0.6.0 — One-click fixes and risk explanations

- Per-permission deep links into System Settings (verified on Sonoma + Sequoia + Tahoe).
- Risk Explanations content (static, ships with the app).

## v0.7.0 — Polish, weekly digest, preferences

- Weekly notification.
- Preferences pane (digest on/off, snapshot retention, "Reset all data").

## v1.0.0 — First public release

- All v1 scope items shipped and tested.
- README screenshots taken.
- GitHub Releases announcement post.
- Optionally Show HN / Product Hunt.

## v1.1 (post-launch)

- Search and filter in the Inbox.
- Export to JSON/Markdown.
- Configurable stale-app threshold.
- Homebrew tap.
- Localization for at least one non-English locale.

## v2 (speculative)

- Sparkle 2 auto-updater (requires Developer ID — separate decision).
- Notarized signed builds (requires Developer ID).
- Per-Mac historical comparison (still local-only — no cloud).
- More scanners as APIs become available.

## Out of plan, ever

- iCloud sync of snapshot data.
- Cloud telemetry of any kind.
- Mac App Store version.
- Removing or modifying any permission programmatically.
