# 13 — Fourth slice: BTM scanner

**Status:** Implemented v0.4.0 — 2026-05-14.

## Why this slice

- The roadmap had `v0.4.0 — BTM and mic/cam` as a single line. The Tahoe
  schema dump (see `docs/_btm-schema-dump-tahoe-26.md`) revealed the
  `.btm` format is NSKeyedArchiver, not a plain plist, and that two file
  versions (`v13`, `v16`) coexist on disk. That bumped BTM from "small
  scanner" to "highest-fragility surface in the project".
- BTM is the modern unified registry for login items, agent daemons, and
  helper tools. Users want to see what's registered. Apple offers no
  public API.
- Splitting the slice (BTM here; mic/cam + menu-bar icon to v0.4.1) lets
  each ship and revert independently and mirrors the v0.3.0 → v0.3.1
  cadence.

## What shipped

1. **`BTMScannerDirect`** reads
   `/private/var/db/com.apple.backgroundtaskmanagement/BackgroundItems-v*.btm`
   via `NSKeyedUnarchiver` with `requiresSecureCoding = false`. Globs the
   directory and picks the highest version suffix on disk.
2. **`BTMItemRecordShim`** and **`BTMStorageShim`** are
   `final class NSObject, NSCoding` Swift types that match Apple's two
   private classes encoded inside the archive. The archive's `$top`
   key is `"store"` (not the default `"root"`), and the store is an
   instance of a private `Storage` class whose `itemsByUserIdentifier`
   field holds the per-user dictionary. We register both shims with
   the unarchiver so the archive's `$class` UIDs resolve to our Swift
   types. Each shim reads only the fields v0.4.0 surfaces and ignores
   unknown encoded keys.
3. **`BackgroundItemsSection` SwiftUI view** renders enabled and disabled
   background items with name + developer name + scope + type metadata,
   plus a disposition badge. Developer-group parents are filtered out;
   their identifier is surfaced as `"under <parent>"` on child rows so
   the relationship is still visible.
4. **Generalized `PermissionsEmptyStateView` and `SchemaMismatchBanner`**
   across TCC and BTM domains via a `ScannerDomain` parameter
   (default `.tcc` to keep existing call sites unchanged). FDA empty
   state, FDA disclosure body, "permissions unavailable" headline,
   "Unrecognized X schema" banner — all branch on the domain.
5. **Unified menu-bar FDA rollup.** `MenuBarContentView`'s
   `statusArea` now resolves to one of four states based on
   `tccScanError` + `btmScanError`. First match wins:
   1. TCC `.permissionDenied` → "Full Disk Access needed" (covers
      both-denied since FDA fixes both).
   2. BTM `.permissionDenied` only → "Full Disk Access needed for
      background items".
   3. Any `.schemaMismatch` / `.unsupportedOnThisOS` → "Permission Pulse
      schema mismatch" (opens detail window; banners inside
      disambiguate).
   4. Clean → two count rows ("N permissions tracked", "M background
      items").
6. **`MockBTMScanner`** with three labeled items (enabled app, enabled
   legacy daemon under a parent, disabled app) so the UI exercises every
   state without a real `.btm` read.

## Data flow

```
BTMScannerDirect.scan() throws ScannerError
        │
        ▼
ScanCoordinator.runScan()  (three async let child tasks — TCC, LA, BTM)
        │   on success      → viewModel.btmItems / btmDataSource / btmScanError = nil
        │   on ScannerError → viewModel.btmScanError = error
        │   on other Error  → viewModel.btmScanError = .permissionDenied(...)
        ▼
AppViewModel.btmItems / btmDataSource / btmScanError  (new @Observable)
        │
        ├─→ MenuBarContentView.statusArea — unified TCC + BTM rollup
        ├─→ DetailWindowView — second SchemaMismatchBanner branch + section
        └─→ BackgroundItemsSection — list rows, or PermissionsEmptyStateView(.btm)
```

## Files touched

- **New:**
  - `Packages/PermissionsCore/Sources/PermissionsCore/BTMItem.swift`
  - `Packages/PermissionsScanners/Sources/PermissionsScanners/BTMScannerDirect.swift`
  - `Packages/PermissionsScanners/Sources/PermissionsScanners/BTMItemRecordShim.swift`
  - `Packages/PermissionsScanners/Sources/PermissionsScanners/MockBTMScanner.swift`
  - `Packages/PermissionsScanners/Tests/PermissionsScannersTests/BTMFixtures.swift`
  - `Packages/PermissionsScanners/Tests/PermissionsScannersTests/BTMFixturesRoundTripTests.swift`
  - `Packages/PermissionsScanners/Tests/PermissionsScannersTests/BTMScannerDirectTests.swift`
  - `Packages/PermissionsScanners/Tests/PermissionsScannersTests/MockBTMScannerTests.swift`
  - `Packages/PermissionsUI/Sources/PermissionsUI/BackgroundItemsSection.swift`
  - `Packages/PermissionsUI/Sources/PermissionsUI/ScannerDomain.swift`
  - `Packages/PermissionsUI/Tests/PermissionsUITests/AppViewModelBTMStateTests.swift`
  - `docs/_btm-schema-dump-tahoe-26.md`
  - `docs/13-btm-slice.md` (this file)

- **Modified:**
  - `Packages/PermissionsCore/Sources/PermissionsCore/Scanners.swift` — added `BTMScanner` protocol.
  - `Packages/PermissionsUI/Sources/PermissionsUI/AppViewModel.swift` — added `btmItems`, `btmDataSource`, `btmScanError`.
  - `Packages/PermissionsUI/Sources/PermissionsUI/PermissionsEmptyStateView.swift` — domain parameter.
  - `Packages/PermissionsUI/Sources/PermissionsUI/SchemaMismatchBanner.swift` — domain parameter.
  - `Packages/PermissionsUI/Sources/PermissionsUI/MenuBarContentView.swift` — unified status area.
  - `Packages/PermissionsUI/Sources/PermissionsUI/DetailWindowView.swift` — new section + second banner.
  - `PermissionPulse/PermissionPulse/ScanCoordinator.swift` — three-way parallel scan.
  - `docs/04-data-sources.md` — BTM section updated.
  - `docs/09-roadmap.md` — v0.4.0 split into BTM (done) and v0.4.1 (mic/cam + icon).

## Test coverage

- `BTMFixturesRoundTripTests` — 1 case asserting archive → unarchive identity through the shim.
- `BTMScannerDirectTests` — 11 cases (parameterized `type` mapping expands to 4, parameterized `disposition` mapping expands to 3, so 18 sub-cases total):
  - returns items for a valid fixture
  - filters developer groups but preserves children
  - maps the type bitmask (parameterized)
  - maps the disposition bitmask bit 0 (parameterized)
  - picks the highest version suffix on disk
  - throws `.schemaMismatch` when the top-level key is missing
  - throws `.schemaMismatch` on a malformed (zero-byte) file
  - throws `.permissionDenied` when the file is unreadable (CI-disabled)
  - returns empty for an empty `itemsByUserIdentifier`
  - scan is deterministically ordered
  - attributes sentinel UUIDs to the correct scope
- `MockBTMScannerTests` — 1 case asserting the three mocked items load.
- `AppViewModelBTMStateTests` — 6 cases mirroring `AppViewModelErrorStateTests` for the new `btmScanError` / `btmDataSource` / `btmItems` properties.

Test counts: 48 (v0.3.1) → 64 visible tests across the four packages.
The Xcode app target's test host stays a no-op per `docs/03-architecture.md`.

## Sentinel user UUIDs

| UUID | Scope |
|---|---|
| `FFFFEEEE-DDDD-CCCC-BBBB-AAAAFFFFFFFE` | `.user` (root / UID -2) |
| `FFFFEEEE-DDDD-CCCC-BBBB-AAAA00000000` | `.system` (UID 0) |
| any other UUID | `.perUser(uuid:)` |

Defined as static constants on `BTMScannerDirect` and `BTMFixtures`.

## Disposition encoding

v0.4.0 reads **bit 0 only**: `disposition & 1 != 0 → .enabled`, else
`.disabled`. The other documented bits (allowed/blocked, notified/not)
are tracked in `docs/_btm-schema-dump-tahoe-26.md` as known unknowns.

## Deferred to later slices

- **`BTMScannerSFL` fallback** (text-parse of `sfltool dumpbtm`) — requires
  user-invoked `sudo`, awkward UX. Defer until / unless users push back
  on the FDA-only path.
- **Mic/cam current use + state-driven `MenuBarExtra` icon** → v0.4.1.
- **Snapshot store** (`background_items` table in GRDB) and "What
  Changed" diff for BTM → v0.5.0.
- **Tree view** (developer-group → child item nesting) → v0.5.0.
- **Jump to Login Items pane** deep link from a BTM row → v0.6.0.
- **`csreq` / cdHash verification** of BTM rows → v0.6.0+.
- **Multi-user macOS attribution nuance** → TBD.
- **Disposition bits 1 / 3** (allowed-by-policy, notified) → revisit if
  users report state-mismatch.

## Known visual polish deferred to v0.4.x / v0.5.0

Functionality in v0.4.0 is correct (scanner, schema validation, FDA
rollup, attention-row priority, deep-linking, scan-on-launch). Some
SwiftUI rendering on Tahoe 26 does not match the intent and is deferred
to a follow-up UX slice:

- **Mock badge visibility on FDA-denied sections.** Logic to hide the
  badge when `*ScanError` is non-nil is in `DetailWindowView` and
  `BackgroundItemsSection`, but the badge still renders on Tahoe 26 in
  practice. Likely a SwiftUI `Section` re-evaluation issue.
- **Grant Access in System Settings button rendering.** The button is
  in the empty-state view with `.borderedProminent` + `.controlSize(.large)`
  + `.tint(.blue)` + explicit HStack content, but is not visible on Tahoe
  26 inside a `List` section. The menu-bar attention row deep-links
  correctly as a workaround.
- **No native FDA grant modal.** macOS does not expose a public API to
  present a "Grant FDA?" prompt. Apps that appear to do this are
  showing a custom `NSAlert`-style dialog and then deep-linking. A
  guided custom dialog could be added in a v0.5.0 UX polish slice.

## Tahoe-specific risks (documented)

- **v13 vs v16 file-version divergence.** Only v16 verified on this
  machine. The shim ignores unknown keys, so a v13 file with the same
  field names should decode. If a Sequoia user files an issue, we'll see
  it as `.schemaMismatch` rather than a crash.
- **`NSKeyedUnarchiver(forReadingFrom:)` is the legacy non-secure-coding
  path.** Required because Apple did not opt the `.btm` archive into
  `NSSecureCoding`. If the legacy path is ever removed, we fall back to
  a manual `$objects` graph walk.
- **`mdmPaloadsByIdentifier` is Apple's typo** — preserve, do not "fix"
  in any future cleanup.

## Done means

- All four package test suites pass (`swift test` on each).
- Xcode build succeeds (`xcodebuild ... -scheme PermissionPulse`).
- Launching the app on Tahoe with FDA granted: three sections render
  (Permissions, Launch Agents, Background Items); BTM rows match what
  System Settings → General → Login Items & Extensions shows.
- Toggling FDA off: BTM section shows the FDA empty-state CTA; menu bar
  shows one unified "Full Disk Access needed" row.
- Toggling FDA back on: both sections recover after a Refresh.
