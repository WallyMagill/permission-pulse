# 06 — Distribution

**Channel:** GitHub Releases only.

**Form (current):** a `.zip` of `PermissionPulse.app` — `PermissionPulse-vX.Y.Z.app.zip`. The `.dmg` packaging described below is planned but not yet built.

**Signing:** Ad-hoc (`-`) for now. Notarization deferred indefinitely until a paid Apple Developer ID is acquired. Sparkle 2 auto-updates also deferred.

## v0.7.2 candidate release flow (manual publication)

`scripts/package-release.sh` is the only supported release-artifact entry point. It builds from the exact clean `HEAD`, creates a universal arm64 + x86_64 app, signs it ad hoc without entitlements, independently verifies the app before and after archiving, and writes the zip, SHA-256 sidecar, and manifest to the explicit output directory. Do not build or zip a release artifact by hand.

After all v0.7.2 automated and human gates pass, run these exact commands from the clean release commit:

```bash
scripts/smoke-test.sh --keep --no-launch
scripts/package-release.sh 0.7.2 /tmp/permission-pulse-v0.7.2
scripts/verify-release.sh \
  /tmp/permission-pulse-v0.7.2/PermissionPulse-v0.7.2.app.zip 0.7.2 12
```

The script refuses to overwrite existing output. If the output directory already holds an artifact from a previous attempt, delete those three files (`PermissionPulse-v0.7.2.app.zip`, `PermissionPulse-v0.7.2.app.zip.sha256`, `PermissionPulse-v0.7.2.manifest.txt`) first, or pick a new output directory. If a run fails while installing the final files, it removes the ones it already installed, so a failed run does not leave a checksum or manifest without its archive.

The output directory must then contain the independently verified archive, `PermissionPulse-v0.7.2.app.zip.sha256`, and `PermissionPulse-v0.7.2.manifest.txt`. Confirm the checksum sidecar and manifest both name that exact archive, and confirm the manifest's `gitSHA` is the release commit. The manifest also records the toolchain that built the archive (`xcode=`, `sdk=`, `swift=`); release artifacts are built with Xcode 27.2.

Publication remains an intentional manual boundary. CI builds and verifies the exact archive shape above from a clean checkout, but it never tags, creates a GitHub release, or uploads files. A maintainer must tag the manifest's exact commit as `v0.7.2`, create the GitHub release, upload the zip, checksum, and manifest, download them into a fresh directory, check the downloaded checksum, and rerun `scripts/verify-release.sh` before announcing the release. Release notes are written by hand; there is no `CHANGELOG.md` in the repository.

v0.7.1 remains the latest published release until v0.7.2 is actually tagged and published. After publication, amend the v0.7.1 release notes to point users to v0.7.2, but do not delete, replace, or modify the existing v0.7.1 asset.

## Update mechanism (v1)

No auto-updater in v1. `Check for Updates…` — in the menu-bar dropdown and in Preferences → General → About — only opens `https://github.com/WallyMagill/permission-pulse/releases` in the browser; the app itself makes no network request.

Why not Sparkle now:
- Sparkle's update download lands a `.dmg` that Gatekeeper quarantines because we are unsigned. The user sees the same "Apple could not verify..." dialog they saw on initial install. Sparkle's value is mostly nullified.
- Sparkle 2.9.1 is from March 2024 and there is no public confirmation it compiles cleanly under Swift 6 strict concurrency. We don't want to ship a dependency we'd need to wrap.

When we add a Developer ID, we revisit. The architecture leaves room for Sparkle to slot in cleanly behind an `Updater` protocol in the App target.

## First-install instructions (replicated in README)

1. Download `PermissionPulse-vX.Y.Z.app.zip` from the Releases page and unzip it.
2. Drag `PermissionPulse.app` to `/Applications`.
3. **First launch:** double-click → dismiss the "Apple could not verify…" dialog with **Done** → System Settings → Privacy & Security → **Open Anyway** → authenticate. macOS 15 (Sequoia) removed the right-click → Open override for unsigned apps; that shortcut only still works on macOS 14. The `xattr -d com.apple.quarantine` CLI route is the alternative.
4. Grant Full Disk Access when the app asks (required for TCC + BTM reads; macOS may ask you to quit and reopen).
5. After each update, turn Full Disk Access back on: every ad-hoc-signed build has a different signature, so replacing the app turns its existing grant off. The first scan of a new build that finds access off opens a "Full Disk Access was turned off" window with these steps (once per build), and offers to reopen the app if macOS needs a restart.

Users find the running version in Preferences → General → About, next to **Check for Updates…**.

## Anti-distribution

- **No Mac App Store.** The sandbox forbids reading TCC.db. Permission Pulse is structurally impossible inside MAS. We do not engineer for this option.
- **No Setapp.** Setapp requires notarization; we don't have it. Even if a Developer ID lands later, the OSS distribution model means Setapp's revenue split is hard to justify — leaving it open as a future option but not building toward it.
- **No third-party distribution sites.** Only the GitHub Releases page is the source of truth.

## Homebrew (post-v1)

Once we have at least one stable release, a `homebrew-tap` repo gets added: `brew install --cask wallymagill/tap/permission-pulse`. This is a v1.1 task; the cask points at GitHub Releases.

## File sizes / artifacts to expect

- `.app` bundle: ~16 MB.
- `PermissionPulse-vX.Y.Z.app.zip`: ~5 MB (v0.7.1 was 4.8 MB).
- `PermissionPulse-vX.Y.Z.app.zip.sha256`: SHA-256 checksum sidecar.
- `PermissionPulse-vX.Y.Z.manifest.txt`: version, build, exact Git commit, archive name, checksum, and the Xcode, macOS SDK, and Swift versions used.
- The Release binary is a **universal binary (arm64 + x86_64)** — the Intel slice is built but is **untested** (development is Apple-Silicon-only). The app should run on Intel Macs in principle, but no one has verified it.
- A `.dmg` would add a few MB over the zip, once `.dmg` packaging is built.
