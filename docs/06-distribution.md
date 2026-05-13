# 06 — Distribution

**Channel:** GitHub Releases only.

**Form:** `.dmg` containing `Permission Pulse.app`.

**Signing:** Ad-hoc (`-`) for now. Notarization deferred indefinitely until a paid Apple Developer ID is acquired. Sparkle 2 auto-updates also deferred.

## Release flow (v1)

1. Bump version in the Xcode project and `CFBundleShortVersionString`.
2. Tag the commit: `git tag vX.Y.Z && git push origin vX.Y.Z`.
3. **GitHub Action** triggered by tag push:
   - Builds the app in Release with `xcodebuild`.
   - Ad-hoc-signs the resulting `.app`.
   - Packages it into a `.dmg` using `create-dmg` or `hdiutil`.
   - Creates a GitHub Release for the tag.
   - Uploads the `.dmg`.
4. Release notes are hand-written in `CHANGELOG.md` (added when we cut v0.1.0); the workflow pulls them from the most recent entry.

The notarization step is **not** in the workflow yet. When a Developer ID lands, this doc is updated and the workflow gains:

- Code signing with the Developer ID certificate from a CI secret.
- `xcrun notarytool submit` + `xcrun stapler staple`.
- (Optional) Sparkle appcast generation, hosted on GitHub Pages.

## Update mechanism (v1)

No auto-updater in v1. The app has a `Check for Updates…` menu item that opens `https://github.com/WallyMagill/permission-pulse/releases` in the browser.

Why not Sparkle now:
- Sparkle's update download lands a `.dmg` that Gatekeeper quarantines because we are unsigned. The user sees the same "Apple could not verify..." dialog they saw on initial install. Sparkle's value is mostly nullified.
- Sparkle 2.9.1 is from March 2024 and there is no public confirmation it compiles cleanly under Swift 6 strict concurrency. We don't want to ship a dependency we'd need to wrap.

When we add a Developer ID, we revisit. The architecture leaves room for Sparkle to slot in cleanly behind an `Updater` protocol in the App target.

## First-install instructions (replicated in README)

1. Download the `.dmg` from the Releases page.
2. Open the `.dmg`, drag `Permission Pulse.app` to `/Applications`.
3. **First launch:** right-click → Open. Gatekeeper warning is expected and the right-click → Open path is the standard workaround for unsigned OSS apps.
4. Grant Full Disk Access when the app asks.

## Anti-distribution

- **No Mac App Store.** The sandbox forbids reading TCC.db. Permission Pulse is structurally impossible inside MAS. We do not engineer for this option.
- **No Setapp.** Setapp requires notarization; we don't have it. Even if a Developer ID lands later, the OSS distribution model means Setapp's revenue split is hard to justify — leaving it open as a future option but not building toward it.
- **No third-party distribution sites.** Only the GitHub Releases page is the source of truth.

## Homebrew (post-v1)

Once we have at least one stable release, a `homebrew-tap` repo gets added: `brew install --cask wallymagill/tap/permission-pulse`. This is a v1.1 task; the cask points at GitHub Releases.

## File sizes / artifacts to expect

- `.app` bundle: 15–30 MB (depends on whether GRDB statically links SQLite vs uses the system one).
- `.dmg`: ~5 MB larger than the `.app`.
- Single artifact: universal binary (arm64 + x86_64) so older Intel Macs work.
