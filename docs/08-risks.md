# 08 — Risks

Four real risks. None are project-killers, all need active mitigation.

## R1 — TCC.db schema fragility

**The risk:** Apple owns the TCC.db schema. They have renamed columns and added new ones in past macOS releases. A point release of Tahoe could land tomorrow that breaks our reader.

**Likelihood:** Medium. Apple has changed the schema roughly once per major macOS version since Catalina.

**Impact:** Permission Inbox reports schema failure and, when available, keeps last-known rows labeled stale until we ship a fix. The rest of the app (LaunchAgents, mic/cam, What Changed against earlier snapshots) keeps working.

**Mitigation:**
- Probe the column list at read time. If we see unexpected columns or missing expected columns, fall back to "schema unknown" banner.
- Model complete/degraded/failed coverage explicitly; never convert schema failure to a valid empty list, and never snapshot incomplete evidence.
- Pin a known-good schema per macOS major in `PermissionsCore`.
- Test fixture: a snapshot of the schema (sql dump of the `access` table structure) per macOS major. Re-record at each major's first beta.
- Maintain a small "what macOS is this" diagnostic in the app's own log file so the user can paste it into a bug report.

## R2 — BTM enumeration is unsupported by Apple

**The risk:** There is no public API for enumerating BTM-managed background items. The two available approaches both have problems: `sfltool dumpbtm` needs sudo (terrible UX) and the `.btm` binary plist format is private (filename version bumps unannounced, structure can change).

**Likelihood:** High that one of the two breaks per macOS major; low that both break simultaneously.

**Impact:** Background Items becomes explicitly degraded or failed. Last-known data remains labeled when available; LaunchAgents/Daemons still work independently.

**Mitigation:**
- `BTMScanner` protocol isolates the shipping direct `.btm` reader. The app does not ship an `sfltool` implementation, invoke `sudo`, or mutate the store.
- Typed complete/degraded/failed availability prevents a scanner failure from looking like a valid empty result. Any degraded or failed domain suppresses snapshot persistence.
- A future manual `sfltool` implementation remains an explicit product decision rather than an automatic fallback.
- Pin the expected `.btm` filename version per macOS major.
- Watch `objective-see/DumpBTM` for upstream fixes; we're not vendoring but the README is a useful smoke signal.

## R3 — Apple ships a native equivalent in a future macOS

**The risk:** macOS 27 or 28 could ship a unified Permissions dashboard inside System Settings that subsumes most of Permission Pulse. Apple's "what changed recently" UI has been improving steadily.

**Likelihood:** Medium-high in the 2-year horizon.

**Impact:** Reduces the marginal value of Permission Pulse. The app doesn't break, but the "wow, finally this exists" reaction dampens.

**Mitigation:**
- This is a free OSS tool. We don't have commercial pressure to differentiate; the niche we serve (history + diff + stale-review + one place to see everything) is still useful even if Apple ships a partial overlap.
- If Apple ships a true full-feature dashboard, we deprecate gracefully and pin the repo as "use macOS X's native panel instead." That is a fine outcome.

## R4 — FDA prompt friction for unsigned apps

**The risk:** Tahoe's tightened security UX makes granting FDA to an unsigned app especially scary for non-technical users. Some users may abandon at this step.

**Likelihood:** Medium for casual users; low for the open-source-Mac-power-user audience this tool will reach first.

**Impact:** Lower install-to-active-use conversion. Acceptable for an OSS tool.

**Mitigation:**
- Welcome screen explains in plain English what FDA is and what we use it for: read-only access to TCC.db and the direct BTM background-items store.
- Provide a "Skip for now" path; the rest of the app continues to function.
- Document the unsigned-app + FDA flow with screenshots in the README.
- When/if a Developer ID lands, this risk substantially drops.

## Risks we are explicitly not engineering against

- **Mac App Store policy changes.** We are not shipping to MAS. Not a risk.
- **Antivirus false-positive on reading TCC.db.** Plausible but rare; we accept it. Surface a one-line note in the README if it actually happens.
- **User runs Permission Pulse as root.** They won't, and if they do, we behave the same as for any normal user.

## Risks the brief flagged that no longer apply

The original brief framed "FDA conversion drag" as a commercial risk (paid-app trial-to-purchase). With the pivot to free OSS, that framing no longer applies. R4 above captures the residual UX-level concern.
