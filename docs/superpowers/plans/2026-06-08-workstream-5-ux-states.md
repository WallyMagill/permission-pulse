# Workstream 5 — UX States & Flows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the six UX-state gaps in Thread A Workstream 5 — a real "Scanning…" state, a parity-safe "Dismiss forever" flow, a Quit & Reopen affordance for the FDA grant loop, discoverability hints for row actions, a re-openable Welcome/About, and a mock marker that survives `showsHeader: false`.

**Architecture:** All changes live in `PermissionsUI` (views + one pure helper) plus a one-line wiring change in the app target (`PermissionPulseApp.swift`). One new pure helper (`ScanState`) carries the only new unit test; the remaining tasks are view-layer changes verified by `swift build` + the smoke-test manual checklist (consistent with Workstream 4). No model, store-schema, or scanner changes. Read-only discipline is untouched.

**Tech Stack:** Swift 6, SwiftUI, AppKit (relaunch + activation only), Swift Testing, GRDB (unaffected).

**Scope note — deliberate YAGNI calls (carried from the spec):**
- **U2:** We deliver *parity with the existing stale-app flow* — relabel to "Dismiss forever" + a confirmation alert whose message points at Reset All Data as the un-dismiss path. We do **not** add an undo-toast system: nothing else in the app has one, `DismissedDiffEntryStore.undismiss(key:)` already exists for a future surfaced un-dismiss UI, and inventing a one-off toast conflicts with the consistency goal. Snooze stays a direct (reversible, 7-day) action with no alert.
- **U3:** We add a "Quit & Reopen" relaunch affordance (the honest fix — FDA for a running process needs a restart to take effect) rather than a foreground re-check, which would not detect a grant the running process is still denied.

---

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `Packages/PermissionsUI/Sources/PermissionsUI/ScanState.swift` | **NEW.** Pure helper deciding when a "Scanning…" placeholder shows. | 1 |
| `Packages/PermissionsUI/Tests/PermissionsUITests/ScanStateTests.swift` | **NEW.** Unit tests for `ScanState`. | 1 |
| `Packages/PermissionsUI/Sources/PermissionsUI/ScanningPlaceholder.swift` | **NEW.** Shared ProgressView + "Scanning…" placeholder. | 1 |
| `DetailWindowView.swift` | Gate the 3 inventory pages on the scanning placeholder; add Mock marker to the page scaffold. | 1, 6 |
| `MenuBarContentView.swift` | "Scanning…" header state; "Welcome & About" footer row; optional shortcut on `MenuRowButton`. | 1, 5 |
| `ChangeRow.swift` | Relabel "Dismiss" → "Dismiss forever"; extract `summary(for:)`. | 2 |
| `DiffTabView.swift` | Confirmation alert for Dismiss forever; one-line discoverability hint. | 2, 4 |
| `StaleAppsTabView.swift` | One-line discoverability hint. | 4 |
| `AppRelauncher.swift` | **NEW.** AppKit relaunch helper. | 3 |
| `PermissionsEmptyStateView.swift` | "Quit & Reopen" button in the FDA-denied state. | 3 |
| `PermissionPulse/PermissionPulse/PermissionPulseApp.swift` | Pass `onShowWelcome` closure into `MenuBarContentView`. | 5 |

---

## Task 1: Loading / scanning state (U1)

**Problem:** Mid-scan the three inventory lists render their *empty* states, indistinguishable from a finished-but-empty result. The menu-bar header says "Watching for changes" while a scan is actually running.

**Files:**
- Create: `Packages/PermissionsUI/Sources/PermissionsUI/ScanState.swift`
- Create: `Packages/PermissionsUI/Tests/PermissionsUITests/ScanStateTests.swift`
- Create: `Packages/PermissionsUI/Sources/PermissionsUI/ScanningPlaceholder.swift`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/DetailWindowView.swift` (the three `*DetailPage` structs)
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/MenuBarContentView.swift:66-73` (`headerStatusText`, `pulseTint`)

- [ ] **Step 1: Write the failing test**

Create `Packages/PermissionsUI/Tests/PermissionsUITests/ScanStateTests.swift`:

```swift
import Testing
@testable import PermissionsUI

@Suite("ScanState.showsScanningPlaceholder")
struct ScanStateTests {
    @Test("shows placeholder while scanning with nothing to show yet")
    func showsWhileScanningAndEmpty() {
        #expect(ScanState.showsScanningPlaceholder(
            isScanning: true, isEmpty: true, hasError: false, isSearching: false
        ))
    }

    @Test("hidden when not scanning")
    func hiddenWhenNotScanning() {
        #expect(!ScanState.showsScanningPlaceholder(
            isScanning: false, isEmpty: true, hasError: false, isSearching: false
        ))
    }

    @Test("hidden when there is already data")
    func hiddenWhenData() {
        #expect(!ScanState.showsScanningPlaceholder(
            isScanning: true, isEmpty: false, hasError: false, isSearching: false
        ))
    }

    @Test("hidden when an error is present — the error state owns the surface")
    func hiddenWhenError() {
        #expect(!ScanState.showsScanningPlaceholder(
            isScanning: true, isEmpty: true, hasError: true, isSearching: false
        ))
    }

    @Test("hidden while searching — a search miss is its own state")
    func hiddenWhenSearching() {
        #expect(!ScanState.showsScanningPlaceholder(
            isScanning: true, isEmpty: true, hasError: false, isSearching: true
        ))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --package-path Packages/PermissionsUI --filter ScanStateTests`
Expected: FAIL — `cannot find 'ScanState' in scope`.
(If SourceKit shows "No such module 'Testing'/'PermissionsUI'" in the editor, ignore it — only the `swift test` result is authoritative. See the project memory on SourceKit false positives.)

- [ ] **Step 3: Write the helper**

Create `Packages/PermissionsUI/Sources/PermissionsUI/ScanState.swift`:

```swift
/// Pure decision for when a domain section should show a "Scanning…"
/// placeholder instead of its empty state. Mid-scan with nothing yet must not
/// look like a finished empty result. (U1)
public enum ScanState {
    /// True only when a scan is running, there is nothing to show yet, there is
    /// no error (the error state owns that surface), and the user is not
    /// searching (a search miss is its own "no matches" state).
    public static func showsScanningPlaceholder(
        isScanning: Bool,
        isEmpty: Bool,
        hasError: Bool,
        isSearching: Bool
    ) -> Bool {
        isScanning && isEmpty && !hasError && !isSearching
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --package-path Packages/PermissionsUI --filter ScanStateTests`
Expected: PASS — 5 tests.

- [ ] **Step 5: Create the placeholder view**

Create `Packages/PermissionsUI/Sources/PermissionsUI/ScanningPlaceholder.swift`:

```swift
import SwiftUI

/// Shown in an inventory page while the initial scan is still running and there
/// is nothing to display yet. (U1)
struct ScanningPlaceholder: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text(String(localized: "Scanning…"))
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Scanning"))
    }
}
```

- [ ] **Step 6: Gate the Permissions page**

In `DetailWindowView.swift`, replace the body of `PermissionsDetailPage` (the `DetailPageScaffold { ... }` content closure, currently lines ~396-411) so the scanning placeholder wins first:

```swift
        ) {
            if let error = viewModel.tccScanError, isSchemaIssue(error) {
                SchemaMismatchBanner(error: error, domain: .tcc)
            }

            if ScanState.showsScanningPlaceholder(
                isScanning: viewModel.scanInProgress,
                isEmpty: viewModel.grants.isEmpty,
                hasError: viewModel.tccScanError != nil,
                isSearching: !searchText.isEmpty
            ) {
                ScanningPlaceholder()
            } else if filteredGrants.isEmpty && !searchText.isEmpty {
                EmptySearchView(query: searchText)
            } else {
                PermissionsSection(
                    grants: filteredGrants,
                    dataSource: viewModel.tccDataSource,
                    error: viewModel.tccScanError,
                    showsHeader: false
                )
            }
        }
```

- [ ] **Step 7: Gate the Launch Agents page**

In `LaunchAgentsDetailPage`, the content closure currently branches `if let error … else { if filteredItems.isEmpty && !searchText.isEmpty … }`. Insert the scanning check at the top of the `else` (no-error) branch:

```swift
            if let error = viewModel.launchAgentScanError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text(String(localized: "Couldn't read Launch Agents"))
                        .font(.headline)
                    Text(error.errorDescription ?? String(localized: "An error occurred reading the LaunchAgents directories."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
            } else if ScanState.showsScanningPlaceholder(
                isScanning: viewModel.scanInProgress,
                isEmpty: viewModel.launchAgents.isEmpty,
                hasError: false,
                isSearching: !searchText.isEmpty
            ) {
                ScanningPlaceholder()
            } else {
                if filteredItems.isEmpty && !searchText.isEmpty {
                    EmptySearchView(query: searchText)
                } else {
                    LaunchAgentsSection(
                        items: filteredItems,
                        dataSource: viewModel.launchAgentsDataSource,
                        showsHeader: false
                    )
                }
            }
```

- [ ] **Step 8: Gate the Background Items page**

In `BackgroundItemsDetailPage`, mirror the Permissions structure:

```swift
        ) {
            if let error = viewModel.btmScanError, isSchemaIssue(error) {
                SchemaMismatchBanner(error: error, domain: .btm)
            }

            if ScanState.showsScanningPlaceholder(
                isScanning: viewModel.scanInProgress,
                isEmpty: viewModel.btmItems.isEmpty,
                hasError: viewModel.btmScanError != nil,
                isSearching: !searchText.isEmpty
            ) {
                ScanningPlaceholder()
            } else if filteredItems.isEmpty && !searchText.isEmpty {
                EmptySearchView(query: searchText)
            } else {
                BackgroundItemsSection(
                    items: filteredItems,
                    dataSource: viewModel.btmDataSource,
                    error: viewModel.btmScanError,
                    showsHeader: false
                )
            }
        }
```

- [ ] **Step 9: Scanning state in the menu-bar header**

In `MenuBarContentView.swift`, update `headerStatusText` and `pulseTint`:

```swift
    private var pulseTint: Color {
        if viewModel.scanInProgress { return .blue }
        return isCleanAttention ? .green : .orange
    }

    private var headerStatusText: String {
        if viewModel.scanInProgress {
            return String(localized: "Scanning…")
        }
        switch attentionState {
        case .clean: return String(localized: "Watching for changes")
        case .fdaDenied, .btmOnlyFDADenied: return String(localized: "Action needed")
        case .schemaMismatch: return String(localized: "Schema mismatch")
        case .launchAgentError: return String(localized: "Action needed")
        }
    }
```

(Note: this `switch` now uses explicit `return`s — the original relied on implicit-return single expressions; with the leading `if` guard the explicit `return`s are required for the function to compile.)

- [ ] **Step 10: Build the package**

Run: `swift build --package-path Packages/PermissionsUI`
Expected: builds with no errors.

- [ ] **Step 11: Run the full UI test suite**

Run: `swift test --package-path Packages/PermissionsUI`
Expected: all tests pass (prior count + 5 new `ScanStateTests`).

- [ ] **Step 12: Commit**

```bash
git add Packages/PermissionsUI/Sources/PermissionsUI/ScanState.swift \
        Packages/PermissionsUI/Tests/PermissionsUITests/ScanStateTests.swift \
        Packages/PermissionsUI/Sources/PermissionsUI/ScanningPlaceholder.swift \
        Packages/PermissionsUI/Sources/PermissionsUI/DetailWindowView.swift \
        Packages/PermissionsUI/Sources/PermissionsUI/MenuBarContentView.swift
git commit -m "feat(ui): scanning placeholder + menu-bar Scanning state (U1)"
```

---

## Task 2: "Dismiss forever" relabel + confirmation (U2)

**Problem:** A change row's "Dismiss" is permanent, unlabeled-as-permanent, and unconfirmed — unlike the stale-app "Skip forever" flow, which confirms and explains the un-skip path.

**Files:**
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/ChangeRow.swift:31-33,66-87`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/DiffTabView.swift`

- [ ] **Step 1: Extract a reusable summary on `ChangeRow`**

In `ChangeRow.swift`, replace the instance `description` computed property (lines ~66-87) with a thin wrapper over a new `static` so `DiffTabView` can reuse it for the alert message:

```swift
    private var description: String {
        Self.summary(for: kind)
    }

    static func summary(for kind: Kind) -> String {
        switch kind {
        case .granted(let g):
            return String(localized: "Granted \(g.service.displayName) to \(g.app.displayName)")
        case .revoked(let g):
            return String(localized: "Revoked \(g.service.displayName) from \(g.app.displayName)")
        case .btmAdded(let i):
            return String(localized: "New background item: \(i.name)")
        case .btmRemoved(let i):
            return String(localized: "Removed background item: \(i.name)")
        case .btmDispositionFlipped(let change):
            let from = dispositionLabel(change.before.disposition)
            let to = dispositionLabel(change.after.disposition)
            return String(localized: "Disposition changed: \(change.after.name) (\(from) → \(to))")
        case .launchAgentAdded(let i):
            return String(localized: "New launch agent: \(i.label)")
        case .launchAgentRemoved(let i):
            return String(localized: "Removed launch agent: \(i.label)")
        case .launchAgentFlipped(let change):
            return launchAgentFlipDescription(change)
        }
    }
```

(The two existing helpers `launchAgentFlipDescription` and `dispositionLabel` are already `static` — the new `static summary(for:)` references them directly without `Self.`.)

- [ ] **Step 2: Relabel the Dismiss button**

In `ChangeRow.swift`, the menu (lines ~31-33): change the button title only.

```swift
                    if let onDismissForever {
                        Button(String(localized: "Dismiss forever"), role: .destructive) { onDismissForever() }
                    }
```

- [ ] **Step 3: Route dismiss through a confirmation alert in `DiffTabView`**

In `DiffTabView.swift`, add a pending-dismiss candidate and an alert that mirrors `StaleAppsTabView`. First add state + a small payload type at the top of the struct (after the `snoozeDuration` constant):

```swift
    @State private var pendingDismiss: PendingDismiss?

    private struct PendingDismiss: Identifiable {
        let id = UUID()
        let key: String
        let summary: String
    }
```

In `section(title:rows:)`, change the `onDismissForever` closure to set the candidate instead of dismissing immediately:

```swift
                    ChangeRow(
                        kind: kind,
                        onDismissForever: {
                            pendingDismiss = PendingDismiss(
                                key: key,
                                summary: ChangeRow.summary(for: kind)
                            )
                        },
                        onSnooze: {
                            dismissedStore.snooze(
                                key: key,
                                until: Date().addingTimeInterval(snoozeDuration)
                            )
                        }
                    )
```

Then attach the alert to the content VStack in the `totalVisible > 0` branch (the `VStack(alignment: .leading, spacing: 16) { … }`):

```swift
            if totalVisible > 0 {
                VStack(alignment: .leading, spacing: 16) {
                    if !tccVisible.isEmpty {
                        section(title: String(localized: "Permissions"), rows: tccVisible)
                    }
                    if !btmVisible.isEmpty {
                        section(title: String(localized: "Background Items"), rows: btmVisible)
                    }
                    if !laVisible.isEmpty {
                        section(title: String(localized: "Launch Agents"), rows: laVisible)
                    }
                }
                .alert(
                    String(localized: "Dismiss this change forever?"),
                    isPresented: Binding(
                        get: { pendingDismiss != nil },
                        set: { if !$0 { pendingDismiss = nil } }
                    ),
                    presenting: pendingDismiss
                ) { candidate in
                    Button(String(localized: "Dismiss forever"), role: .destructive) {
                        dismissedStore.dismissForever(key: candidate.key)
                        pendingDismiss = nil
                    }
                    Button(String(localized: "Cancel"), role: .cancel) {
                        pendingDismiss = nil
                    }
                } message: { candidate in
                    Text(String(localized: "Permission Pulse will stop showing \"\(candidate.summary)\". Use Reset All Data in Preferences to bring it back."))
                }
            } else {
                emptyContentState
            }
```

- [ ] **Step 4: Build the package**

Run: `swift build --package-path Packages/PermissionsUI`
Expected: builds with no errors.

- [ ] **Step 5: Run the UI test suite**

Run: `swift test --package-path Packages/PermissionsUI`
Expected: all tests pass (no behavioral test for this view change; the build + smoke-test §G covers it).

- [ ] **Step 6: Commit**

```bash
git add Packages/PermissionsUI/Sources/PermissionsUI/ChangeRow.swift \
        Packages/PermissionsUI/Sources/PermissionsUI/DiffTabView.swift
git commit -m "feat(ui): Dismiss forever confirmation parity with stale-app skip (U2)"
```

---

## Task 3: Quit & Reopen affordance for the FDA loop (U3)

**Problem:** After the user grants FDA in System Settings and returns, the running process is still denied (FDA for a running process needs a restart). The denied state persists with no in-app way to relaunch.

**Files:**
- Create: `Packages/PermissionsUI/Sources/PermissionsUI/AppRelauncher.swift`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/PermissionsEmptyStateView.swift:56-59`

- [ ] **Step 1: Create the relaunch helper**

Create `Packages/PermissionsUI/Sources/PermissionsUI/AppRelauncher.swift`:

```swift
// AppKit: there is no SwiftUI/Foundation primitive that restarts the running
// app. We spawn a fresh instance of our own bundle, then terminate this one —
// the standard Sparkle-less relaunch. Read-only: launches our own bundle only.
import AppKit

public enum AppRelauncher {
    /// Launch a new instance of this app, then terminate the current process.
    /// Used to recover from the FDA grant loop, where a running process stays
    /// denied until restart. (U3)
    public static func relaunch() {
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        Task { @MainActor in
            _ = try? await NSWorkspace.shared.openApplication(
                at: url,
                configuration: configuration
            )
            NSApp.terminate(nil)
        }
    }
}
```

- [ ] **Step 2: Add the Quit & Reopen button to the FDA-denied state**

In `PermissionsEmptyStateView.swift`, the `permissionDeniedView` currently ends the relaunch hint with a `Text` footnote (lines ~57-59). Replace that footnote with the hint plus a borderless "Quit & Reopen" button:

```swift
            VStack(spacing: 6) {
                Text(String(localized: "You'll need to relaunch Permission Pulse after granting."))
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                Button {
                    AppRelauncher.relaunch()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise")
                            .accessibilityHidden(true)
                        Text(String(localized: "Quit & Reopen"))
                    }
                    .font(.footnote.weight(.medium))
                }
                .buttonStyle(.link)
                .accessibilityHint(String(localized: "Restarts Permission Pulse so a newly granted permission takes effect"))
            }
```

- [ ] **Step 3: Build the package**

Run: `swift build --package-path Packages/PermissionsUI`
Expected: builds with no errors.

- [ ] **Step 4: Run the UI test suite**

Run: `swift test --package-path Packages/PermissionsUI`
Expected: all tests pass. (Relaunch is an AppKit side effect verified by smoke-test §A / the FDA-loop manual check; no unit test.)

- [ ] **Step 5: Commit**

```bash
git add Packages/PermissionsUI/Sources/PermissionsUI/AppRelauncher.swift \
        Packages/PermissionsUI/Sources/PermissionsUI/PermissionsEmptyStateView.swift
git commit -m "feat(ui): Quit & Reopen affordance for the FDA grant loop (U3)"
```

---

## Task 4: Discoverability hints for row actions (U4)

**Problem:** The per-row `⋯` dismiss/snooze and skip actions are low-prominence and undiscoverable.

**Files:**
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/DiffTabView.swift`
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/StaleAppsTabView.swift`

- [ ] **Step 1: Add a hint to the Recent Changes content state**

In `DiffTabView.swift`, inside the `totalVisible > 0` branch, append a footnote *after* the sections VStack but inside it (so it only shows when there are rows). Add as the last child of the `VStack(alignment: .leading, spacing: 16)`:

```swift
                    Text(String(localized: "Use the ⋯ menu on a row to snooze or dismiss a change."))
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
```

(Place it after the three `if !…Visible.isEmpty { section(…) }` blocks, before the closing brace of the VStack the `.alert` attaches to.)

- [ ] **Step 2: Add a hint to the Stale Apps content state**

In `StaleAppsTabView.swift`, the non-empty branch opens with a subtitle `Text(...)` then the rows. Add a second line under that subtitle:

```swift
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Apps with active grants you haven't used in \(staleThresholdDays)+ days"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(String(localized: "Use the ⋯ menu on a row to skip an app you don't want flagged."))
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                VStack(spacing: 0) {
```

(Leave the rest of the `VStack(spacing: 0) { ForEach … }` and the `.alert` unchanged.)

- [ ] **Step 3: Build the package**

Run: `swift build --package-path Packages/PermissionsUI`
Expected: builds with no errors.

- [ ] **Step 4: Run the UI test suite**

Run: `swift test --package-path Packages/PermissionsUI`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Packages/PermissionsUI/Sources/PermissionsUI/DiffTabView.swift \
        Packages/PermissionsUI/Sources/PermissionsUI/StaleAppsTabView.swift
git commit -m "feat(ui): one-line discoverability hints for row actions (U4)"
```

---

## Task 5: Re-openable Welcome / About (U5)

**Problem:** The Welcome window (with the read-only / no-network / never-modifies reassurance) is unreachable after the user clicks "Skip for now."

**Files:**
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/MenuBarContentView.swift` (`init`, footer, `MenuRowButton`)
- Modify: `PermissionPulse/PermissionPulse/PermissionPulseApp.swift:22-24`

- [ ] **Step 1: Make `MenuRowButton`'s shortcut optional**

In `MenuBarContentView.swift`, the `MenuRowButton` requires a shortcut. Make it optional so the Welcome row can omit one. Change the stored properties and `body`:

```swift
private struct MenuRowButton: View {
    let icon: String
    var iconTint: Color = .secondary
    let title: String
    var shortcutKey: KeyEquivalent? = nil
    var shortcutDisplay: String? = nil
    var showsChangeDot: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 22, height: 22)
                    .foregroundStyle(iconTint)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                if showsChangeDot {
                    PulseDot(tint: .orange)
                }
                if let shortcutDisplay {
                    Text(shortcutDisplay)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHovering ? Color.primary.opacity(0.06) : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .modifier(OptionalShortcut(key: shortcutKey))
    }
}

/// Applies `.keyboardShortcut` only when a key is present — `MenuRowButton`
/// rows like Welcome & About have no shortcut.
private struct OptionalShortcut: ViewModifier {
    let key: KeyEquivalent?

    func body(content: Content) -> some View {
        if let key {
            content.keyboardShortcut(key, modifiers: [.command])
        } else {
            content
        }
    }
}
```

(The four existing call sites pass `shortcutKey:`/`shortcutDisplay:` as before — they keep working unchanged because the params still accept those values.)

- [ ] **Step 2: Add the `onShowWelcome` closure to `MenuBarContentView`**

Change the public initializer and store the closure:

```swift
public struct MenuBarContentView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(AppViewModel.self) private var viewModel
    private let onShowWelcome: (() -> Void)?

    public init(onShowWelcome: (() -> Void)? = nil) {
        self.onShowWelcome = onShowWelcome
    }
```

- [ ] **Step 3: Add the "Welcome & About" footer row**

In the `footer` view, insert a new `MenuRowButton` after the Preferences row and before the `Divider()` that precedes Quit (only when the closure is provided):

```swift
            MenuRowButton(
                icon: "gearshape.fill",
                title: String(localized: "Preferences…"),
                shortcutKey: ",",
                shortcutDisplay: "⌘,"
            ) {
                activateAndOpen("preferences")
            }

            if let onShowWelcome {
                MenuRowButton(
                    icon: "info.circle",
                    title: String(localized: "Welcome & About")
                ) {
                    onShowWelcome()
                }
            }

            Divider()
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
```

- [ ] **Step 4: Wire the closure from the app target**

In `PermissionPulseApp.swift`, the `MenuBarExtra` content currently constructs `MenuBarContentView()`. Pass the closure that re-shows the existing welcome window:

```swift
        MenuBarExtra {
            MenuBarContentView(onShowWelcome: { [appDelegate] in
                appDelegate.showWelcomeWindow()
            })
                .environment(appDelegate.viewModel)
        } label: {
```

- [ ] **Step 5: Make `AppDelegate.showWelcomeWindow()` reachable**

In `PermissionPulseApp.swift`, `showWelcomeWindow()` is currently `private`. Change it to non-private so the closure above can call it (it stays in the app target; no public-API surface change to a package):

```swift
    func showWelcomeWindow() {
```

(If a welcome window is already open, `makeKeyAndOrderFront` simply re-fronts it — the existing `welcomeWindow` reference is reused, so repeated invocations don't stack windows.)

- [ ] **Step 6: Build the package, then the app target**

Run: `swift build --package-path Packages/PermissionsUI`
Expected: builds with no errors.

Run: `xcodebuild -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse -configuration Debug build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 7: Run the UI test suite**

Run: `swift test --package-path Packages/PermissionsUI`
Expected: all tests pass.

- [ ] **Step 8: Commit**

```bash
git add Packages/PermissionsUI/Sources/PermissionsUI/MenuBarContentView.swift \
        PermissionPulse/PermissionPulse/PermissionPulseApp.swift
git commit -m "feat(ui): re-openable Welcome & About from the menu bar (U5)"
```

---

## Task 6: Mock marker in the detail window (U6)

**Problem:** Detail pages pass `showsHeader: false`, which suppresses the `MockBadge` that normally rides in `SectionHeader`. A mock data source can paint unmarked in the detail window, conflicting with the mock-vs-real discipline.

**Files:**
- Modify: `Packages/PermissionsUI/Sources/PermissionsUI/DetailWindowView.swift` (`DetailPageScaffold`, the three inventory pages)

- [ ] **Step 1: Add a `dataSource` parameter to `DetailPageScaffold`**

In `DetailWindowView.swift`, extend `DetailPageScaffold` to optionally render a `MockBadge` in the title row:

```swift
private struct DetailPageScaffold<Content: View>: View {
    let title: String
    var inlineMeta: String? = nil
    let subtitle: String?
    var dataSource: AppViewModel.DataSource? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                if dataSource == .mock {
                    MockBadge()
                        .accessibilityLabel(String(localized: "Mock data"))
                }
                if let inlineMeta {
                    Text(inlineMeta)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                    }
                    content()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
```

- [ ] **Step 2: Pass each inventory page's data source**

In `PermissionsDetailPage`, add the argument to its `DetailPageScaffold(...)` call:

```swift
        DetailPageScaffold(
            title: String(localized: "Permissions"),
            inlineMeta: inlineMeta,
            subtitle: viewModel.grants.isEmpty
                ? nil
                : String(localized: "Tap a row to see what each grant unlocks and how it was given."),
            dataSource: viewModel.tccDataSource
        ) {
```

In `LaunchAgentsDetailPage`:

```swift
        DetailPageScaffold(
            title: String(localized: "Launch Agents"),
            subtitle: subtitle,
            dataSource: viewModel.launchAgentsDataSource
        ) {
```

In `BackgroundItemsDetailPage`:

```swift
        DetailPageScaffold(
            title: String(localized: "Background Items"),
            subtitle: subtitle,
            dataSource: viewModel.btmDataSource
        ) {
```

(Leave `RecentChangesDetailPage` and `StaleAppsDetailPage` without a `dataSource` — they render snapshot-derived data, not a scanner's mock/live output, so a Mock badge there would be meaningless.)

- [ ] **Step 3: Build the package**

Run: `swift build --package-path Packages/PermissionsUI`
Expected: builds with no errors.

- [ ] **Step 4: Run the UI test suite**

Run: `swift test --package-path Packages/PermissionsUI`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Packages/PermissionsUI/Sources/PermissionsUI/DetailWindowView.swift
git commit -m "feat(ui): surface Mock badge in detail window independent of showsHeader (U6)"
```

---

## Final verification (after all tasks)

- [ ] **App-target build + full suite:**

```bash
xcodebuild -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse -configuration Debug build
swift test --package-path Packages/PermissionsUI
```

Expected: `BUILD SUCCEEDED`; UI suite green with the 5 new `ScanStateTests`.

- [ ] **Manual smoke (covered by `scripts/smoke-test.sh` human checklist):** initial launch shows "Scanning…" not an empty list (U1); §G dismiss now asks for confirmation and names the change (U2); FDA-denied state shows "Quit & Reopen" (U3); Recent Changes / Stale Apps show the hint line (U4); menu bar has "Welcome & About" that re-opens the welcome window (U5).

---

## Self-Review

**Spec coverage:** U1 → Task 1 (scanning placeholder on 3 pages + menu-bar header). U2 → Task 2 (relabel + confirmation alert, parity with stale apps; undo-toast deliberately out per scope note). U3 → Task 3 (Quit & Reopen relauncher + button). U4 → Task 4 (hint lines on both pages). U5 → Task 5 (re-openable Welcome & About). U6 → Task 6 (Mock badge in detail scaffold). All six IDs covered.

**Placeholder scan:** No TBD/TODO; every code step shows complete code.

**Type consistency:** `ScanState.showsScanningPlaceholder(isScanning:isEmpty:hasError:isSearching:)` — identical signature in test (Task 1 Step 1), helper (Step 3), and all four call sites (Steps 6-9). `ChangeRow.summary(for:)` defined in Task 2 Step 1, consumed in Task 2 Step 3. `MenuRowButton` optional `shortcutKey`/`shortcutDisplay` (Task 5 Step 1) — existing callers still pass both; new Welcome caller omits both. `DetailPageScaffold.dataSource: AppViewModel.DataSource?` defined Task 6 Step 1, supplied Task 6 Step 2. `AppViewModel.DataSource` is `public` with `.mock`/`.live` cases (confirmed in `AppViewModel.swift`). `MockBadge()` zero-arg init and `DismissedDiffEntryStore.dismissForever(key:)`/`undismiss(key:)` confirmed against source.
