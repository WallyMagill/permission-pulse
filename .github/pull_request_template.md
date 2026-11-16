## What and why

<!-- One or two sentences. Link the issue if there is one. -->

## Checklist

- [ ] Tests run (`swift test --package-path Packages/<package>` for each touched package, and the app-target tests if app code changed). Paste the summary lines.
- [ ] No writes outside `~/Library/Application Support/com.wallymagill.permissionpulse/`, the app's own preferences, or an export location the user chooses.
- [ ] No network access, analytics, or telemetry added.
- [ ] Every new user-facing string goes through `String(localized:)`.
