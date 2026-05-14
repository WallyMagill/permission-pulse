# TCC.db schema dump — macOS Tahoe (26)

Captured 2026-05-14 from Wally's dev machine. This file feeds `TCCScannerSQLite`'s `requiredColumns` set and the TCC-service-string → `PermissionService` mapping table.

Re-capture if `ScannerError.schemaMismatch` starts firing on a newer macOS build.

## Schema

The `access` table schema is **character-identical** between the user DB (`~/Library/Application Support/com.apple.TCC/TCC.db`) and the system DB (`/Library/Application Support/com.apple.TCC/TCC.db`). One decoder works for both paths.

```sql
CREATE TABLE access (
    service                            TEXT     NOT NULL,
    client                             TEXT     NOT NULL,
    client_type                        INTEGER  NOT NULL,
    auth_value                         INTEGER  NOT NULL,
    auth_reason                        INTEGER  NOT NULL,
    auth_version                       INTEGER  NOT NULL,
    csreq                              BLOB,
    policy_id                          INTEGER,
    indirect_object_identifier_type    INTEGER,
    indirect_object_identifier         TEXT     NOT NULL DEFAULT 'UNUSED',
    indirect_object_code_identity      BLOB,
    flags                              INTEGER,
    last_modified                      INTEGER  NOT NULL DEFAULT (CAST(strftime('%s','now') AS INTEGER)),
    pid                                INTEGER,
    pid_version                        INTEGER,
    boot_uuid                          TEXT     NOT NULL DEFAULT 'UNUSED',
    last_reminded                      INTEGER  NOT NULL DEFAULT (CAST(strftime('%s','now') AS INTEGER)),
    PRIMARY KEY (service, client, client_type, indirect_object_identifier),
    FOREIGN KEY (policy_id) REFERENCES policies(id) ON DELETE CASCADE ON UPDATE CASCADE
);
```

| cid | name                            | type    | notnull | dflt_value                                  | pk |
|----:|---------------------------------|---------|--------:|---------------------------------------------|---:|
|  0  | service                         | TEXT    | 1       |                                             | 1  |
|  1  | client                          | TEXT    | 1       |                                             | 2  |
|  2  | client_type                     | INTEGER | 1       |                                             | 3  |
|  3  | auth_value                      | INTEGER | 1       |                                             | 0  |
|  4  | auth_reason                     | INTEGER | 1       |                                             | 0  |
|  5  | auth_version                    | INTEGER | 1       |                                             | 0  |
|  6  | csreq                           | BLOB    | 0       |                                             | 0  |
|  7  | policy_id                       | INTEGER | 0       |                                             | 0  |
|  8  | indirect_object_identifier_type | INTEGER | 0       |                                             | 0  |
|  9  | indirect_object_identifier      | TEXT    | 1       | `'UNUSED'`                                  | 4  |
| 10  | indirect_object_code_identity   | BLOB    | 0       |                                             | 0  |
| 11  | flags                           | INTEGER | 0       |                                             | 0  |
| 12  | last_modified                   | INTEGER | 1       | `CAST(strftime('%s','now') AS INTEGER)`     | 0  |
| 13  | pid                             | INTEGER | 0       |                                             | 0  |
| 14  | pid_version                     | INTEGER | 0       |                                             | 0  |
| 15  | boot_uuid                       | TEXT    | 1       | `'UNUSED'`                                  | 0  |
| 16  | last_reminded                   | INTEGER | 1       | `CAST(strftime('%s','now') AS INTEGER)`     | 0  |

## Services present on this machine

### User DB (`~/Library/Application Support/com.apple.TCC/TCC.db`)

```
kTCCServiceAddressBook
kTCCServiceAppleEvents
kTCCServiceBluetoothAlways
kTCCServiceCalendar
kTCCServiceCamera
kTCCServiceFileProviderDomain
kTCCServiceFocusStatus
kTCCServiceLiverpool
kTCCServiceMediaLibrary
kTCCServiceMicrophone
kTCCServicePhotos
kTCCServiceReminders
kTCCServiceSystemPolicyAppBundles
kTCCServiceSystemPolicyAppData
kTCCServiceSystemPolicyDesktopFolder
kTCCServiceSystemPolicyDocumentsFolder
kTCCServiceSystemPolicyDownloadsFolder
kTCCServiceSystemPolicyNetworkVolumes
kTCCServiceUbiquity
kTCCServiceWebBrowserPublicKeyCredential
```

### System DB (`/Library/Application Support/com.apple.TCC/TCC.db`)

```
kTCCServiceAccessibility
kTCCServiceDeveloperTool
kTCCServiceListenEvent
kTCCServicePostEvent
kTCCServiceScreenCapture
kTCCServiceSystemPolicyAllFiles
```

Dumped with `sudo sqlite3` because the system DB is root-owned at 0644. The shipping app does not need sudo — `Configuration.readonly = true` + `?immutable=1` is sufficient at runtime once the user grants FDA to Permission Pulse.

## Notes for the implementer

- **`requiredColumns` (finalized):** `{service, client, client_type, auth_value, last_modified}`. All five are `NOT NULL` so the row decoder never sees null for them.
- **`indirect_object_identifier` is `NOT NULL DEFAULT 'UNUSED'`.** The planner's plan had it as `String?` in `TCCRow`; adjust to non-optional `String` and treat the sentinel `"UNUSED"` as "no target" rather than `nil`.
- **`auth_value == 2` (allowed) is the v0.3.0 inclusion criterion.** Other values (0 denied, 1 unknown, 3 limited) skipped per planner section 4.4.
- **v0.3.0 reads both DBs (scope decision 2026-05-14).** A single `TCCScannerSQLite` instance reads both user and system DBs internally via a parallel task group; results are unioned and sorted in the scanner. Same schema means one decoder.
- **`PermissionService` enum expansion in v0.3.0 (scope decision 2026-05-14):**
  - Existing: `.accessibility .screenRecording .fullDiskAccess .microphone .camera .automation .filesAndFolders` (7).
  - Adding for user DB: `.photos .calendar .contacts .reminders .bluetooth .mediaLibrary .appManagement` (7).
  - Adding for system DB: `.inputMonitoring .developerTool` (2; `kTCCServicePostEvent` is skipped — see service mapping below).
  - **Total target: 16 cases.**
- **Service → `PermissionService` mapping (authoritative for v0.3.0):**

  | TCC service | `PermissionService` | Source DB |
  |---|---|---|
  | `kTCCServiceAccessibility` | `.accessibility` | system |
  | `kTCCServiceScreenCapture` | `.screenRecording` | system |
  | `kTCCServiceSystemPolicyAllFiles` | `.fullDiskAccess` | system |
  | `kTCCServiceMicrophone` | `.microphone` | user |
  | `kTCCServiceCamera` | `.camera` | user |
  | `kTCCServiceAppleEvents` | `.automation` | user |
  | `kTCCServiceSystemPolicyDesktopFolder` | `.filesAndFolders` | user |
  | `kTCCServiceSystemPolicyDocumentsFolder` | `.filesAndFolders` | user |
  | `kTCCServiceSystemPolicyDownloadsFolder` | `.filesAndFolders` | user |
  | `kTCCServiceSystemPolicyNetworkVolumes` | `.filesAndFolders` | user |
  | `kTCCServiceSystemPolicyRemovableVolumes` | `.filesAndFolders` | user (not on this machine) |
  | `kTCCServicePhotos` | `.photos` | user |
  | `kTCCServiceCalendar` | `.calendar` | user |
  | `kTCCServiceAddressBook` | `.contacts` | user |
  | `kTCCServiceReminders` | `.reminders` | user |
  | `kTCCServiceBluetoothAlways` | `.bluetooth` | user |
  | `kTCCServiceMediaLibrary` | `.mediaLibrary` | user |
  | `kTCCServiceSystemPolicyAppBundles` | `.appManagement` | user |
  | `kTCCServiceSystemPolicyAppData` | `.appManagement` | user |
  | `kTCCServiceListenEvent` | `.inputMonitoring` | system |
  | `kTCCServiceDeveloperTool` | `.developerTool` | system |

- **Skipped with `.debug` log (planner section 4.3):**
  - `kTCCServiceFileProviderDomain` — internal File Provider extension plumbing.
  - `kTCCServiceFocusStatus` — internal Focus state.
  - `kTCCServiceLiverpool` — HomeKit (Apple's internal codename).
  - `kTCCServiceUbiquity` — iCloud Drive internals.
  - `kTCCServiceWebBrowserPublicKeyCredential` — WebAuthn / passkey.
  - `kTCCServicePostEvent` — synthetic input posting; not a distinct Privacy & Security pane, collapses into Accessibility for end users. Reconsider in v0.4.0 if user feedback asks for it.
- **Source-DB tag is informational, not load-bearing.** The scanner does not need to know which DB a row came from — only that both DBs were read and results unioned. The "Source DB" column above is documentation for the next maintainer.
- **cdHash / `csreq` policy unchanged:** v0.3.0 attributes by `client` (bundle ID) only. Input Monitoring rows get the same treatment despite CLAUDE.md's tightening note — surfacing the grant with bundle-ID attribution is consistent with CLAUDE.md's "match by bundle ID first, verify with cdHash where present" wording. cdHash verification lands in v0.6.0.
