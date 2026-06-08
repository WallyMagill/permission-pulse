# Workstream 3 — Robustness / No Silent Failure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the remaining swallowed-error / silent-failure paths beyond P0: log snapshot-prune failures, guard against a Refresh racing the launch scan (duplicate snapshots), pin that unknown-enum-kind reads throw (so they hit the W1 error state, not "empty"), and stop the `mdls` probe from stranding a process/continuation on timeout.

**Architecture:** Four small, independent fixes (R1–R4). R3 is a regression test that pins existing throw-on-unknown-kind behavior (the decoders already throw; this makes them reachable to `@testable` and tests them). R1/R2/R4 are real code changes whose failure paths are not unit-testable in this codebase (no injectable failing-store seam; app-target `AppDelegate`; a real `mdls` subprocess) — they are build-verified with the reasoning documented, matching how the existing live-scanner / coordinator-wiring layers are handled.

**Tech Stack:** Swift 6.0 (MainActor-by-default, strict concurrency), GRDB 7.10, Swift Testing, Xcode 26.

**Source spec:** `docs/superpowers/specs/2026-06-06-app-quality-audit-design.md` (Workstream 3). Builds on W1 (C2 added `viewModel.diffUnavailable`, set in `SnapshotCoordinator.computeDiffs`' catch) and W2.

**Conventions:**
- Commit attribution disabled — no `Co-Authored-By` trailer.
- Package tests: `swift test --package-path <pkg> --filter <name>`. App build/tests via `xcodebuild`. SourceKit "No such module" / "has no member" warnings are known false positives — trust `swift build`/`swift test`/`xcodebuild`.

---

## File Structure

**Task 1 (R3 — unknown-kind throws regression test):**
- Modify: `Packages/PermissionsStore/Sources/PermissionsStore/SnapshotStore.swift` (make 3 BTM decoders `internal`)
- Test: `Packages/PermissionsStore/Tests/PermissionsStoreTests/BTMDecodeErrorTests.swift` (new)

**Task 2 (R1 — log prune failures):**
- Modify: `PermissionPulse/PermissionPulse/SnapshotCoordinator.swift:89` (do/catch + `.error` log)

**Task 3 (R2 — concurrent-scan guard):**
- Modify: `PermissionPulse/PermissionPulse/PermissionPulseApp.swift:159` (`rescan()` guard)

**Task 4 (R4 — mdls process/continuation cleanup on cancel):**
- Modify: `Packages/PermissionsScanners/Sources/PermissionsScanners/LastUsedProbeHybrid.swift` (`runMDLS` wrapped in `withTaskCancellationHandler`)

---

## Task 1: R3 — Pin that unknown enum kinds throw (broken ≠ empty)

**Problem (already mostly fixed by W1's C2):** `SnapshotStore`'s `decodeItemType`/`decodeDisposition`/`decodeScope` throw `StoreError` on an unrecognized `kind`, which propagates up through `readBTMItems` → `diffBTMItems` → `SnapshotCoordinator.computeDiffs`' catch, which (since C2) sets `viewModel.diffUnavailable = true` (the error state, not the empty "come back tomorrow" state). This task adds a regression test pinning the throw, so a future change that silently defaults instead of throwing fails loudly. The decoders are currently `private static`; make them `internal` so `@testable` can reach them.

**Files:** as listed above.

- [ ] **Step 1: Write the failing test (compile-RED: decoders are private)**

Create `Packages/PermissionsStore/Tests/PermissionsStoreTests/BTMDecodeErrorTests.swift`:

```swift
import Foundation
import Testing
@testable import PermissionsStore

@Suite struct BTMDecodeErrorTests {
    @Test func unknownTypeKindThrows() {
        #expect(throws: StoreError.self) {
            _ = try SnapshotStore.decodeItemType(kind: "bogus-type", raw: nil)
        }
    }

    @Test func unknownDispositionKindThrows() {
        #expect(throws: StoreError.self) {
            _ = try SnapshotStore.decodeDisposition(kind: "bogus-disposition", raw: nil)
        }
    }

    @Test func unknownScopeKindThrows() {
        #expect(throws: StoreError.self) {
            _ = try SnapshotStore.decodeScope(kind: "bogus-scope", uuid: nil)
        }
    }

    @Test func knownKindsStillDecode() throws {
        #expect(try SnapshotStore.decodeItemType(kind: "app", raw: nil) == .app)
        #expect(try SnapshotStore.decodeDisposition(kind: "enabled", raw: nil) == .enabled)
        #expect(try SnapshotStore.decodeScope(kind: "system", uuid: nil) == .system)
    }
}
```

- [ ] **Step 2: Run the test to verify it FAILS (to compile)**

Run: `swift test --package-path Packages/PermissionsStore --filter BTMDecodeErrorTests 2>&1 | tail -20`
Expected: FAIL to compile — `decodeItemType`/`decodeDisposition`/`decodeScope` are `private` and not visible to the test target.

- [ ] **Step 3: Make the three BTM decoders internal**

In `SnapshotStore.swift`, change the three function signatures from `private static func` to `static func` (drop `private`), and add a brief comment above the first one. They are in the `// MARK: - BTM enum encoding` section:

```swift
    // internal (not private): the unknown-kind throw is a data-integrity guarantee
    // (a corrupt/foreign snapshot row surfaces as an error state, not silent
    // default). Exposed for BTMDecodeErrorTests. (R3)
    static func decodeItemType(kind: String, raw: Int?) throws -> BTMItem.ItemType {
```
```swift
    static func decodeDisposition(kind: String, raw: Int?) throws -> BTMItem.Disposition {
```
```swift
    static func decodeScope(kind: String, uuid: String?) throws -> BTMItem.Scope {
```
(Bodies unchanged — they already `throw StoreError.unknown...Kind` in the `default:` case.)

- [ ] **Step 4: Run the test to verify it PASSES**

Run: `swift test --package-path Packages/PermissionsStore --filter BTMDecodeErrorTests 2>&1 | tail -20`
Expected: PASS (4 tests).

- [ ] **Step 5: Run the full store suite**

Run: `swift test --package-path Packages/PermissionsStore 2>&1 | grep -E "Test run|✘|error:" | tail -3`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add Packages/PermissionsStore/Sources/PermissionsStore/SnapshotStore.swift Packages/PermissionsStore/Tests/PermissionsStoreTests/BTMDecodeErrorTests.swift
git commit -m "test(store): pin that unknown enum kinds throw (broken != empty) (R3)"
```

---

## Task 2: R1 — Log snapshot-prune failures instead of swallowing them

**Problem:** `SnapshotCoordinator.onScanCompleted` prunes with `_ = try? await store.pruneSnapshots(...)` — any failure (disk full, locked DB) is discarded silently, and the DB can grow unbounded with no signal, defeating the retention setting.

**Files:** `PermissionPulse/PermissionPulse/SnapshotCoordinator.swift` (the prune call at line 89).

> Not unit-tested: making `pruneSnapshots` fail requires an injectable failing store, which `SnapshotCoordinator` does not have (it holds a concrete `SnapshotStore`). Adding a store protocol seam is out of scope for a logging fix. Verified by build + the surrounding test suite staying green. The change must NOT let a prune failure abort the subsequent diff refresh.

- [ ] **Step 1: Replace the swallowing `try?` with a logged do/catch**

In `SnapshotCoordinator.swift`, inside `onScanCompleted`'s `do` block, replace:

```swift
            _ = try? await store.pruneSnapshots(olderThan: retentionCutoff)
            await refreshDiffsAndStale(latestID: snapshotID)
```

with:

```swift
            // A prune failure must NOT abort the diff refresh below, so it gets
            // its own do/catch (not the outer one) and is logged rather than
            // swallowed — otherwise the DB grows unbounded with no signal. (R1)
            do {
                _ = try await store.pruneSnapshots(olderThan: retentionCutoff)
            } catch {
                Self.logger.error("Snapshot prune failed: \(error.localizedDescription, privacy: .public)")
            }
            await refreshDiffsAndStale(latestID: snapshotID)
```

- [ ] **Step 2: Build the app target + run the coordinator tests**

Run: `xcodebuild build -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse -destination 'platform=macOS,arch=arm64' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED.
Run: `xcodebuild test -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse -destination 'platform=macOS,arch=arm64' -only-testing:PermissionPulseTests/SnapshotCoordinatorTests 2>&1 | tail -15`
Expected: all `SnapshotCoordinatorTests` pass (the prune happy-path — `customRetentionHonored` — still works; the change only affects the failure path, which those tests don't trigger).

- [ ] **Step 3: Commit**

```bash
git add PermissionPulse/PermissionPulse/SnapshotCoordinator.swift
git commit -m "fix(snapshot): log prune failures instead of swallowing them (R1)"
```

---

## Task 3: R2 — Guard against a Refresh racing the launch scan

**Problem:** `AppDelegate.rescan()` sets `viewModel.scanInProgress = true` and runs, but does not check whether a scan is already in flight. If the user clicks Refresh during the initial launch scan (which sets `scanInProgress = true` in its own `Task`), two scans run concurrently and can both pass `SnapshotCoordinator`'s once-per-day write guard (the first hasn't persisted `lastSnapshotDate` yet) → duplicate snapshot rows.

**Files:** `PermissionPulse/PermissionPulse/PermissionPulseApp.swift` (`rescan()` at line 159).

> Not unit-tested: `rescan()` is on the app `AppDelegate`, which is constructed by the app and wires every coordinator in `applicationDidFinishLaunching` — there is no test harness that instantiates it. The guard is a one-line early-return, correct by inspection. Verified by build.

- [ ] **Step 1: Add the early-return guard at the top of `rescan()`**

In `PermissionPulseApp.swift`, replace:

```swift
    func rescan() async {
        viewModel.scanInProgress = true
        viewModel.staleThresholdDays = preferencesStore.staleThresholdDays
        await coordinator?.rescan()
        await snapshotCoordinator?.onScanCompleted()
        viewModel.scanInProgress = false
    }
```

with:

```swift
    func rescan() async {
        // Don't start a second scan while one is in flight (e.g. user hits
        // Refresh during the initial launch scan). Concurrent scans can both
        // pass SnapshotCoordinator's once-per-day write guard before the first
        // persists lastSnapshotDate, producing duplicate snapshot rows. (R2)
        guard !viewModel.scanInProgress else {
            Self.logger.debug("Rescan ignored — a scan is already in progress")
            return
        }
        viewModel.scanInProgress = true
        viewModel.staleThresholdDays = preferencesStore.staleThresholdDays
        await coordinator?.rescan()
        await snapshotCoordinator?.onScanCompleted()
        viewModel.scanInProgress = false
    }
```
(`Self.logger` is the existing `AppDelegate` logger — confirm it exists; the file already uses `Self.logger.error(...)` in `applicationDidFinishLaunching`, so it does.)

- [ ] **Step 2: Build the app target**

Run: `xcodebuild build -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse -destination 'platform=macOS,arch=arm64' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED.
Run: `xcodebuild test -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse -destination 'platform=macOS,arch=arm64' -only-testing:PermissionPulseTests 2>&1 | grep -E "✔ Test run with|✘|TEST SUCCEEDED|TEST FAILED" | tail -3`
Expected: TEST SUCCEEDED (no regression).

- [ ] **Step 3: Commit**

```bash
git add PermissionPulse/PermissionPulse/PermissionPulseApp.swift
git commit -m "fix(scan): ignore Refresh while a scan is already in progress (R2)"
```

---

## Task 4: R4 — Terminate the `mdls` process on probe cancellation

**Problem:** `LastUsedProbeHybrid.runMDLS` launches `/usr/bin/mdls` inside `withCheckedContinuation`. The caller (`spotlightDate`) races it against a 2-second timeout and `cancelAll()`s the group when the timeout wins — but `withCheckedContinuation` doesn't observe cancellation, so the `mdls` process keeps running (orphaned) and the continuation only resumes if/when the process eventually terminates. A hung `mdls` strands the process and the continuation. Fix: wrap the continuation in `withTaskCancellationHandler` and `terminate()` the process on cancellation, so its `terminationHandler` fires and the continuation always resumes.

**Files:** `Packages/PermissionsScanners/Sources/PermissionsScanners/LastUsedProbeHybrid.swift` (`runMDLS`).

> Not unit-tested: `runMDLS` shells out to the real `/usr/bin/mdls`; there is no mock seam (the testable `LastUsedProbe` mock is a separate type). The fix is verified by (a) it compiles under Swift 6 strict concurrency — the `Process` capture into the `@Sendable onCancel` is the tricky part — and (b) reasoning: the continuation is resumed exactly once (only `terminationHandler` resumes it for a started process; the launch-failure `catch` resumes it once if the process never started). Manual sanity: the existing `LastUsedProbeTests` (which use the file-system fallback path, not `mdls`) must stay green.

- [ ] **Step 1: Add an unchecked-Sendable box helper (file-private)**

In `LastUsedProbeHybrid.swift`, add at the bottom of the file (after the struct), a tiny box to bridge the non-`Sendable` `Process` into the `@Sendable` cancellation handler:

```swift
// `Process` is not Sendable, but `terminate()`/`isRunning` are safe to call from
// another thread. This box lets the @Sendable onCancel closure hold a reference
// without tripping Swift 6 strict-concurrency checking. (R4)
private struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
```

- [ ] **Step 2: Rewrite `runMDLS` to terminate the process on cancellation**

Replace the entire `runMDLS` function with:

```swift
    private static func runMDLS(path: String) async -> Date? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdls")
        process.arguments = ["-name", "kMDItemLastUsedDate", "-raw", path]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let box = UncheckedSendableBox(process)

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Date?, Never>) in
                process.terminationHandler = { proc in
                    guard proc.terminationStatus == 0 else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let data = stdout.fileHandleForReading.readDataToEndOfFile()
                    let raw = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if raw.isEmpty || raw == "(null)" {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(returning: Self.parseMDLSDate(raw))
                }
                do {
                    try process.run()
                } catch {
                    logger.error("mdls launch failed: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(returning: nil)
                }
            }
        } onCancel: {
            // Timeout (or any cancellation) fired: kill mdls so its
            // terminationHandler runs and the continuation resumes — no orphaned
            // process, no stranded continuation. terminate() on an already-exited
            // process is harmless. (R4)
            let proc = box.value
            if proc.isRunning { proc.terminate() }
        }
    }
```

Key correctness points (for the reviewer): the continuation is resumed exactly once — `terminationHandler` handles every started-process exit (including the one caused by `onCancel`'s `terminate()`), and the `catch` handles the never-started case. `onCancel` only calls `terminate()`; it never resumes the continuation itself, so there is no double-resume.

- [ ] **Step 3: Build under strict concurrency + run the probe tests**

Run: `swift build --package-path Packages/PermissionsScanners 2>&1 | tail -5`
Expected: Build succeeds with NO Sendable/concurrency errors. If the compiler complains about capturing `process`/`stdout` in the `operation` closure, note that the `operation` closure of `withTaskCancellationHandler` is NOT `@Sendable` (only `onCancel` is) so those captures are legal; only the `box` is captured by `onCancel`. If a real error appears, STOP and report it.
Run: `swift test --package-path Packages/PermissionsScanners --filter LastUsedProbeTests 2>&1 | tail -10`
Expected: existing probe tests pass (they exercise the file-system fallback, unaffected by this change).
Run: `swift test --package-path Packages/PermissionsScanners 2>&1 | grep -E "Test run|✘|error:" | tail -3`
Expected: all pass.

- [ ] **Step 4: Commit**

```bash
git add Packages/PermissionsScanners/Sources/PermissionsScanners/LastUsedProbeHybrid.swift
git commit -m "fix(probe): terminate mdls on cancellation to avoid stranded process/continuation (R4)"
```

---

## Final verification (after all tasks)

- [ ] **All package suites + app target**

```bash
swift test --package-path Packages/PermissionsCore 2>&1 | tail -3
swift test --package-path Packages/PermissionsScanners 2>&1 | tail -3
swift test --package-path Packages/PermissionsStore 2>&1 | tail -3
swift test --package-path Packages/PermissionsUI 2>&1 | tail -3
xcodebuild test -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse -destination 'platform=macOS,arch=arm64' -only-testing:PermissionPulseTests 2>&1 | grep -E "✔ Test run with|TEST SUCCEEDED|TEST FAILED" | tail -2
xcodebuild build -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse -destination 'platform=macOS,arch=arm64' 2>&1 | tail -3
```
Expected: all green + BUILD SUCCEEDED.

---

## Self-Review (completed during planning)

**Spec coverage:** R1→Task 2, R2→Task 3, R3→Task 1, R4→Task 4. All four Workstream-3 items covered. R3's deeper goal ("classified as an error state, not empty") was already delivered by W1's C2 (`computeDiffs` catch → `diffUnavailable`); Task 1 adds the regression test pinning the throw that feeds it.

**Dependencies / ordering:** All four tasks touch different files (SnapshotStore, SnapshotCoordinator, PermissionPulseApp, LastUsedProbeHybrid) and are independent — any order works. Task 1 first because it's the one with a true unit test.

**Type consistency:** Task 1 only changes visibility (`private` → internal) of three existing functions; signatures unchanged. Tasks 2/3/4 are self-contained behavior changes with no new cross-task types. `UncheckedSendableBox` (Task 4) is file-private to `LastUsedProbeHybrid.swift`.

**Testability honesty:** Only R3 is unit-tested (the decoders are reachable and deterministic). R1 (needs a failing-store seam), R2 (app-target `AppDelegate`), and R4 (real `mdls` subprocess) have no injectable failure seam in this codebase, so they are build-verified with the reasoning documented inline and in each task's note — consistent with how the live-scanner and coordinator-wiring layers are already handled in W1. This is a deliberately lighter-weight workstream: four small, surgical robustness fixes.
