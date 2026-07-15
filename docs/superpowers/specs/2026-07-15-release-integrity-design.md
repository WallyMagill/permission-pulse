# Permission Pulse v0.7.2 Release Integrity Design

**Status:** Approved in brainstorming on 2026-07-15

**Workstream:** A of 3

**Depends on:** None

**Required before release:** Workstreams B and C must also pass their gates

## Purpose

Permission Pulse v0.7.1 was published with an Apple Development signature and the `com.apple.security.get-task-allow` entitlement even though the documented distribution contract requires ad-hoc signing. The current CI workflow also floats on `macos-latest`, used Xcode 16.4 for recent failing runs, and does not execute the app-target tests. The release process must become deterministic, repeatable, and safe for both users and maintainers before v0.7.2 is published.

## Goals

- Make CI use the repository's required macOS 26 and Xcode 26.5 toolchain.
- Run all four Swift package suites and the app-target tests in CI.
- Make app-target tests incapable of reading, deleting, or writing the maintainer's live Permission Pulse state.
- Produce a universal, ad-hoc-signed v0.7.2 application archive from one supported script.
- Reject development signatures, unintended entitlements, wrong versions, missing architectures, and malformed archives.
- Make `scripts/smoke-test.sh --keep` genuinely non-destructive.
- Preserve v0.7.1 as an immutable historical release and point users to v0.7.2.

## Non-goals

- Developer ID signing, notarization, Sparkle, a DMG, the Mac App Store, or Homebrew distribution.
- A tag-triggered publication workflow that holds signing secrets.
- Supporting Xcode 16 or lowering the committed Swift/Xcode requirements.
- Replacing the existing v0.7.1 binary in place.

## Constraints

- Deployment target remains macOS 14.6.
- The release remains a universal arm64 and x86_64 application.
- No signing identities, certificates, credentials, or other secrets enter the repository.
- Release tooling writes only to an explicit isolated output directory.
- Test tooling does not mutate `~/Library/Application Support/com.wallymagill.permissionpulse` or the production `UserDefaults` domain.
- GitHub Releases remains the only distribution channel.

## CI Architecture

Both CI jobs pin `runs-on: macos-26` and set `DEVELOPER_DIR` to `/Applications/Xcode_26.5.app/Contents/Developer`. The workflow prints `sw_vers`, `xcodebuild -version`, and `swift --version` before validation so a runner-image drift is visible in logs.

The package job runs the complete test suite for:

1. `PermissionsCore`
2. `PermissionsScanners`
3. `PermissionsStore`
4. `PermissionsUI`

The app job runs `PermissionPulseTests`, not merely a Debug build. A dedicated test runtime mode prevents the host application from starting live scanners, media observation, notifications, welcome windows, or the production snapshot store while XCTest/Swift Testing is active. Tests continue to construct explicit in-memory or temporary-file dependencies.

CI also performs a clean Debug build, static analysis, a universal Release build, packaging, and artifact verification. It never publishes an artifact.

## Safe Test Runtime

The app target gains a small runtime-environment boundary that detects the explicit test environment supplied by the shared scheme and CI. In test mode, application launch skips production side effects. Component tests remain responsible for creating their own temporary snapshot databases and isolated `UserDefaults` suites.

`scripts/smoke-test.sh` no longer deletes the production snapshot database before app tests. Its `--keep` option prohibits every state-removal path, including later test setup. A default smoke run may still clear live Permission Pulse state, but it must announce each exact path and defaults domain before doing so.

## Packaging Architecture

`scripts/package-release.sh` is the only documented release-artifact entry point. It accepts the expected semantic version and an output directory, then:

1. Requires a clean tracked worktree and records the exact Git commit.
2. Builds Release into isolated DerivedData with automatic signing disabled.
3. Confirms the built bundle's marketing version and build number.
4. Confirms the executable contains arm64 and x86_64 slices.
5. Signs nested executable code from the inside out, then signs the app ad hoc with timestamping disabled and hardened-runtime options retained.
6. Calls `scripts/verify-release.sh` against the unarchived app.
7. Archives exactly one `PermissionPulse.app` using `ditto`.
8. Expands the zip into a fresh temporary directory and verifies it again.
9. Writes a SHA-256 file and a plain-text manifest containing the version, build number, Git commit, artifact name, and checksum.

`scripts/verify-release.sh` is independently usable on a local app or downloaded archive. It fails unless:

- Bundle identifier is `com.wallymagill.permissionpulse`.
- Version and build match the supplied expectations.
- The main executable is universal arm64 and x86_64.
- `codesign` reports an ad-hoc signature.
- No signing authority or team identifier is embedded.
- `com.apple.security.get-task-allow` is absent.
- No unexpected entitlements exist.
- `codesign --verify --deep --strict` succeeds.
- An archive expands to exactly one top-level application bundle with no traversal or unrelated payload.

Gatekeeper assessment is recorded but is not treated as an automated success condition because an ad-hoc, unnotarized application is expected to require Apple's documented Privacy & Security → Open Anyway flow.

## Release Procedure

The release remains intentionally manual:

1. Merge all three v0.7.2 workstreams after their automated and human gates pass.
2. Bump marketing/build versions in one source of truth and verify generated build settings.
3. Run the complete smoke and human FDA checklist.
4. Run the packaging script from the release commit.
5. Tag that exact commit as `v0.7.2`.
6. Create the GitHub release and upload the zip, checksum, and manifest.
7. Download the published files into a fresh directory and rerun verification.
8. Amend v0.7.1 release notes to state that its development-signed artifact is superseded by v0.7.2; do not replace or delete the old asset.

## Failure Behavior

Packaging is fail-closed. Any failed build, signing, entitlement, architecture, version, archive, or checksum check exits nonzero and leaves no publishable-looking final zip. Temporary outputs may be retained under a clearly marked failure directory for diagnosis.

CI concurrency continues to cancel superseded runs on the same branch. A failed validation cannot trigger publication because publication remains a separate manual action.

## Verification Gates

- Four package suites pass under pinned Swift 6.3/Xcode 26.5.
- App-target tests pass under the explicit test runtime.
- Debug build and static analysis pass.
- Clean universal Release build passes.
- A deliberately development-signed fixture is rejected.
- A fixture containing `get-task-allow` is rejected.
- Wrong-version, single-architecture, and malformed-archive fixtures are rejected.
- A correctly ad-hoc-signed fixture passes before and after archiving.
- `smoke-test.sh --keep --no-launch` leaves a sentinel production database and defaults key unchanged.
- The published v0.7.2 download matches its manifest checksum and passes release verification.

## Documentation

Update the README and distribution/build documentation to make the packaging script the sole supported flow, describe the v0.7.1 supersession, record current test counts, and retain the Open Anyway instructions for an unnotarized ad-hoc build.
