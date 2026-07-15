# Permission Pulse v0.7.2 Release Integrity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make tests non-destructive, pin CI to the supported toolchain, and produce a reproducible verified ad-hoc-signed v0.7.2 archive.

**Architecture:** Add a test-runtime guard around production AppDelegate side effects, split release packaging from verification, and make CI exercise the same build/test/verify entry points used by maintainers. Publication remains manual and cannot occur unless the downloaded artifact passes the independent verifier.

**Tech Stack:** Swift 6.3, Swift Testing, Xcode 26.5, macOS 26 GitHub Actions, Bash 3.2, `xcodebuild`, `codesign`, `lipo`, `ditto`, `shasum`.

## Global Constraints

- Deployment target remains macOS 14.6.
- Release output remains universal arm64 plus x86_64 and ad-hoc signed.
- No Developer ID, notarization, DMG, Sparkle, or signing secrets.
- Tests and `smoke-test.sh --keep` never mutate production Application Support or UserDefaults.
- Release scripts write only beneath an explicit output directory.
- Preserve the existing untracked `docs/superpowers/prompts/` content.

---

### Task 1: Prevent test hosts from booting production services

**Files:**
- Create: `PermissionPulse/PermissionPulse/AppRuntimeEnvironment.swift`
- Modify: `PermissionPulse/PermissionPulse/PermissionPulseApp.swift:154-196`
- Test: `PermissionPulse/PermissionPulseTests/PermissionPulseTests.swift`

**Interfaces:**
- Produces: `AppRuntimeEnvironment.init(environment:)` and `isRunningTests: Bool`.
- Consumed by: `AppDelegate.applicationDidFinishLaunching(_:)`, smoke tests, and CI.

- [ ] **Step 1: Write failing detection tests**

```swift
@Suite struct AppRuntimeEnvironmentTests {
    @Test func explicitTestModeIsDetected() {
        #expect(AppRuntimeEnvironment(environment: ["PERMISSION_PULSE_TEST_MODE": "1"]).isRunningTests)
    }

    @Test func xctestConfigurationIsDetected() {
        #expect(AppRuntimeEnvironment(environment: ["XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration"]).isRunningTests)
    }

    @Test func ordinaryLaunchIsNotTestMode() {
        #expect(!AppRuntimeEnvironment(environment: [:]).isRunningTests)
    }
}
```

- [ ] **Step 2: Verify the red state**

Run:

```bash
xcodebuild test -project PermissionPulse/PermissionPulse.xcodeproj \
  -scheme PermissionPulse -destination 'platform=macOS,arch=arm64' \
  -only-testing:PermissionPulseTests/AppRuntimeEnvironmentTests CODE_SIGNING_ALLOWED=NO
```

Expected: FAIL because `AppRuntimeEnvironment` is undefined.

- [ ] **Step 3: Implement the runtime boundary**

```swift
import Foundation

struct AppRuntimeEnvironment: Sendable {
    let environment: [String: String]

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    var isRunningTests: Bool {
        environment["PERMISSION_PULSE_TEST_MODE"] == "1"
            || environment["XCTestConfigurationFilePath"] != nil
    }
}
```

Start `applicationDidFinishLaunching(_:)` with:

```swift
guard !AppRuntimeEnvironment().isRunningTests else {
    Self.logger.debug("Skipping production launch services in test mode")
    return
}
```

- [ ] **Step 4: Verify focused and full app suites**

Run the Step 2 command, then:

```bash
PERMISSION_PULSE_TEST_MODE=1 xcodebuild test \
  -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:PermissionPulseTests CODE_SIGNING_ALLOWED=NO
```

Expected: both end with `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add PermissionPulse/PermissionPulse/AppRuntimeEnvironment.swift \
  PermissionPulse/PermissionPulse/PermissionPulseApp.swift \
  PermissionPulse/PermissionPulseTests/PermissionPulseTests.swift
git commit -m "test: isolate app services during test runs"
```

### Task 2: Make `smoke-test.sh --keep` non-destructive

**Files:**
- Modify: `scripts/smoke-test.sh:71-165`
- Create: `scripts/tests/smoke-test-safety-test.sh`

**Interfaces:**
- Consumes: `PERMISSION_PULSE_TEST_MODE=1` from Task 1.
- Produces: `SMOKE_DRY_RUN=1` and a `--keep` path containing no removal commands.

- [ ] **Step 1: Write the failing shell regression**

```bash
#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/../.." && pwd)
output=$(SMOKE_DRY_RUN=1 "$repo_root/scripts/smoke-test.sh" --keep --no-launch)
if printf '%s\n' "$output" | grep -Eq 'rm .*snapshots\.db|defaults delete'; then
    printf 'FAIL: --keep attempted destructive cleanup\n' >&2
    exit 1
fi
printf '%s\n' "$output" | grep -F 'state preservation verified'
printf 'PASS: --keep contains no state deletion\n'
```

- [ ] **Step 2: Run and verify failure**

```bash
chmod +x scripts/tests/smoke-test-safety-test.sh
scripts/tests/smoke-test-safety-test.sh
```

Expected: FAIL because the script unconditionally deletes `snapshots.db` before app tests and has no dry-run seam.

- [ ] **Step 3: Centralize state removal and remove app-test deletion**

Add:

```bash
run_or_print() {
    if [[ "${SMOKE_DRY_RUN:-0}" == "1" ]]; then
        printf 'DRY-RUN'; printf ' %q' "$@"; printf '\n'
    else
        "$@"
    fi
}

remove_live_state() {
    [[ $WIPE_STATE -eq 1 ]] || return 0
    [[ -f "$DB" ]] && run_or_print rm -f "$DB"
    defaults read "$BUNDLE_DOMAIN" >/dev/null 2>&1 \
        && run_or_print defaults delete "$BUNDLE_DOMAIN"
    return 0
}
```

Call `remove_live_state` only in section 0. Delete the unconditional `rm -f "$DB"` in section 4. Execute app tests with:

```bash
APP_TESTS_OUT=$(PERMISSION_PULSE_TEST_MODE=1 xcodebuild test \
  -project "$PROJECT" -scheme "$SCHEME" \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:PermissionPulseTests CODE_SIGNING_ALLOWED=NO 2>&1)
```

When `SMOKE_DRY_RUN=1`, stop after the state phase and print `state preservation verified`.

- [ ] **Step 4: Verify shell syntax and safety**

```bash
bash -n scripts/smoke-test.sh scripts/tests/smoke-test-safety-test.sh
scripts/tests/smoke-test-safety-test.sh
```

Expected: exits 0 and prints both preservation lines.

- [ ] **Step 5: Commit**

```bash
git add scripts/smoke-test.sh scripts/tests/smoke-test-safety-test.sh
git commit -m "fix: keep smoke tests away from live app state"
```

### Task 3: Pin CI and run supported validation

**Files:**
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: Tasks 1-2.
- Produces: pinned macOS 26/Xcode 26.5 package, app-test, analyzer, and safety jobs.

- [ ] **Step 1: Preserve current failure evidence**

```bash
gh run view 27962911140 --repo WallyMagill/permission-pulse --log-failed \
  | rg 'Xcode_16.4|Swift version 6.1|ExportToolbar.swift.*error'
```

Expected: Xcode 16.4/Swift 6.1 and `ExportToolbar.swift` actor-isolation failures.

- [ ] **Step 2: Replace the floating configuration**

Apply to both jobs:

```yaml
runs-on: macos-26
env:
  DEVELOPER_DIR: /Applications/Xcode_26.5.app/Contents/Developer
```

Keep the four package test commands. Replace the app build-only step with:

```yaml
- name: Test app target
  env:
    PERMISSION_PULSE_TEST_MODE: "1"
  run: |
    xcodebuild test \
      -project PermissionPulse/PermissionPulse.xcodeproj \
      -scheme PermissionPulse \
      -destination 'platform=macOS,arch=arm64' \
      -only-testing:PermissionPulseTests CODE_SIGNING_ALLOWED=NO

- name: Analyze app target
  run: |
    xcodebuild analyze \
      -project PermissionPulse/PermissionPulse.xcodeproj \
      -scheme PermissionPulse -configuration Debug \
      -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

- name: Verify smoke preservation
  run: scripts/tests/smoke-test-safety-test.sh
```

Delete the obsolete macOS 15/app-tests-unavailable comment.

- [ ] **Step 3: Validate YAML and local equivalents**

```bash
ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci.yml"); puts "yaml ok"'
for package in PermissionsCore PermissionsScanners PermissionsStore PermissionsUI; do
  swift test --package-path "Packages/$package"
done
PERMISSION_PULSE_TEST_MODE=1 xcodebuild test \
  -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:PermissionPulseTests CODE_SIGNING_ALLOWED=NO
```

Expected: YAML parses and all suites pass.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: pin Xcode 26 and run app tests"
```

### Task 4: Build an independent release verifier

**Files:**
- Create: `scripts/verify-release.sh`
- Create: `scripts/tests/release-verifier-test.sh`

**Interfaces:**
- Produces: `scripts/verify-release.sh APP_OR_ZIP EXPECTED_VERSION EXPECTED_BUILD`.
- Consumed by: Task 5 packaging, CI, and post-upload verification.

- [ ] **Step 1: Write positive and negative integration fixtures**

The test script accepts `RELEASE_APP EXPECTED_VERSION EXPECTED_BUILD`, copies and ad-hoc signs the app, expects verification success with those arguments, then re-signs another copy with:

```xml
<?xml version="1.0"?>
<plist version="1.0"><dict>
  <key>com.apple.security.get-task-allow</key><true/>
</dict></plist>
```

It must assert the debug-entitled copy is rejected. Add cases that edit `CFBundleShortVersionString` to `9.9.9`, thin the executable to arm64 with `lipo -thin`, and add an unrelated top-level archive file; each must be rejected.

- [ ] **Step 2: Verify the red state**

```bash
rm -rf /tmp/pp-verifier-derived
xcodebuild -project PermissionPulse/PermissionPulse.xcodeproj \
  -scheme PermissionPulse -configuration Release \
  -derivedDataPath /tmp/pp-verifier-derived \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build
scripts/tests/release-verifier-test.sh \
  /tmp/pp-verifier-derived/Build/Products/Release/PermissionPulse.app 0.7.1 11
```

Expected: FAIL because `verify-release.sh` does not exist.

- [ ] **Step 3: Implement the verifier**

Use `set -euo pipefail`, extract zip input to `mktemp -d`, require one top-level app, and perform:

```bash
identifier=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$plist")
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$plist")
build=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$plist")
[[ "$identifier" == 'com.wallymagill.permissionpulse' ]]
[[ "$version" == "$expected_version" ]]
[[ "$build" == "$expected_build" ]]

architectures=$(lipo -archs "$app/Contents/MacOS/PermissionPulse")
printf '%s\n' "$architectures" | grep -qw arm64
printf '%s\n' "$architectures" | grep -qw x86_64

signature=$(codesign -dvvv "$app" 2>&1)
printf '%s\n' "$signature" | grep -F 'Signature=adhoc'
! printf '%s\n' "$signature" | grep -Eq 'Authority=|TeamIdentifier=[A-Z0-9]'

entitlements=$(codesign -d --entitlements - "$app" 2>/dev/null || true)
! printf '%s\n' "$entitlements" | grep -Fq 'com.apple.security.get-task-allow'
codesign --verify --deep --strict --verbose=2 "$app"
```

Reject archive entries outside the single app and symlinks escaping the extraction root.

- [ ] **Step 4: Run syntax and fixture tests**

```bash
chmod +x scripts/verify-release.sh scripts/tests/release-verifier-test.sh
bash -n scripts/verify-release.sh scripts/tests/release-verifier-test.sh
scripts/tests/release-verifier-test.sh \
  /tmp/pp-verifier-derived/Build/Products/Release/PermissionPulse.app 0.7.1 11
```

Expected: the current 0.7.1/build 11 fixture passes; all four tampered fixtures fail. Task 5 updates its invocation to 0.7.2/build 12.

- [ ] **Step 5: Commit**

```bash
git add scripts/verify-release.sh scripts/tests/release-verifier-test.sh
git commit -m "build: verify release signatures and archives"
```

### Task 5: Package and version v0.7.2 deterministically

**Files:**
- Create: `Config/Version.xcconfig`
- Modify: `PermissionPulse/PermissionPulse.xcodeproj/project.pbxproj`
- Create: `scripts/package-release.sh`
- Modify: `scripts/smoke-test.sh:111-129`
- Test: `scripts/tests/release-verifier-test.sh`

**Interfaces:**
- Produces: v0.7.2/build 12 and `scripts/package-release.sh VERSION OUTPUT_DIR`.
- Consumes: Task 4 verifier.

- [ ] **Step 1: Centralize version settings**

Create:

```xcconfig
MARKETING_VERSION = 0.7.2
CURRENT_PROJECT_VERSION = 12
```

Wire `Config/Version.xcconfig` as the base configuration for app/test configs, remove duplicated literal versions, and change smoke expectations to `0.7.2`/`12`.

Verify:

```bash
xcodebuild -project PermissionPulse/PermissionPulse.xcodeproj \
  -scheme PermissionPulse -showBuildSettings \
  | rg 'MARKETING_VERSION = 0.7.2|CURRENT_PROJECT_VERSION = 12'
```

Expected: both settings appear.

- [ ] **Step 2: Implement packaging**

The script must require a clean tracked tree, use isolated DerivedData, and run this core flow. A `PERMISSION_PULSE_PACKAGE_TESTING=1` seam may bypass the clean-tree gate only while developing the script; it must append `testingDirtyTree=true` to the manifest and name the archive `PermissionPulse-v0.7.2-TESTING-DIRTY.app.zip` so it cannot be confused with a publishable artifact.

```bash
xcodebuild -project "$project" -scheme PermissionPulse -configuration Release \
  -derivedDataPath "$derived" ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build

app="$derived/Build/Products/Release/PermissionPulse.app"
codesign --force --sign - --options runtime --timestamp=none "$app"
"$repo_root/scripts/verify-release.sh" "$app" "$expected_version" "$expected_build"
ditto -c -k --keepParent "$app" "$temporary_zip"
"$repo_root/scripts/verify-release.sh" "$temporary_zip" "$expected_version" "$expected_build"
mv "$temporary_zip" "$final_zip"
shasum -a 256 "$final_zip" > "$final_zip.sha256"
```

Before signing the app, sign every nested executable bundle from deepest to shallowest. Write a manifest with version, build, full Git SHA, archive basename, and checksum. Final names appear only after all checks pass.

- [ ] **Step 3: Run end-to-end packaging and tamper tests**

```bash
rm -rf /tmp/permission-pulse-v072
PERMISSION_PULSE_PACKAGE_TESTING=1 \
  scripts/package-release.sh 0.7.2 /tmp/permission-pulse-v072
scripts/verify-release.sh \
  /tmp/permission-pulse-v072/PermissionPulse-v0.7.2-TESTING-DIRTY.app.zip 0.7.2 12
rm -rf /tmp/pp-verifier-derived
xcodebuild -project PermissionPulse/PermissionPulse.xcodeproj \
  -scheme PermissionPulse -configuration Release \
  -derivedDataPath /tmp/pp-verifier-derived \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build
scripts/tests/release-verifier-test.sh \
  /tmp/pp-verifier-derived/Build/Products/Release/PermissionPulse.app 0.7.2 12
```

Expected: testing zip/checksum/manifest exist, the manifest is visibly non-publishable, and tamper tests reject invalid fixtures. The Workstream A exit gate reruns packaging from a clean committed tree without the testing seam.

- [ ] **Step 4: Commit**

```bash
git add Config/Version.xcconfig PermissionPulse/PermissionPulse.xcodeproj/project.pbxproj \
  scripts/package-release.sh scripts/smoke-test.sh scripts/tests/release-verifier-test.sh
git commit -m "build: package verified v0.7.2 artifacts"
```

### Task 6: Document and exercise the release gate

**Files:**
- Modify: `README.md`
- Modify: `docs/06-distribution.md`
- Modify: `docs/07-build-and-test.md`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: Tasks 1-5.
- Produces: one supported release path and CI artifact verification.

- [ ] **Step 1: Add packaging verification to CI**

```yaml
- name: Build and verify release artifact
  run: |
    scripts/package-release.sh 0.7.2 "$RUNNER_TEMP/permission-pulse-release"
    scripts/verify-release.sh \
      "$RUNNER_TEMP/permission-pulse-release/PermissionPulse-v0.7.2.app.zip" \
      0.7.2 12
```

- [ ] **Step 2: Replace manual release documentation**

Document these exact commands:

```bash
scripts/smoke-test.sh --keep --no-launch
scripts/package-release.sh 0.7.2 /tmp/permission-pulse-v0.7.2
scripts/verify-release.sh \
  /tmp/permission-pulse-v0.7.2/PermissionPulse-v0.7.2.app.zip 0.7.2 12
```

State that v0.7.1 remains immutable but its development-signed artifact is superseded by v0.7.2. Replace stale approximate test counts with fresh counts.

- [ ] **Step 3: Run the workstream gate**

```bash
bash -n scripts/smoke-test.sh scripts/package-release.sh scripts/verify-release.sh scripts/tests/*.sh
scripts/tests/smoke-test-safety-test.sh
for package in PermissionsCore PermissionsScanners PermissionsStore PermissionsUI; do
  swift test --package-path "Packages/$package"
done
PERMISSION_PULSE_TEST_MODE=1 xcodebuild test \
  -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:PermissionPulseTests CODE_SIGNING_ALLOWED=NO
xcodebuild analyze -project PermissionPulse/PermissionPulse.xcodeproj \
  -scheme PermissionPulse -configuration Debug \
  -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
rm -rf /tmp/permission-pulse-v072
PERMISSION_PULSE_PACKAGE_TESTING=1 \
  scripts/package-release.sh 0.7.2 /tmp/permission-pulse-v072
git diff --check
```

Expected: all commands exit 0, tests pass, analyzer succeeds, and the dirty-tree testing artifact verifies under its non-publishable filename.

- [ ] **Step 4: Commit**

```bash
git add README.md docs/06-distribution.md docs/07-build-and-test.md .github/workflows/ci.yml
git commit -m "docs: define the verified v0.7.2 release flow"
```

- [ ] **Step 5: Prove clean-tree publication packaging**

```bash
rm -rf /tmp/permission-pulse-v072-clean
scripts/package-release.sh 0.7.2 /tmp/permission-pulse-v072-clean
scripts/verify-release.sh \
  /tmp/permission-pulse-v072-clean/PermissionPulse-v0.7.2.app.zip 0.7.2 12
```

Expected: clean publishable zip, checksum, and manifest verify without the testing seam.

## Workstream A Exit Gate

- [ ] CI is pinned to macOS 26/Xcode 26.5 and runs all automated suites.
- [ ] App tests and `--keep` cannot mutate live state.
- [ ] Artifact verification proves both positive and negative fixtures.
- [ ] Packaging creates only entitlement-clean, universal, ad-hoc-signed v0.7.2 archives.
- [ ] Documentation supersedes v0.7.1 without replacing its artifact.
