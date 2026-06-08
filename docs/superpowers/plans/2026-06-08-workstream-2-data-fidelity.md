# Workstream 2 — Data Fidelity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the app silently merging or dropping permission data: unify the TCC identity key, capture `auth_value` (so limited-Photos access appears), preserve BTM disposition bits losslessly, handle `KeepAlive`-as-dictionary and `Disabled` in Launch Agents, and guard the GRDB date-column encoding.

**Architecture:** Five independent fixes (D1–D5). Pure-data/logic changes get full RED→GREEN unit tests. D2 adds one additive GRDB migration (v4). D1 centralizes the TCC identity into a single `PermissionGrant.identityKey` used by the scanner, the store diff engine, the dismiss keys, and SwiftUI bindings. D3 captures BTM raw bits with custom Equatable/Hashable that excludes the forensic field so diffs stay clean. The deeper *representation* work (showing `auth_value`/disposition changes as diff rows, sub-service granularity) stays the separately-tracked v0.8.x model-fidelity slice — this plan does capture only.

**Tech Stack:** Swift 6.0 (MainActor-by-default), GRDB 7.10, Swift Testing, Xcode 26. Local SwiftPM packages: PermissionsCore (models), PermissionsScanners (scanners), PermissionsStore (GRDB store + diff), PermissionsUI (views/VMs).

**Source spec:** `docs/superpowers/specs/2026-06-06-app-quality-audit-design.md` (Workstream 2).

**Conventions:**
- Commit attribution disabled — no `Co-Authored-By` trailer.
- All user-facing strings via `String(localized:)`.
- Package tests: `swift test --package-path <pkg> --filter <name>`. SourceKit "No such module" warnings are known false positives — trust `swift build`/`swift test`.

---

## File Structure

**Task 1 (D1 — unify TCC identity key):**
- Modify: `Packages/PermissionsCore/Sources/PermissionsCore/PermissionGrant.swift` (add `appKey`/`identityKey`; route `id` through it)
- Modify: `Packages/PermissionsScanners/Sources/PermissionsScanners/TCCScannerSQLite.swift` (`identityKey` delegates to the model)
- Modify: `Packages/PermissionsStore/Sources/PermissionsStore/SnapshotStore.swift` (`tccGrantIdentityKey` delegates)
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/DiffEntryKey.swift` (granted/revoked use `identityKey`)
- Test: `Packages/PermissionsCore/Tests/PermissionsCoreTests/PermissionGrantIdentityTests.swift` (new) + adjust `Packages/PermissionsStore/Tests/PermissionsStoreTests/TCCDiffTests.swift` if it codified the old collapse

**Task 2 (D2 — capture auth_value):**
- Modify: `Packages/PermissionsCore/Sources/PermissionsCore/PermissionGrant.swift` (+`authValue`)
- Modify: `Packages/PermissionsScanners/Sources/PermissionsScanners/TCCScannerSQLite.swift` (`>= 2`, pass authValue)
- Modify: `Packages/PermissionsStore/Sources/PermissionsStore/SnapshotStore.swift` (v4 migration + insert/read auth_value)
- Test: `Packages/PermissionsScanners/Tests/PermissionsScannersTests/TCCScannerSQLiteTests.swift` (+limited-access case), `Packages/PermissionsStore/Tests/PermissionsStoreTests/PermissionsStoreTests.swift` (+round-trip + schemaVersion)

**Task 3 (D3 — preserve BTM disposition raw):**
- Modify: `Packages/PermissionsCore/Sources/PermissionsCore/BTMItem.swift` (+`dispositionRaw` + custom Equatable/Hashable excluding it)
- Modify: `Packages/PermissionsScanners/Sources/PermissionsScanners/BTMScannerDirect.swift` (populate `dispositionRaw`)
- Modify: `Packages/PermissionsStore/Sources/PermissionsStore/SnapshotStore.swift` (write/read `disposition_raw` always)
- Test: `Packages/PermissionsStore/Tests/PermissionsStoreTests/BTMDiffTests.swift` or a new store test (round-trip + no diff noise)

**Task 4 (D4 — KeepAlive-dict + Disabled):**
- Modify: `Packages/PermissionsCore/Sources/PermissionsCore/LaunchAgentItem.swift` (+`isDisabled`)
- Modify: `Packages/PermissionsScanners/Sources/PermissionsScanners/LaunchAgentScannerFS.swift` (KeepAlive bool-or-dict; decode `Disabled`)
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/LaunchAgentDetailSheet.swift` (show Disabled)
- Test: `Packages/PermissionsScanners/Tests/PermissionsScannersTests/LaunchAgentScannerFSTests.swift` (+dict-keepalive→true, +disabled)

**Task 5 (D5 — date-column guard):**
- Modify: `Packages/PermissionsStore/Sources/PermissionsStore/SnapshotStore.swift` (comment on date columns)
- Test: `Packages/PermissionsStore/Tests/PermissionsStoreTests/SnapshotDateEncodingTests.swift` (new)

---

## Task 1: D1 — Unify the TCC identity key

**Problem:** Four divergent implementations of "what makes a TCC grant unique." The scanner's dedupe key falls back to bundle path for path-only grants (empty bundleID), but `SnapshotStore.tccGrantIdentityKey`, `PermissionGrant.id`, and `DiffEntryKey` use bundleID only — so two distinct path-only CLI tools collapse to one in the diff and dismissals.

**Files:** as listed above.

- [ ] **Step 1: Write the failing test (Core)**

Create `Packages/PermissionsCore/Tests/PermissionsCoreTests/PermissionGrantIdentityTests.swift`:

```swift
import Foundation
import Testing
@testable import PermissionsCore

@Suite struct PermissionGrantIdentityTests {
    private func grant(bundleID: String, path: String?) -> PermissionGrant {
        PermissionGrant(
            service: .filesAndFolders,
            app: AppIdentity(
                bundleID: bundleID,
                displayName: "X",
                bundlePath: path.map { URL(fileURLWithPath: $0) }
            ),
            lastModified: Date(timeIntervalSince1970: 0)
        )
    }

    @Test func bundleIDGrantUsesBundleIDAsAppKey() {
        let g = grant(bundleID: "com.example.app", path: "/Applications/Example.app")
        #expect(g.appKey == "com.example.app")
        #expect(g.identityKey == "filesAndFolders|com.example.app|")
        #expect(g.id == g.identityKey)
    }

    @Test func pathOnlyGrantsWithDistinctPathsDoNotCollapse() {
        let a = grant(bundleID: "", path: "/usr/local/bin/tool-a")
        let b = grant(bundleID: "", path: "/usr/local/bin/tool-b")
        #expect(a.appKey == "/usr/local/bin/tool-a")
        #expect(a.identityKey != b.identityKey)
    }
}
```

- [ ] **Step 2: Run the test to verify it FAILS**

Run: `swift test --package-path Packages/PermissionsCore --filter PermissionGrantIdentityTests 2>&1 | tail -20`
Expected: FAIL to compile — `appKey`/`identityKey` don't exist on `PermissionGrant`.

- [ ] **Step 3: Add the canonical identity to `PermissionGrant`**

In `PermissionGrant.swift`, replace the `id` computed property:

```swift
    // Canonical app key. Path-only grants (TCC client_type == 1) carry an empty
    // bundleID, so fall back to the bundle path to keep two distinct path-based
    // clients from collapsing into one identity. (D1)
    public var appKey: String {
        if !app.bundleID.isEmpty { return app.bundleID }
        return app.bundlePath?.path(percentEncoded: false) ?? app.displayName
    }

    // Single source of truth for TCC grant identity — used by the scanner's
    // dedupe, the store's diff engine, the dismiss-key mapper, and SwiftUI
    // sheet(item:) bindings. (D1)
    public var identityKey: String {
        "\(service.rawValue)|\(appKey)|\(automationTarget ?? "")"
    }

    public var id: String { identityKey }
```

- [ ] **Step 4: Run the test to verify it PASSES**

Run: `swift test --package-path Packages/PermissionsCore --filter PermissionGrantIdentityTests 2>&1 | tail -20`
Expected: PASS (2 tests).

- [ ] **Step 5: Route the scanner, store, and dismiss key through `identityKey`**

In `TCCScannerSQLite.swift`, replace the `identityKey(_:)` helper body so it delegates (removing the duplicated path-fallback logic):

```swift
    private static func identityKey(_ grant: PermissionGrant) -> String {
        grant.identityKey
    }
```

In `SnapshotStore.swift`, replace `tccGrantIdentityKey`:

```swift
    private static func tccGrantIdentityKey(_ grant: PermissionGrant) -> String {
        grant.identityKey
    }
```

In `DiffEntryKey.swift`, replace the `.granted`/`.revoked` cases:

```swift
        case .granted(let g):
            return "tcc-granted|\(g.identityKey)"
        case .revoked(let g):
            return "tcc-revoked|\(g.identityKey)"
```

- [ ] **Step 6: Adjust the store diff test if it codified the old collapse**

READ `Packages/PermissionsStore/Tests/PermissionsStoreTests/TCCDiffTests.swift`. Find any test (e.g. `diffDoesNotTrapOnDuplicateIdentityKeys`) that asserts two **distinct path-only** grants collapse to one key. With D1 they no longer collapse. Update its expectations so two distinct path-only grants (distinct `bundlePath`, empty `bundleID`) produce TWO entries, and add this test if no equivalent exists:

```swift
    @Test func distinctPathOnlyGrantsBothAppearInDiff() async throws {
        let store = try SnapshotStore.inMemory()
        let s1 = try await store.writeTCCGrantsSnapshot([], at: Date(timeIntervalSince1970: 0))
        let toolA = PermissionGrant(service: .filesAndFolders,
            app: AppIdentity(bundleID: "", displayName: "tool-a", bundlePath: URL(fileURLWithPath: "/usr/local/bin/tool-a")),
            lastModified: Date(timeIntervalSince1970: 100))
        let toolB = PermissionGrant(service: .filesAndFolders,
            app: AppIdentity(bundleID: "", displayName: "tool-b", bundlePath: URL(fileURLWithPath: "/usr/local/bin/tool-b")),
            lastModified: Date(timeIntervalSince1970: 100))
        let s2 = try await store.writeTCCGrantsSnapshot([toolA, toolB], at: Date(timeIntervalSince1970: 200))
        let diff = try await store.diffTCCGrants(from: s1, to: s2)
        #expect(diff.added.count == 2)
    }
```
> If `TCCDiffTests` keeps a genuine same-identity dedupe test (two grants that really share an identity, e.g. the five `.filesAndFolders` strings already collapsed to one `service`), LEAVE that — it still must not trap. Only update assertions that conflated *distinct* path-only grants with duplicates. Use `@testable import` if the file already does; otherwise the public API above suffices.

- [ ] **Step 7: Build + test the affected packages**

Run: `swift test --package-path Packages/PermissionsCore 2>&1 | grep -E "Test run|error:" | tail -3`
Run: `swift test --package-path Packages/PermissionsStore 2>&1 | grep -E "Test run|error:" | tail -3`
Run: `swift build --package-path Packages/PermissionsScanners 2>&1 | tail -3`
Run: `swift build --package-path Packages/PermissionsUI 2>&1 | tail -3`
Expected: all green / build succeeds.

- [ ] **Step 8: Commit**

```bash
git add Packages/PermissionsCore/Sources/PermissionsCore/PermissionGrant.swift Packages/PermissionsScanners/Sources/PermissionsScanners/TCCScannerSQLite.swift Packages/PermissionsStore/Sources/PermissionsStore/SnapshotStore.swift Packages/PermissionsUI/Sources/PermissionsUI/DiffEntryKey.swift Packages/PermissionsCore/Tests/PermissionsCoreTests/PermissionGrantIdentityTests.swift Packages/PermissionsStore/Tests/PermissionsStoreTests/TCCDiffTests.swift
git commit -m "fix(tcc): unify TCC identity key so path-only grants don't collapse (D1)"
```

---

## Task 2: D2 — Capture `auth_value` (stop dropping limited access)

**Problem:** `TCCScannerSQLite` only keeps `auth_value == 2` rows, so limited access (`auth_value == 3`, e.g. Photos "Selected Photos") is dropped entirely and never appears. Capture `auth_value` (allowed + limited) so those grants surface; the changed-diff representation stays the v0.8.x slice.

**Files:** as listed above.

- [ ] **Step 1: Write the failing test (store round-trip + schema version)**

In `Packages/PermissionsStore/Tests/PermissionsStoreTests/PermissionsStoreTests.swift`, add:

```swift
    @Test func authValueRoundTripsAndSchemaIsV4() async throws {
        let store = try SnapshotStore.inMemory()
        #expect(try store.schemaVersion() == 4)
        let limited = PermissionGrant(
            service: .photos,
            app: AppIdentity(bundleID: "com.example.photoapp", displayName: "PhotoApp"),
            lastModified: Date(timeIntervalSince1970: 0),
            automationTarget: nil,
            authValue: 3
        )
        let sid = try await store.writeTCCGrantsSnapshot([limited], at: Date(timeIntervalSince1970: 1))
        let read = try await store.readTCCGrants(snapshotID: sid)
        #expect(read.count == 1)
        #expect(read.first?.authValue == 3)
    }
```
> Confirm `.photos` is a valid `PermissionService` case by checking `Packages/PermissionsCore/Sources/PermissionsCore/PermissionService.swift`; if the case is named differently, use a real case (e.g. `.filesAndFolders`).

- [ ] **Step 2: Run the test to verify it FAILS**

Run: `swift test --package-path Packages/PermissionsStore --filter authValueRoundTripsAndSchemaIsV4 2>&1 | tail -20`
Expected: FAIL — `PermissionGrant` has no `authValue` parameter (compile error), and schema is still 3.

- [ ] **Step 3: Add `authValue` to `PermissionGrant`**

In `PermissionGrant.swift`, add the stored property (after `automationTarget`), an init parameter (defaulted so existing call sites compile), and the assignment:

```swift
    public let service: PermissionService
    public let app: AppIdentity
    public let lastModified: Date
    public let automationTarget: String?
    // TCC auth_value: 2 = allowed, 3 = limited (e.g. Photos "Selected Photos").
    // Captured so limited access surfaces; representing a 2<->3 change as a diff
    // row is deferred to the v0.8.x model-fidelity slice. (D2)
    public let authValue: Int

    public init(
        service: PermissionService,
        app: AppIdentity,
        lastModified: Date,
        automationTarget: String? = nil,
        authValue: Int = 2
    ) {
        self.service = service
        self.app = app
        self.lastModified = lastModified
        self.automationTarget = automationTarget
        self.authValue = authValue
    }
```
(Leave the `appKey`/`identityKey`/`id` from Task 1 unchanged — `authValue` is intentionally NOT part of identity.)

- [ ] **Step 4: Add the v4 migration + persist auth_value in `SnapshotStore`**

In `SnapshotStore.swift`, register a new migration after the `v3` block (before `try migrator.migrate(queue)`):

```swift
        migrator.registerMigration("v4") { db in
            try db.alter(table: "tcc_grants") { t in
                t.add(column: "auth_value", .integer).notNull().defaults(to: 2)
            }
            try db.execute(sql: "UPDATE schema_version SET version = 4")
        }
```

In `insertTCCGrants`, add `auth_value` to the INSERT (column list, placeholder, and argument):

```swift
            try db.execute(sql: """
                INSERT INTO tcc_grants
                (snapshot_id, service, bundle_id, display_name, bundle_path,
                 last_modified, automation_target, auth_value)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    snapshotID,
                    grant.service.rawValue,
                    grant.app.bundleID,
                    grant.app.displayName,
                    grant.app.bundlePath?.path(percentEncoded: false),
                    grant.lastModified,
                    grant.automationTarget,
                    grant.authValue,
                ])
```

In `readTCCGrants`, add `auth_value` to the SELECT:

```swift
            let rows = try Row.fetchAll(db, sql: """
                SELECT service, bundle_id, display_name, bundle_path,
                       last_modified, automation_target, auth_value
                FROM tcc_grants
                WHERE snapshot_id = ?
                ORDER BY service, bundle_id, automation_target
                """, arguments: [snapshotID.rawValue])
```

In `tccGrantFromRow`, read it and pass it through:

```swift
        let automationTarget: String? = row["automation_target"]
        let authValue: Int = row["auth_value"]
        return PermissionGrant(
            service: service,
            app: AppIdentity(bundleID: bundleID, displayName: displayName, bundlePath: bundlePath),
            lastModified: lastModified,
            automationTarget: automationTarget,
            authValue: authValue
        )
```

- [ ] **Step 5: Run the test to verify it PASSES**

Run: `swift test --package-path Packages/PermissionsStore --filter authValueRoundTripsAndSchemaIsV4 2>&1 | tail -20`
Expected: PASS. Also run the full store suite — if any existing test asserts `schemaVersion() == 3`, update it to `4`:
Run: `swift test --package-path Packages/PermissionsStore 2>&1 | grep -E "Test run|✘|error:" | tail -5`

- [ ] **Step 6: Capture limited access in the scanner + test it**

In `TCCScannerSQLite.swift` `mapRowToGrant`, change the auth filter from `== 2` to `>= 2` and pass `authValue`:

```swift
    private static func mapRowToGrant(_ row: TCCRow) -> PermissionGrant? {
        guard row.authValue >= 2 else { return nil }   // allowed (2) + limited (3+) (D2)
```
and in the `PermissionGrant(...)` it returns, add `authValue: row.authValue`:

```swift
        return PermissionGrant(
            service: service,
            app: identity,
            lastModified: lastModified,
            automationTarget: automationTarget,
            authValue: row.authValue
        )
```

Add a scanner test. READ `Packages/PermissionsScanners/Tests/PermissionsScannersTests/TCCScannerSQLiteTests.swift` to see how it builds a fixture TCC.db (it uses `TCCFixtures`). Add a test that a row with `auth_value == 3` is now returned with `authValue == 3` (previously dropped). Mirror the fixture-construction pattern already in that file; the assertion is:

```swift
    @Test func limitedAccessRowIsReturnedWithAuthValue3() async throws {
        // <build a temp TCC.db with one row auth_value = 3 using the file's existing
        //  fixture helper, then scan it>
        let grants = try await scanner.scan()
        #expect(grants.contains { $0.authValue == 3 })
    }
```
> Use the file's existing fixture/DB-builder helper exactly (e.g. `TCCFixtures.writeDatabase(...)` with an `auth_value: 3` row). If the helper hardcodes `auth_value = 2`, extend it to accept the value, mirroring its style. If that proves infeasible from the fixture API, STOP and report NEEDS_CONTEXT.

- [ ] **Step 7: Verify scanner + build dependents**

Run: `swift test --package-path Packages/PermissionsScanners 2>&1 | grep -E "Test run|✘|error:" | tail -5` → all pass.
Run: `swift build --package-path Packages/PermissionsUI 2>&1 | tail -3` → builds.

- [ ] **Step 8: Commit**

```bash
git add Packages/PermissionsCore/Sources/PermissionsCore/PermissionGrant.swift Packages/PermissionsScanners/Sources/PermissionsScanners/TCCScannerSQLite.swift Packages/PermissionsScanners/Tests/PermissionsScannersTests/TCCScannerSQLiteTests.swift Packages/PermissionsStore/Sources/PermissionsStore/SnapshotStore.swift Packages/PermissionsStore/Tests/PermissionsStoreTests/PermissionsStoreTests.swift
git commit -m "fix(tcc): capture auth_value so limited access stops being dropped (D2)"
```

---

## Task 3: D3 — Preserve BTM disposition raw bits

**Problem:** `BTMScannerDirect` maps the disposition bitmask to `.enabled`/`.disabled` (never `.unknown(rawValue:)`), so `encodeDisposition` always writes `disposition_raw = NULL`. The schema column is dead and the original bits (e.g. policy-block vs user-toggle) are unrecoverable. Capture the raw bits losslessly; keep the enum for display. Exclude the raw field from Equatable/Hashable so it doesn't create confusing "Disabled→Disabled" diff rows (representing sub-state changes is deferred).

**Files:** as listed above.

- [ ] **Step 1: Write the failing test (store round-trip preserves raw; no diff noise)**

In `Packages/PermissionsStore/Tests/PermissionsStoreTests/BTMDiffTests.swift` (or create `BTMDispositionRawTests.swift` if you prefer; the diff-noise assertion needs the diff API which is here), add:

```swift
    @Test func dispositionRawRoundTripsAndDoesNotCreateDiffNoise() async throws {
        let store = try SnapshotStore.inMemory()
        func item(raw: Int) -> BTMItem {
            BTMItem(identifier: "com.example.helper", name: "Helper",
                    type: .legacyDaemon, disposition: .disabled, dispositionRaw: raw,
                    scope: .system, modificationDate: Date(timeIntervalSince1970: 0))
        }
        // Round-trip preserves the raw bits in the persisted snapshot.
        let s1 = try await store.writeBTMItemsSnapshot([item(raw: 5)], at: Date(timeIntervalSince1970: 1))
        let read = try await store.readBTMItems(snapshotID: s1)
        #expect(read.first?.dispositionRaw == 5)
        // Two items identical except dispositionRaw must NOT show as a change
        // (raw is excluded from Equatable; representing it is deferred).
        let s2 = try await store.writeBTMItemsSnapshot([item(raw: 9)], at: Date(timeIntervalSince1970: 2))
        let diff = try await store.diffBTMItems(from: s1, to: s2)
        #expect(diff.changed.isEmpty)
        #expect(diff.added.isEmpty)
        #expect(diff.removed.isEmpty)
    }
```

- [ ] **Step 2: Run the test to verify it FAILS**

Run: `swift test --package-path Packages/PermissionsStore --filter dispositionRawRoundTripsAndDoesNotCreateDiffNoise 2>&1 | tail -20`
Expected: FAIL to compile — `BTMItem` has no `dispositionRaw`.

- [ ] **Step 3: Add `dispositionRaw` + custom Equatable/Hashable to `BTMItem`**

In `BTMItem.swift`: add the stored property and init parameter (defaulted), and replace the auto-synthesized conformance with custom Equatable/Hashable that EXCLUDES `dispositionRaw`. The struct currently declares `: Sendable, Hashable, Identifiable`. Keep those, but add explicit `==` and `hash(into:)`.

Add the property (after `disposition`) and init param (after `disposition:`):

```swift
    public let disposition: Disposition
    // Raw BTM disposition bitmask, captured losslessly for the snapshot. Excluded
    // from Equatable/Hashable so a sub-bit change (e.g. policy-block vs user
    // toggle) does not surface as a confusing "Disabled -> Disabled" diff; the
    // friendly enum drives display. Representing raw changes is a future slice. (D3)
    public let dispositionRaw: Int
```
```swift
        type: ItemType,
        disposition: Disposition,
        dispositionRaw: Int = 0,
        scope: Scope,
```
```swift
        self.disposition = disposition
        self.dispositionRaw = dispositionRaw
        self.scope = scope
```

Then add explicit conformance at the end of the struct (before `var id`), listing every field EXCEPT `dispositionRaw`:

```swift
    public static func == (lhs: BTMItem, rhs: BTMItem) -> Bool {
        lhs.identifier == rhs.identifier
            && lhs.name == rhs.name
            && lhs.developerName == rhs.developerName
            && lhs.bundleIdentifier == rhs.bundleIdentifier
            && lhs.teamIdentifier == rhs.teamIdentifier
            && lhs.type == rhs.type
            && lhs.disposition == rhs.disposition
            && lhs.scope == rhs.scope
            && lhs.modificationDate == rhs.modificationDate
            && lhs.parentIdentifier == rhs.parentIdentifier
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
        hasher.combine(name)
        hasher.combine(developerName)
        hasher.combine(bundleIdentifier)
        hasher.combine(teamIdentifier)
        hasher.combine(type)
        hasher.combine(disposition)
        hasher.combine(scope)
        hasher.combine(modificationDate)
        hasher.combine(parentIdentifier)
    }
```

- [ ] **Step 4: Write/read `disposition_raw` always in `SnapshotStore`**

In `insertBTMItems`, change the `disposition_raw` argument from the encoded (always-nil) value to the item's raw bits. Replace `dispositionEncoded.raw` in the arguments array with `item.dispositionRaw`:

```swift
                    dispositionEncoded.kind,
                    item.dispositionRaw,
```
(Leave `encodeDisposition` and `typeEncoded`/`scopeEncoded` unchanged.)

In `btmItemFromRow`, read `disposition_raw` into the model (the SELECT already includes `disposition_raw`). Add a local and pass it to the `BTMItem(...)`:

```swift
        let dispositionRaw: Int = row["disposition_raw"] ?? 0
```
and in the `BTMItem(...)` constructor add `dispositionRaw: dispositionRaw` right after `disposition:`:

```swift
            disposition: try decodeDisposition(kind: dispositionKind, raw: dispositionRaw),
            dispositionRaw: dispositionRaw,
            scope: try decodeScope(kind: scopeKind, uuid: scopeUUID),
```
> Note: `decodeDisposition(kind:raw:)` still uses `raw` only for the `.unknown` case, which is unchanged. For known kinds the enum ignores `raw`; the raw is now also surfaced via the dedicated `dispositionRaw` field.

- [ ] **Step 5: Populate `dispositionRaw` from the scanner**

READ `BTMScannerDirect.swift` around `mapDisposition` / where `BTMItem(...)` is constructed (the audit cites ~line 156–172). The scanner decodes a raw `Int64` disposition then calls `mapDisposition`. Pass the raw value into the new field. In the `BTMItem(...)` construction, add `dispositionRaw: Int(<rawDispositionValue>)` right after `disposition:`. The raw value is whatever local holds the decoded disposition integer before `mapDisposition` (e.g. `record.disposition`). Example shape:

```swift
            disposition: Self.mapDisposition(record.disposition),
            dispositionRaw: Int(record.disposition),
```
> Match the actual local/field name in the file. If the raw disposition is not available at the construction site, thread it from where `mapDisposition` is called. If unclear, read the shim (`BTMItemRecordShim.swift`) to find the field.

- [ ] **Step 6: Run the test to verify it PASSES + full suites**

Run: `swift test --package-path Packages/PermissionsStore --filter dispositionRawRoundTripsAndDoesNotCreateDiffNoise 2>&1 | tail -20` → PASS.
Run: `swift test --package-path Packages/PermissionsStore 2>&1 | grep -E "Test run|✘|error:" | tail -5` → all pass.
Run: `swift test --package-path Packages/PermissionsScanners 2>&1 | grep -E "Test run|✘|error:" | tail -5` → all pass (existing BTM fixtures still round-trip; they'll now carry a raw value).
Run: `swift build --package-path Packages/PermissionsUI 2>&1 | tail -3` → builds.

- [ ] **Step 7: Commit**

```bash
git add Packages/PermissionsCore/Sources/PermissionsCore/BTMItem.swift Packages/PermissionsScanners/Sources/PermissionsScanners/BTMScannerDirect.swift Packages/PermissionsStore/Sources/PermissionsStore/SnapshotStore.swift Packages/PermissionsStore/Tests/PermissionsStoreTests/BTMDiffTests.swift
git commit -m "fix(btm): preserve disposition raw bits losslessly in snapshots (D3)"
```

---

## Task 4: D4 — Launch Agent `KeepAlive`-as-dictionary and `Disabled`

**Problem:** `KeepAlive` is commonly a dictionary (`{SuccessfulExit=false}`, etc.) which fails the `Bool` decode and silently becomes `false` (undercounts persistence). The launchd `Disabled` key isn't decoded at all, so a disabled agent looks active in the live view. Fix both in the scanner; surface `Disabled` in the detail sheet. `Disabled` is NOT persisted/diffed in this slice (deferred) — it's a live-display fidelity fix, so no migration.

**Files:** as listed above.

- [ ] **Step 1: Write the failing test (scanner)**

READ `Packages/PermissionsScanners/Tests/PermissionsScannersTests/LaunchAgentScannerFSTests.swift` to learn how it writes fixture `.plist` files into a temp dir and constructs `LaunchAgentScannerFS(sources:)`. Then add two tests mirroring that style:

```swift
    @Test func keepAliveAsDictionaryIsTreatedAsTrue() async throws {
        // <write a .plist where KeepAlive is a <dict> (e.g. {SuccessfulExit:false})
        //  into a temp LaunchAgents dir, scan it>
        let items = try await scanner.scan()
        #expect(items.first?.keepAlive == true)
    }

    @Test func disabledKeyIsDecoded() async throws {
        // <write a .plist with <key>Disabled</key><true/>>
        let items = try await scanner.scan()
        #expect(items.first?.isDisabled == true)
    }
```
> Use the exact fixture-writing helper the existing tests use. The first test's plist must have `KeepAlive` as a dictionary; the second must include `Disabled = true`.

- [ ] **Step 2: Run the tests to verify they FAIL**

Run: `swift test --package-path Packages/PermissionsScanners --filter LaunchAgentScannerFSTests 2>&1 | tail -25`
Expected: FAIL — `isDisabled` doesn't exist (compile), and `keepAlive` is `false` for the dict case.

- [ ] **Step 3: Add `isDisabled` to `LaunchAgentItem`**

In `LaunchAgentItem.swift`, add the property (after `keepAlive`), init parameter (defaulted), and assignment:

```swift
    public let runAtLoad: Bool
    public let keepAlive: Bool
    // launchd `Disabled` key. A disabled agent is registered but not loaded;
    // surfaced in the detail view so it isn't mistaken for active. (D4)
    public let isDisabled: Bool
```
```swift
        runAtLoad: Bool,
        keepAlive: Bool,
        isDisabled: Bool = false
    ) {
```
```swift
        self.runAtLoad = runAtLoad
        self.keepAlive = keepAlive
        self.isDisabled = isDisabled
```

- [ ] **Step 4: Decode `KeepAlive`-as-dict and `Disabled` in the scanner**

In `LaunchAgentScannerFS.swift`, the `DecodedPlist` struct decodes keys via a custom `init(from:)`. Update `KeepAlive` to treat a present-but-non-bool value (a dict) as `true`, and add `Disabled` decoding. Replace the `keepAlive`/add `isDisabled` lines in `DecodedPlist`:

Add to the stored properties and `CodingKeys`:

```swift
    let keepAlive: Bool
    let isDisabled: Bool
```
```swift
        case keepAlive = "KeepAlive"
        case disabled = "Disabled"
```
In `init(from:)`, replace the `keepAlive` line and add `isDisabled`:

```swift
        // KeepAlive is often a dictionary ({SuccessfulExit=false}, {Crashed=true}).
        // A Bool decode fails on a dict; treat any present non-bool form as an
        // active keep-alive policy rather than silently false. (D4)
        if let b = try? container.decode(Bool.self, forKey: .keepAlive) {
            self.keepAlive = b
        } else {
            self.keepAlive = container.contains(.keepAlive)
        }
        self.isDisabled = (try? container.decode(Bool.self, forKey: .disabled)) ?? false
```

In `decodePlist`, pass `isDisabled` into the `LaunchAgentItem(...)`:

```swift
                runAtLoad: decoded.runAtLoad,
                keepAlive: decoded.keepAlive,
                isDisabled: decoded.isDisabled
```

- [ ] **Step 5: Run the scanner tests to verify they PASS**

Run: `swift test --package-path Packages/PermissionsScanners --filter LaunchAgentScannerFSTests 2>&1 | tail -25`
Expected: PASS (including the two new tests and the pre-existing ones; note the pre-existing `scanHandlesDictKeepAlive` test, if present, asserted `keepAlive == false` for a dict — UPDATE it to `== true`, since the lossy behavior is the bug we're fixing).

- [ ] **Step 6: Surface `Disabled` in the detail sheet**

READ `Packages/PermissionsUI/Sources/PermissionsUI/LaunchAgentDetailSheet.swift`. It renders key/value rows for the agent (label, path, args, Run at load, Keep alive). Add a "Disabled" row mirroring the existing `keepAlive`/`runAtLoad` row pattern. Find the row that shows `item.keepAlive ? "Yes" : "No"` and add an adjacent row:

```swift
            // (mirror the exact KV-row helper used for "Keep alive"/"Run at load")
            row(String(localized: "Disabled"), item.isDisabled ? String(localized: "Yes") : String(localized: "No"))
```
> Use whatever KV-row helper/label the sheet already uses for Run-at-load/Keep-alive (match its exact call shape). Keep the value localized.

- [ ] **Step 7: Build + verify**

Run: `swift build --package-path Packages/PermissionsUI 2>&1 | tail -3` → builds.
Run: `swift test --package-path Packages/PermissionsScanners 2>&1 | grep -E "Test run|✘|error:" | tail -5` → all pass.
Run: `swift build --package-path Packages/PermissionsStore 2>&1 | tail -3` → builds (store still constructs `LaunchAgentItem` without `isDisabled` via the default; confirm no break).

- [ ] **Step 8: Commit**

```bash
git add Packages/PermissionsCore/Sources/PermissionsCore/LaunchAgentItem.swift Packages/PermissionsScanners/Sources/PermissionsScanners/LaunchAgentScannerFS.swift Packages/PermissionsScanners/Tests/PermissionsScannersTests/LaunchAgentScannerFSTests.swift Packages/PermissionsUI/Sources/PermissionsUI/LaunchAgentDetailSheet.swift
git commit -m "fix(launchagent): handle KeepAlive-dict and decode Disabled (D4)"
```

---

## Task 5: D5 — Guard the GRDB date-column encoding

**Problem:** `created_at`/`last_modified`/`modification_date` are declared `.double` (REAL affinity) but GRDB serializes `Date` as a fixed-width TEXT string. It works today only because both sides use the same encoder. If a numeric timestamp were ever written into those columns, SQLite would sort all REALs before all TEXT, silently corrupting `latestSnapshotID` ordering and pruning. Pin the invariant with a guard test and a comment (no risky table rebuild for a latent issue).

**Files:** as listed above.

- [ ] **Step 1: Write the guard test**

Create `Packages/PermissionsStore/Tests/PermissionsStoreTests/SnapshotDateEncodingTests.swift`:

```swift
import Foundation
import Testing
import PermissionsCore
@testable import PermissionsStore

@Suite struct SnapshotDateEncodingTests {
    @Test func datesRoundTripToMillisecond() async throws {
        let store = try SnapshotStore.inMemory()
        let when = Date(timeIntervalSince1970: 1_700_000_000.123)
        let grant = PermissionGrant(
            service: .filesAndFolders,
            app: AppIdentity(bundleID: "com.example.app", displayName: "App"),
            lastModified: when
        )
        let sid = try await store.writeTCCGrantsSnapshot([grant], at: when)
        let read = try await store.readTCCGrants(snapshotID: sid)
        // GRDB TEXT date encoding is millisecond-precision; assert within 1ms.
        let delta = abs((read.first?.lastModified.timeIntervalSince1970 ?? 0) - when.timeIntervalSince1970)
        #expect(delta < 0.0011)
    }

    @Test func latestSnapshotOrderingIsChronologicalNotInsertionOrder() async throws {
        let store = try SnapshotStore.inMemory()
        // Insert out of chronological order; the "latest" must be the newest DATE.
        _ = try await store.writeTCCGrantsSnapshot([], at: Date(timeIntervalSince1970: 3_000_000_000))
        let middle = try await store.writeTCCGrantsSnapshot([], at: Date(timeIntervalSince1970: 1_000_000_000))
        let newest = try await store.latestSnapshotID()
        // The first insert has the newest date, so it must win despite being inserted first.
        #expect(newest != middle)
        let atOrBeforeOld = try await store.latestSnapshotID(atOrBefore: Date(timeIntervalSince1970: 1_500_000_000))
        #expect(atOrBeforeOld == middle)
    }
}
```

- [ ] **Step 2: Run the tests to verify they PASS (this is a guard — current behavior is correct)**

Run: `swift test --package-path Packages/PermissionsStore --filter SnapshotDateEncodingTests 2>&1 | tail -20`
Expected: PASS. (These pin the working behavior so a future numeric-writer regression fails loudly.)

- [ ] **Step 3: Document the date-column invariant**

In `SnapshotStore.swift`, add a comment directly above the `migrate(_:)` function (or above the `v2` migration where `created_at` is first declared) documenting the invariant:

```swift
    // INVARIANT: every `.double`-declared date column (created_at, last_modified,
    // modification_date) actually stores a GRDB-encoded fixed-width TEXT date,
    // NOT a numeric timestamp. Comparisons (ORDER BY created_at, created_at <= ?)
    // rely on lexicographic ordering of that fixed format. Only ever write these
    // via a Swift `Date` through GRDB — a raw numeric write would make SQLite sort
    // all REALs before all TEXT and silently corrupt ordering/pruning. Pinned by
    // SnapshotDateEncodingTests. (D5)
    private static func migrate(_ queue: DatabaseQueue) throws {
```

- [ ] **Step 4: Verify**

Run: `swift test --package-path Packages/PermissionsStore 2>&1 | grep -E "Test run|✘|error:" | tail -3` → all pass.

- [ ] **Step 5: Commit**

```bash
git add Packages/PermissionsStore/Sources/PermissionsStore/SnapshotStore.swift Packages/PermissionsStore/Tests/PermissionsStoreTests/SnapshotDateEncodingTests.swift
git commit -m "test(store): guard GRDB date-column TEXT encoding + ordering invariant (D5)"
```

---

## Final verification (after all tasks)

- [ ] **All package suites green**

```bash
swift test --package-path Packages/PermissionsCore 2>&1 | tail -3
swift test --package-path Packages/PermissionsScanners 2>&1 | tail -3
swift test --package-path Packages/PermissionsStore 2>&1 | tail -3
swift test --package-path Packages/PermissionsUI 2>&1 | tail -3
```

- [ ] **App-target tests + build**

```bash
xcodebuild test -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse -destination 'platform=macOS,arch=arm64' -only-testing:PermissionPulseTests 2>&1 | grep -E "✔ Test run with|✘|TEST SUCCEEDED|TEST FAILED" | tail -3
xcodebuild build -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse -destination 'platform=macOS,arch=arm64' 2>&1 | tail -5
```
Expected: TEST SUCCEEDED + BUILD SUCCEEDED. (App-target coordinator tests construct `PermissionGrant`/`BTMItem`/`LaunchAgentItem` — the defaulted new params keep them compiling; confirm.)

---

## Self-Review (completed during planning)

**Spec coverage:** D1→Task 1, D2→Task 2, D3→Task 3, D4→Task 4, D5→Task 5. All five Workstream-2 items covered. The deeper representation work (auth_value/disposition *changed* diff rows, `.filesAndFolders` sub-service granularity, persisting/diffing `Disabled`) is explicitly the deferred v0.8.x slice, consistent with the spec.

**Dependencies / ordering:** Task 1 and Task 2 both touch `PermissionGrant.swift`, `TCCScannerSQLite.swift`, and `SnapshotStore.swift` — run them in order (1 then 2). Task 1 adds `appKey`/`identityKey`/`id`; Task 2 adds `authValue` (not part of identity, so no interaction). Tasks 3, 4, 5 are independent of each other and of 1/2 except all touch `SnapshotStore.swift` (different methods) — sequential execution avoids conflicts.

**Type consistency:** new members are `PermissionGrant.appKey`/`identityKey`/`authValue`, `BTMItem.dispositionRaw`, `LaunchAgentItem.isDisabled` — each defined once and referenced consistently. All new init params are defaulted so existing constructors across the scanners, store, app target, and tests keep compiling. `auth_value` migration is v4 (after the existing v3); `schemaVersion()` becomes 4 (Task 2 Step 5 updates any v3 assertion).

**Testability honesty:** D1/D2/D3/D5 are unit-tested (Core/Store/Scanners). D4's scanner decode is unit-tested via fixture plists; the detail-sheet "Disabled" row is build + visual (views aren't unit-tested here). Scanner tests that build fixture TCC.db / `.plist` files reuse the files' existing helpers — if a helper hardcodes a value that blocks the new case, the task says to extend it or report NEEDS_CONTEXT rather than guess.
