# 01 — Research Notes

**Conducted:** 2026-05-13
**Purpose:** Verify tooling versions and surface area before scaffolding (per project brief §5c).
**Status:** Inputs frozen at this date. Re-verify any version-pinned claim before depending on it.

## TL;DR

The committed stack survives review. Two practical findings change how we scaffold day one:

1. **`openSettings` (the SwiftUI environment action) is broken inside `MenuBarExtra` on macOS 26 Tahoe.** We need a workaround (SettingsAccess library or a hidden pre-Settings `WindowGroup`) from the first commit. The brief assumed it Just Works; it doesn't.
2. **Sparkle 2.9.1 (March 2024) is the latest stable** — two years stale. Deferring Sparkle for v1 was already the plan (no Developer ID), and the stale upstream reinforces it. v1 ships with a manual "Check for updates → open GitHub Releases" link, not Sparkle.

No committed stack item needs to be replaced.

---

## 1. Xcode + Swift versions

- **Answer:** Xcode 26.5 (released 2026-05-12) is current stable. Bundles Swift 6.3. Requires macOS 26.2 Tahoe or later to run.
- **Sources:** https://developer.apple.com/xcode/, https://xcodereleases.com/, https://developer.apple.com/documentation/xcode-release-notes/xcode-26-release-notes
- **What this means for us:** Dev machine (Tahoe) is fine. Deployment-target floor (macOS 14 Sonoma) is independent of Xcode version. No constraint here.

## 2. Swift 6 strict concurrency

- **Answer:** Xcode 26 new-project defaults: Approachable Concurrency = Yes, Default Actor Isolation = MainActor, Strict Concurrency Checking = Complete. Swift 6.2's MainActor-by-default is on.
- **Sources:** https://developer.apple.com/documentation/swift/adoptingswift6, https://www.swift.org/migration/documentation/migrationguide/
- **What this means for us:** Accept the new-project defaults. The brief's rule "`@MainActor` only where Apple already requires it — do not blanket-annotate" still applies — we just no longer have to *manually* annotate, because the compiler infers MainActor by default. We mark `nonisolated` on the rare type that truly needs to live off the main actor (file-I/O scanners, SQLite worker pools). Raw pointers, `deinit`, and synchronous C interop are the friction points to watch.

## 3. Sparkle 2

- **Answer:** Latest stable 2.9.1 (2024-03-29). Min deployment target macOS 10.13. EdDSA signing works for unsigned apps; Developer ID is recommended for safer key rotation but not required to ship updates.
- **Sources:** https://github.com/sparkle-project/Sparkle/releases, https://sparkle-project.org/documentation/
- **What this means for us:** Deferred for v1 (no Developer ID yet). Without Developer ID, every Sparkle-downloaded update is quarantined by Gatekeeper → user must right-click → Open every update, defeating the point. v1 "auto-update" path: a `Check for Updates…` menu item that opens https://github.com/WallyMagill/permission-pulse/releases in the browser. If a Developer ID lands later, we wire Sparkle properly. Also: 2+ years with no stable release suggests the project may be stalling — when we do adopt it, budget time to verify it compiles under Swift 6 strict concurrency (likely need `@preconcurrency import Sparkle`).

## 4. GRDB.swift

- **Answer:** Latest stable v7.10.0 (2025-02-15). GRDB 7 is Xcode 16 / Swift 6 ready; ships a dedicated Swift Concurrency guide. Compiles cleanly under strict-concurrency=complete when consumers follow the guide.
- **Sources:** https://github.com/groue/GRDB.swift/releases, https://swiftpackageindex.com/groue/grdb.swift/documentation/grdb/swiftconcurrency
- **What this means for us:** Direct dependency, no wrapper layer needed. API surface differs materially from GRDB 6 — only consult v7 docs/examples. Record types are Sendable-aware; expect minor annotations in our model layer.

## 5. SwiftParseTCC (reference only)

- **Answer:** https://github.com/slyd0g/SwiftParseTCC — 5 commits total, **no LICENSE file**, 3 forks of no note.
- **What this means for us:** Treat strictly as a schema-documentation primer. Read the code to understand the TCC.db access table layout. **Do not copy or vendor any code** — without a license, copying is legally unsafe. Our TCC reader is hand-written from the schema knowledge.

## 6. Clearance (competitor)

- **Answer:** https://github.com/cch1rag/Clearance — MIT, local-first macOS GUI for viewing **and editing** TCC.db privacy permissions. AppKit + WKWebView UI. Latest v1.0.2 (2026-04-16), 18 commits.
- **What this means for us:** Overlap is on the *read* side only. Their differentiator is editing TCC.db, which requires SIP-disabled machines and/or workarounds we are not pursuing. Our pitch is fundamentally different: hygiene + history + diff, not edit. Worth re-reading their README for UI ideas; not a competitive threat.

## 7. LaunchLens (competitor)

- **Answer:** https://github.com/shiltian/launchlens-macos — MIT, native macOS GUI for launch agents, daemons, login items, and BTM entries. Enumerates BTM by shelling out to `sfltool dumpbtm` and parsing the text output. Very young repo (1 commit on main).
- **What this means for us:** Closest competitor on the LaunchAgents / BTM side. Their `sfltool` shell-out approach is one of two paths we'd take; alternative (preferred) is direct binary-plist parsing of `/private/var/db/com.apple.backgroundtaskmanagement/BackgroundItems-v*.btm` per https://github.com/objective-see/DumpBTM. Direct parsing avoids the sudo prompt but requires FDA. Our `BTMScanner` protocol should accommodate both implementations.

## 8. TCC.db reading

- **Answer:** Reading either user (`~/Library/Application Support/com.apple.TCC/TCC.db`) or system (`/Library/Application Support/com.apple.TCC/TCC.db`) TCC.db requires Full Disk Access. No sanctioned API exists or is rumored. Schema (access table: `service`, `client`, `client_type`, `auth_value`, `auth_reason`, `auth_version`, `csreq`, `indirect_object_identifier`, `flags`, `last_modified`) is stable from Big Sur through Tahoe. Tahoe and late Sequoia tightened `csreq` matching for some services (Input Monitoring confirmed) to anchor on the binary's `cdHash` rather than its signing-cert root.
- **Sources:** https://www.rainforestqa.com/blog/macos-tcc-db-deep-dive, https://github.com/yo-yo-yo-jbo/macos_tcc
- **What this means for us:**
  - Read-only SQLite open via GRDB. Never write.
  - We surface FDA as a first-run blocker for the TCC scanner specifically. The app must run usefully *without* FDA (it can still enumerate LaunchAgents, mic/cam current-use, SMAppService items registered by other apps' bundles when accessible).
  - Tahoe 26.1+ restricts FDA for unsigned **CLI binaries**. We are an `.app` bundle, so this does not apply — but it does mean we keep all TCC.db reads inside the main app process and ship zero bundled CLI helpers that need FDA.
  - Unsigned/ad-hoc-signed apps requesting FDA may show extra warning UI. Document this in `docs/05-permissions.md`.

## 9. `sfltool dumpbtm` on Tahoe

- **Answer:** Still works (`sudo sfltool dumpbtm`). Text-only, undocumented, no JSON option. Alternative: direct binary-plist parsing of `/private/var/db/com.apple.backgroundtaskmanagement/BackgroundItems-v*.btm`.
- **Sources:** https://eclecticlight.co/2025/12/03/manage-login-and-background-items/, https://github.com/objective-see/DumpBTM
- **What this means for us:**
  - `sfltool` requires sudo → unacceptable for a polished UX. Direct .btm parsing requires FDA but no sudo — that's the preferred path.
  - **Unverified:** `objective-see/DumpBTM`'s repo predates Tahoe; the .btm file's version suffix may have bumped (was v7 on Ventura 13.1). Before depending on direct parsing, verify against the actual filename on a Tahoe install — `ls /private/var/db/com.apple.backgroundtaskmanagement/`.
  - `BTMScanner` protocol must support both implementations; `sfltoolBTMScanner` is the fallback when direct parsing fails or returns suspicious data.

## 10. macOS 26 Tahoe — notable changes

- **Answer:** `openSettings` environment action is **broken** inside `MenuBarExtra` on Tahoe (regression vs. macOS 15). Transparent menu bar has visual implications. TCC `csreq` matching tightened (Input Monitoring confirmed; others possible). SMAppService and BTM behavior unchanged in the release notes I could surface.
- **Sources:** https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items, https://mjtsai.com/blog/2025/06/18/showing-settings-from-macos-menu-bar-items/
- **What this means for us:**
  - **`MenuBarExtra` → main window must use a workaround.** Two known patterns: (1) declare a hidden `WindowGroup` *before* the `Settings` scene and route the action through `@Environment(\.openWindow)`; (2) use `orchetect/SettingsAccess`. Decision: implement pattern (1) ourselves — one dependency we don't need. Document the workaround in `docs/03-architecture.md` and add a `// Workaround:` comment in the code with a link to steipete.me.
  - Transparent menu bar: not actionable for v1 (no custom rendering), but the menu-bar icon (`SF Symbol`) should be designed for both backgrounds. Use `Image(systemName:)` with a glyph that renders cleanly inverted.

---

## Red flags (re-summary, prioritized)

| # | Severity | Item | Action |
|---|----------|------|--------|
| 1 | Blocker | `openSettings` broken in MenuBarExtra on Tahoe | Implement hidden-WindowGroup workaround on first scaffold. |
| 2 | Watch | Sparkle 2 stable is 2+ years old | Defer Sparkle for v1; revisit when we have a Developer ID. |
| 3 | Watch | DumpBTM Tahoe compat unconfirmed | Verify .btm file path/version on Tahoe before depending on direct parsing. |
| 4 | Confirmed safe | Tahoe 26.1 FDA restriction for unsigned CLI | We ship a single `.app` bundle; no bundled CLI helpers. |
| 5 | Confirmed safe | SwiftParseTCC unlicensed | Reference only; no vendoring. |
| 6 | Watch | Sparkle Swift 6 strict-concurrency status | When we adopt it, expect `@preconcurrency import Sparkle` and/or a thin wrapper. |

---

## Open questions for follow-up sessions

- Confirm the actual `BackgroundItems-v*.btm` filename on the developer's Tahoe install before implementing the BTM scanner (one shell command, deferred to that slice).
- Survey Apple's WWDC 2026 session list once published for any new privacy/permissions APIs we'd want to use.
