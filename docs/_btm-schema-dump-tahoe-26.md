# BTM `.btm` schema dump — macOS Tahoe (26)

Captured 2026-05-14 from Wally's dev machine. This file feeds
`BTMScannerDirect`'s class-name registration (`"ItemRecord"` →
`BTMItemRecordShim`), top-level key validation, and the `type` /
`disposition` translation tables.

Re-capture if `ScannerError.schemaMismatch` starts firing on a newer
macOS build.

## Storage path

```
$ sudo ls -la /private/var/db/com.apple.backgroundtaskmanagement/
drwxr-xr-x    4 root  wheel    128 May 14 14:05 .
drwxr-xr-x  132 root  wheel   4224 May 13 13:06 ..
-rw-r--r--    1 root  wheel  57373 Apr  2 16:09 BackgroundItems-v13.btm
-rw-r--r--    1 root  wheel  85000 May 14 14:05 BackgroundItems-v16.btm
```

Two `.btm` files coexist on Tahoe 26. The scanner globs
`BackgroundItems-v*.btm` and picks the highest integer suffix; the
lower-version file appears to be legacy retained for downgrade paths and
is ignored.

The directory is root-owned and FDA-gated — granting Full Disk Access to
the `.app` is sufficient for read access; **no `sudo` is required at
runtime**. The `sudo` above is just because the dump was captured from a
plain `Terminal.app` without FDA.

## Top-level archive layout

`.btm` is **NSKeyedArchiver**-encoded, not a plain binary plist. The
archive's `$top` section keys are:

```
"$archiver" => "NSKeyedArchiver"
"$objects"  => [ ... UID-referenced object graph ... ]
"$top"      => { "store" => UID -> $objects[1], "version" => 16 }
"$version"  => 100000
```

Two important deviations from the typical NSKeyedArchiver layout:

1. The root object is stored under the key **`"store"`**, not the
   standard `NSKeyedArchiveRootObjectKey` (which is `"root"`). Passing
   `"root"` to `decodeObject(forKey:)` returns `nil`.
2. Alongside the store, `$top` also carries an integer `"version"` that
   matches the filename suffix (`16` for `BackgroundItems-v16.btm`).
   v0.4.0 ignores this; future slices could use it for an extra
   sanity-check.

The object at `$objects[1]` is **not** a plain `NSDictionary`. It is an
instance of a private Apple class called `Storage` (see object 827 in
the dump — `"$classname" => "Storage"`). The `Storage` class has a
single field of interest to us:

| `Storage` field | Type | v0.4.0 use |
|---|---|---|
| `itemsByUserIdentifier` | `NSDictionary` (keyed by user UUID) | **read** |
| `mdmPaloadsByIdentifier` | `NSDictionary` (sic: Apple's typo "Paloads") | not read |
| `userSettingsByUserIdentifier` | `NSDictionary` (per-user settings → `BTMUserSettings` instances) | not read |

`PropertyListDecoder` does **not** work here — calling it returns the
raw graph rather than the rewired root object. `NSKeyedUnarchiver` does
the UID dereferencing, but only if we register both private classes
(`Storage` and `ItemRecord`) so the archive's `$class` UIDs resolve:

```swift
let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
unarchiver.requiresSecureCoding = false
unarchiver.setClass(BTMStorageShim.self,    forClassName: "Storage")
unarchiver.setClass(BTMItemRecordShim.self, forClassName: "ItemRecord")
let storage = unarchiver.decodeObject(forKey: "store") as? BTMStorageShim
let items   = storage?.itemsByUserIdentifier
```

## Storage root object

`mdmPaloadsByIdentifier` is misspelled in Apple's own data (it's been
shipped that way for years). Preserve the typo if you ever read it — do
**not** "fix" it.

## User-identifier sentinels

`itemsByUserIdentifier` is keyed by user UUID strings. Two sentinel
UUIDs appear on every system:

| UUID | Meaning | `BTMItem.Scope` |
|---|---|---|
| `FFFFEEEE-DDDD-CCCC-BBBB-AAAAFFFFFFFE` | root / UID -2 (system administrator bucket) | `.user` |
| `FFFFEEEE-DDDD-CCCC-BBBB-AAAA00000000` | system / UID 0 | `.system` |
| any other UUID | real local user | `.perUser(uuid:)` |

These sentinel constants are duplicated in `BTMScannerDirect` and in
`BTMFixtures` for tests. Update both if Apple ever changes them.

## `ItemRecord` schema

Each element in the per-user `NSArray` is an `ItemRecord` (private
Objective-C class). Fields observed on this machine, derived from the
Zoom daemon entry (`$objects[7]`) and matched against `sfltool dumpbtm`
human output:

| On-disk key | Objective-C type | Swift type | Used in v0.4.0 |
|---|---|---|---|
| `identifier` | `NSString` | `String` | yes (primary key) |
| `name` | `NSString` | `String` | yes (display) |
| `developerName` | `NSString` | `String?` | yes |
| `bundleIdentifier` | `NSString` | `String?` | yes |
| `teamIdentifier` | `NSString` (10 chars) | `String?` | yes |
| `container` | `NSString` | `String?` (→ `parentIdentifier`) | yes |
| `type` | `NSNumber` (Int) | `Int` (mapped to enum) | yes |
| `disposition` | `NSNumber` (Int, bitmask) | `Int` (bit 0 only in v0.4.0) | yes |
| `modificationDate` | `NSNumber` (`Double`, `CFAbsoluteTime`) | `Date` | yes |
| `executableModificationDate` | `Double` (CFAbsoluteTime) | — | deferred |
| `executablePath` | `NSString` | — | deferred |
| `url` | `NSURL` (file://) | — | deferred |
| `flags` | `NSNumber` (Int, bitmask) | — | deferred |
| `programArguments` | `NSArray<NSString>` | — | deferred |
| `bookmark` | `NSData` | — | deferred |
| `sha256` | `NSData` | — | deferred |
| `lightweightRequirement` | `NSData` | — | deferred |
| `designatedRequirement` | `NSString` | — | deferred |
| `uuid` | `NSUUID` | — | deferred |
| `generation` | `NSNumber` (Int) | — | deferred |
| `associatedBundleIdentifiers` | `NSArray<NSString>` | — | deferred |
| `items` | `NSArray<NSString>` (child identifiers, for developer-group rows) | — | deferred — we keep the parent's `identifier` on children via `container` instead |

Decoders for new on-disk fields can be added to `BTMItemRecordShim`
without breaking existing scans — `NSCoding` ignores unknown keys.

## `type` enum values

| Decimal | Hex | `BTMItem.ItemType` |
|---|---|---|
| 2 | `0x2` | `.app` |
| 32 | `0x20` | `.developerGroup` — parent grouping (filtered from UI) |
| 65 552 | `0x10010` | `.legacyDaemon` |
| else | — | `.unknown(rawValue:)` — surfaced in UI as "Unknown item type · 0xNN" |

## `disposition` bitmask

Observed values, with the `sfltool dumpbtm` human translation:

| Hex | Decimal | sfltool translation | v0.4.0 mapping |
|---|---|---|---|
| `0xb` | 11 | `[enabled, allowed, notified]` | `.enabled` |
| `0x2` | 2 | `[disabled, allowed, not notified]` | `.disabled` |
| `0x0` | 0 | (unobserved here) | `.disabled` |

Inferred bit layout (verify before encoding more bits):

- Bit 0 (`& 0x1`) — **enabled / disabled** — encoded in v0.4.0.
- Bit 1 (`& 0x2`) — **allowed by policy / blocked** — TBD; needs more
  samples before surfacing.
- Bit 3 (`& 0x8`) — **notified to user / not notified** — TBD; UX-only
  signal, low priority.

If a user reports "this is allowed but Permission Pulse says disabled",
revisit and add bits 1/3.

## `flags` bitmask

Informational only — not consumed by v0.4.0:

| Hex | Meaning |
|---|---|
| `0x0` | none |
| `0x1` | legacy |
| `0x4` | curated |
| `0x5` | legacy + curated |

## Sample `sfltool dumpbtm` output (reference only)

`sfltool dumpbtm` requires `sudo` and **is not invoked by the shipping
app** (CLAUDE.md hard rule). Capture below is from the same machine for
comparison with the direct decode:

```
========================
 Records for UID -2 : FFFFEEEE-DDDD-CCCC-BBBB-AAAAFFFFFFFE
========================

 ServiceManagement migrated: true
 LaunchServices registered: false

 Items:

 #1:
                 UUID: F9B68A0D-E02A-4EFC-87E8-02992E38A9E0
                 Name: Docker
       Developer Name: Docker
                 Type: developer (0x20)
                Flags: [ curated ] (0x4)
          Disposition: [disabled, allowed, not notified] (0x2)
           Identifier: Docker
                  URL: (null)
           Generation: 0
  Embedded Item Identifiers:
    #1: 16.com.docker.vmnetd

 #2:
                 UUID: 423B0467-EA09-470E-AA74-51CB45E753E7
                 Name: com.docker.vmnetd
       Developer Name: Docker
      Team Identifier: 9BNSXJN65R
                 Type: legacy daemon (0x10010)
                Flags: [ legacy, curated ] (0x5)
          Disposition: [enabled, allowed, notified] (0xb)
           Identifier: 16.com.docker.vmnetd
                  URL: file:///Library/LaunchDaemons/com.docker.vmnetd.plist
      Executable Path: /Library/PrivilegedHelperTools/com.docker.vmnetd
           Generation: 3
    Assoc. Bundle IDs: [ com.docker.docker ]
    Parent Identifier: Docker
```

## Notes for the implementer

- **Discovery:** glob `BackgroundItems-v*.btm`, parse the integer suffix,
  pick the highest. On Tahoe today: v13 + v16 — v16 wins.
- **Schema validation:** mirror `TCCScannerSQLite.validateSchema`. Throw
  `.schemaMismatch` if the archive's `"store"` key is missing, if its
  class isn't `Storage`, or if `Storage.itemsByUserIdentifier` is nil.
- **Failure semantics:**
  - I/O failure on `Data(contentsOf:)` → `.permissionDenied` (FDA is the
    typical cause).
  - Empty file → `.schemaMismatch` (clearly broken, not a permissions
    issue).
  - Unarchive throws → `.schemaMismatch`.
  - Top-level key missing → `.schemaMismatch`.
- **v13 vs v16 divergence:** We've only verified v16 on this machine.
  The shim only reads fields by name and ignores unknowns, so v13 should
  decode if the field names are stable. Reconsider if a Sequoia user
  reports a `.schemaMismatch`.
- **`disposition` interpretation:** bit 0 only in v0.4.0. Flag in
  `13-btm-slice.md` as a known unknown.
