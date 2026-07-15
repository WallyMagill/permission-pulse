# Permission Pulse v0.7.2 Data Fidelity and Trust Design

**Status:** Approved in brainstorming on 2026-07-15

**Workstream:** C of 3

**Depends on:** Workstream A validation infrastructure and Workstream B lifecycle boundaries

## Purpose

The current stale-app pipeline drops ordinary bundle-ID TCC clients because their resolved application paths are not retained. Partial scanner reads are logged but presented as complete, TCC authorization transitions are computed but not rendered, and LaunchAgent disabled state is lost from history. This workstream makes identity, coverage, history, and presentation match the evidence the app actually possesses.

## Goals

- Resolve application paths for ordinary bundle-ID TCC records.
- Give bundle-ID and path-only applications one stable, collision-resistant identity contract.
- Preserve existing stale-app dismissal choices while migrating to stable keys.
- Surface partial scanner coverage and prevent partial data from corrupting snapshots.
- Render and search TCC authorization transitions.
- Persist LaunchAgent disabled state without creating a false migration transition.
- Remove search affordances from pages that cannot honor them.

## Non-goals

- Writing to TCC, Background Task Management, launchd, or application bundles.
- Inferring permissions or disabled state that the source did not provide.
- Adding network-based reputation, telemetry, or cloud identity resolution.
- Replacing the existing under-flag-over-over-flag safety policy.
- Expanding the permission-service taxonomy beyond fields needed for the audited defects.

## Constraints

- TCC and Background Task Management access remains SQLite/file read-only with query-only enforcement where applicable.
- Scanners never request administrator privileges, invoke `sudo`, or mutate protected operating-system state.
- Partial or uncertain evidence must under-flag and must never create a false historical removal.
- Stable identity is derived only from local bundle identifiers and standardized local paths; no network lookup is allowed.
- Existing v4 snapshot history and legacy dismissal choices must survive migration.
- User-visible state, warning, search, transition, and accessibility copy uses the existing localization pattern.
- All changes remain compatible with macOS 14.6, Swift 6 strict concurrency, and the existing four-package dependency direction.

## Stable Application Identity

`AppIdentity` gains a computed stable key with two explicit forms:

- `bundle:<bundle-id>` when `bundleID` is nonempty.
- `path:<standardized-file-path>` when no bundle ID exists and a bundle path is available.

The path form standardizes file URLs and resolves redundant path components without resolving arbitrary symlinks. An identity with neither a bundle ID nor a path is not eligible for stale-app tracking.

The stable key becomes the identity for:

- TCC deduplication where an app key is needed.
- Stale-app grouping.
- Stale-app SwiftUI row identity.
- Skip-forever persistence and lookup.

`DismissedStaleAppStore` stores stable keys. During load, legacy values without a recognized prefix are interpreted as raw bundle IDs and migrated to `bundle:<legacy-value>` on the next persistence operation. No existing skip choice is lost.

For TCC `client_type == 0`, one resolver call obtains the installed application URL and derives its display name. `AppIdentity` receives both values. Failure to resolve an uninstalled app retains its bundle ID and display fallback but leaves its path nil; such an app remains visible in permissions but is not falsely classified as stale.

Path-only `client_type == 1` records retain their standardized URL and use the path stable key. Multiple path-only clients no longer collapse under the empty bundle-ID string.

## Scanner Output and Coverage

The scanner contract returns a generic `ScannerOutput<Item>` containing `items` and zero or more machine-readable coverage warnings. Full inability to read any relevant source still throws `ScannerError`.

Coverage warnings identify categories rather than raw private paths, including:

- User TCC source unavailable.
- System TCC source unavailable.
- A known LaunchAgent source unavailable.
- One or more source entries malformed or unreadable when that omission is material.

Mocks can emit complete, degraded, or failed results deterministically.

`ScanCoordinator` maps each domain into an explicit availability state:

- `complete(lastUpdated:)`
- `degraded(lastUpdated:, warnings:)`
- `failed(lastSuccessful:, error:)`

Complete output replaces live data and is eligible for a snapshot. Degraded output is shown with a warning and may replace the current live list, but is not eligible for snapshot persistence. Failed output preserves the last successful list, marks it stale, and does not replace it with an empty list.

`SnapshotCoordinator.scanFullySucceeded()` requires complete availability in all persisted domains. This prevents a missing source from appearing as a mass removal in the next diff.

Overview, each affected detail page, menu-bar attention, and accessibility labels use the same availability model. A domain page showing degraded or last-known data always includes a visible status banner and timestamp.

## TCC Transition Presentation

The existing `DomainChange<PermissionGrant>` retains both before and after values. `ChangeRow.Kind` gains a TCC transition case that shows:

- Application and permission service.
- Previous and current authorization labels.
- A stable dismissal key that includes the permission identity and transition values.

`DiffTabView` includes TCC changed rows alongside granted and revoked rows. Badge counts, empty states, dismissal behavior, routes, accessibility summaries, and weekly digest totals all use the same rendered event set. A TCC-only diff can no longer create an unreviewed badge with an apparently empty Recent Changes page.

## LaunchAgent History Migration

Snapshot schema v5 adds:

- `launch_agents.is_disabled`, persisted for every new LaunchAgent row.
- A per-snapshot marker indicating whether LaunchAgent disabled state was captured.

Existing snapshots migrate transactionally with the marker set to false. Newly written snapshots set it to true. Existing history and all other domain rows remain intact.

LaunchAgent diffing uses a domain-specific equivalence rule:

- If both snapshots captured disabled state, `isDisabled` participates in change detection.
- If either snapshot lacks it, disabled state alone cannot produce a change.
- All previously persisted LaunchAgent fields continue to participate regardless of marker state.

This permits real disabled transitions between v5 snapshots while preventing a false one-time transition immediately after upgrade.

## Search Behavior

The Overview page does not display search because it is a summary/navigation surface. Permissions, Launch Agents, Background Items, Recent Changes, and Stale Apps retain contextual search.

Recent Changes filters the same rendered row model used by the list rather than reimplementing domain logic. Search matches localized summary text plus relevant app, service, label, path, developer, and identifier fields. The selected Yesterday/Last 7 Days window remains unchanged while filtering. No-match state uses the existing localized search-empty presentation.

## Error Handling

- Unknown scanner errors map to temporary unavailability, not permission denial.
- A resolver failure never fabricates a bundle path.
- An identity lacking both bundle ID and path remains visible where possible but is excluded from stale tracking with a diagnostic log.
- Degraded scans never write snapshots.
- Schema migration failure rolls back and leaves existing history unchanged.
- A corrupt legacy dismissal value is ignored with a diagnostic rather than crashing or clearing valid entries.
- Search operates only on in-memory rendered data and never triggers additional disk access.

## Verification Gates

- A fixture bundle ID resolved by the application workspace produces both display name and bundle path.
- An unresolved bundle ID remains visible but is not stale-probed.
- Bundle and path stable keys are deterministic, distinct, and survive snapshot round trips.
- Two path-only grants do not group or dismiss one another accidentally.
- Legacy raw bundle-ID dismissals migrate and remain effective.
- One successful plus one failed TCC source produces degraded output and no snapshot.
- One unreadable LaunchAgent source produces degraded output and no false removals.
- A full scanner failure preserves last-known data and reports its last successful timestamp.
- TCC allowed-to-limited and limited-to-allowed transitions render, count, dismiss, search, and digest correctly.
- A v4 database migrates to v5 without losing snapshots or child rows.
- A legacy-to-v5 LaunchAgent comparison does not report a disabled-only transition.
- Two v5 snapshots do report a real disabled-state transition.
- Overview has no search field; Recent Changes search filters every rendered change kind.
- VoiceOver identifies complete, degraded, failed, and stale-data states without relying on color or icons.

## Human FDA Verification

Because real TCC and Background Task Management databases require Full Disk Access, release validation includes a manual pass on a representative Mac:

1. Verify complete user and system TCC coverage with FDA.
2. Remove or deny access in a controlled test account and verify degraded/failed labeling.
3. Confirm normal installed applications appear as stale candidates when their last-used evidence crosses the configured threshold.
4. Confirm path-only clients retain independent identity.
5. Confirm no scanner writes to protected system databases or launchd locations.

## Documentation

Update architecture, risk, build/test, and roadmap documentation for scanner coverage states, stable application keys, schema v5, rendered TCC transitions, and the remaining human FDA/Intel verification limits.
