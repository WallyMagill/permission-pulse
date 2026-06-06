# 06 — Distribution

**Channel:** GitHub Releases only.

**Form (current):** a `.zip` of `Permission Pulse.app` — `PermissionPulse-vX.Y.Z.app.zip`. The `.dmg` packaging described below is planned but not yet built.

**Signing:** Ad-hoc (`-`) for now. Notarization deferred indefinitely until a paid Apple Developer ID is acquired. Sparkle 2 auto-updates also deferred.

## Release flow (current — manual)

Releases v0.2.0 → v0.7.1 were all cut by hand. There is **no** tag-triggered release workflow; CI only builds and tests (see `docs/07-build-and-test.md`). The actual steps:

1. Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` across the six pbxproj configs and update `scripts/smoke-test.sh`'s expected-version literals.
2. Run `scripts/smoke-test.sh` and work the §A–§I human checklist.
3. Build Release with `xcodebuild`, locate the `.app` in DerivedData, and zip it to `PermissionPulse-vX.Y.Z.app.zip`.
4. Tag the commit: `git tag vX.Y.Z && git push origin vX.Y.Z`.
5. Create the release and upload the zip: `gh release create vX.Y.Z PermissionPulse-vX.Y.Z.app.zip --title "vX.Y.Z — …" --notes "…"`.

Release notes are written by hand directly in the GitHub Release. There is **no `CHANGELOG.md`** in the repo — `docs/09-roadmap.md` is the closest thing to a changelog.

## Release flow (planned automation — not built)

A future tag-triggered GitHub Action could: build Release with `xcodebuild` → ad-hoc-sign the `.app` → package a `.dmg` via `create-dmg`/`hdiutil` → create the release → upload. When a Developer ID lands it would also gain code signing from a CI secret, `xcrun notarytool submit` + `xcrun stapler staple`, and optional Sparkle appcast generation on GitHub Pages.

## Update mechanism (v1)

No auto-updater in v1. The plan is a `Check for Updates…` menu item that opens `https://github.com/WallyMagill/permission-pulse/releases` in the browser — **this item is not wired up in the app yet**; for now users check the Releases page directly.

Why not Sparkle now:
- Sparkle's update download lands a `.dmg` that Gatekeeper quarantines because we are unsigned. The user sees the same "Apple could not verify..." dialog they saw on initial install. Sparkle's value is mostly nullified.
- Sparkle 2.9.1 is from March 2024 and there is no public confirmation it compiles cleanly under Swift 6 strict concurrency. We don't want to ship a dependency we'd need to wrap.

When we add a Developer ID, we revisit. The architecture leaves room for Sparkle to slot in cleanly behind an `Updater` protocol in the App target.

## First-install instructions (replicated in README)

1. Download `PermissionPulse-vX.Y.Z.app.zip` from the Releases page and unzip it.
2. Drag `Permission Pulse.app` to `/Applications`.
3. **First launch:** right-click → Open. Gatekeeper warning is expected and the right-click → Open path is the standard workaround for unsigned OSS apps.
4. Grant Full Disk Access when the app asks (required for TCC + BTM reads; macOS may ask you to quit and reopen).

## Anti-distribution

- **No Mac App Store.** The sandbox forbids reading TCC.db. Permission Pulse is structurally impossible inside MAS. We do not engineer for this option.
- **No Setapp.** Setapp requires notarization; we don't have it. Even if a Developer ID lands later, the OSS distribution model means Setapp's revenue split is hard to justify — leaving it open as a future option but not building toward it.
- **No third-party distribution sites.** Only the GitHub Releases page is the source of truth.

## Homebrew (post-v1)

Once we have at least one stable release, a `homebrew-tap` repo gets added: `brew install --cask wallymagill/tap/permission-pulse`. This is a v1.1 task; the cask points at GitHub Releases.

## File sizes / artifacts to expect

- `.app` bundle: ~16 MB.
- `PermissionPulse-vX.Y.Z.app.zip`: ~5 MB (v0.7.1 was 4.8 MB).
- The Release binary is a **universal binary (arm64 + x86_64)** — the Intel slice is built but is **untested** (development is Apple-Silicon-only). The app should run on Intel Macs in principle, but no one has verified it.
- A `.dmg` would add a few MB over the zip, once `.dmg` packaging is built.
