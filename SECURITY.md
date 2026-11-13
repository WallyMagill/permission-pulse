# Security policy

## Reporting a vulnerability

Report security problems privately through GitHub: open the repository's **Security** tab and click **Report a vulnerability**. Do not open a public issue for a security problem.

Include the macOS version (`sw_vers`), the Permission Pulse version, what you did, and what happened. A proof of concept helps but is not required.

This is a one-maintainer, unpaid project, so there is no guaranteed response time. Reports are read and answered as soon as possible, and fixes ship in a normal GitHub release.

## Supported versions

Only the latest published release on the [Releases page](https://github.com/WallyMagill/permission-pulse/releases) gets fixes.

## In scope

- Permission Pulse writing anywhere other than `~/Library/Application Support/com.wallymagill.permissionpulse/`, its own preferences, or an export location the user chose.
- Permission Pulse modifying, copying out, or sending any data it reads (the TCC databases, the Background Task Management store, launchd files).
- Any network connection made by the app.
- Privilege escalation through the app: `sudo`, helper tools, or anything that gains more access than the user granted.
- A crafted file in a location the app reads (a launchd plist, a `.btm` file, a TCC database) that makes the app crash, hang, execute code, or show false data as complete.
- Problems with the release archive or the release scripts (`scripts/package-release.sh`, `scripts/verify-release.sh`), such as a tampered archive passing verification.

## Out of scope

- The Gatekeeper warning on first launch and the lack of notarization. Releases are ad-hoc signed by design because the project has no Apple Developer ID.
- Full Disk Access turning off after an update. macOS does this for every ad-hoc-signed app.
- What macOS itself exposes or hides (for example, macOS 27 hiding per-user permission records).
- Anything that requires an attacker to already have administrator access or to replace the app bundle.
