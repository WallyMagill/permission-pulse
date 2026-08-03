# Final pre-launch audit — Permission Pulse public repo

Paste everything below this line into a fresh Claude Code session started at the repo root.

---

You are running the **final pre-launch audit** of Permission Pulse (`github.com/WallyMagill/permission-pulse`), a free, MIT-licensed macOS menu-bar app for permission hygiene, distributed as an unsigned `.app.zip` via GitHub Releases. The repo is already public; this audit gates the **launch announcement and release tag**. Read `CLAUDE.md` at the repo root completely before doing anything else — it contains hard rules whose violation is a session-level failure.

## Non-negotiable execution rules

1. **Every subagent you spawn MUST run on `claude-fable-5`** — pass `model: "fable"` on every single `Agent` call, including verifiers and small lookup agents. Never downgrade any agent to haiku or sonnet for cost or speed. If you cannot pin the model on some call, do that work inline yourself instead of delegating it to a lesser model.
2. **The audit is read-only until Phase 4.** No file edits, no commits, no pushes, no `git` state changes during Phases 0–3. Subagents must be told explicitly they are read-only.
3. **Never run `sudo` or any privileged command.** This mirrors the app's own hard rule.
4. **Nothing leaves the machine.** No posting to GitHub (issues, comments, releases), no external services. The deliverable is a local report plus local fix commits.
5. Findings require **evidence**: `file:line` plus the exact code or command output that proves the claim. A finding without evidence is speculation and must not appear in the report.
6. Do not trust SourceKit "No such module" diagnostics in this repo — they are known false positives for the Testing module and sibling packages. Verify with `swift build` / `xcodebuild` instead.

## Phase 0 — Deterministic baseline (inline, no agents)

Establish ground truth before any subjective review:

- `git status` must be clean and on `main`; record the HEAD SHA the audit applies to.
- Run all four package suites: `swift test` in `Packages/PermissionsCore`, `PermissionsScanners`, `PermissionsStore`, `PermissionsUI`. All must pass.
- Clean app build: delete the project's DerivedData folder, then `xcodebuild -project PermissionPulse/PermissionPulse.xcodeproj -scheme PermissionPulse -configuration Release build`. Must succeed. (Audit Release, not Debug — Release is what ships.)
- Confirm CI config exists and matches what it claims to do (`.github/workflows/`).

If any of these fail, **stop** — fix the baseline first or report it as launch-blocking; auditing a broken baseline wastes every agent that follows.

## Phase 1 — Parallel audit fan-out

Spawn the following **seven agents in a single message** (they are independent), each on `model: "fable"`, each read-only, each instructed to return findings as a structured list: `{file:line, severity (CRITICAL/HIGH/MEDIUM/LOW), what a user/attacker/contributor would experience, why it happens, evidence, minimal fix}`. Tell each agent: report only findings you are confident are real after reading the surrounding context; no style preferences; no speculation; "no findings" is an acceptable answer.

**Agent A — Secrets and repo hygiene.** Scan the working tree AND git history (`git log --all -p` sampled by filename patterns, plus `git log --all --diff-filter=A --name-only`) for: API keys, tokens, signing identities/certs, notarization credentials, `.env` contents (only `.env.example` is allowed), private keys, absolute home-directory paths leaking the developer's machine layout into shipped strings, personal emails beyond the intended git author identity, and committed build artifacts (DerivedData, `.app`, `.zip`, `.dSYM`, `xcuserdata`). Verify `.gitignore` actually covers the build/products paths. Check both git remotes/config files for embedded credentials.

**Agent B — Hard-rules compliance (CLAUDE.md §"Hard rules").** Verify by exhaustive grep + read, not by trust: (1) every filesystem **write** API call in the codebase (`FileManager` creation/removal/move/write, `Data.write`, `String.write`, GRDB database paths, `UserDefaults` is exempt) targets only `~/Library/Application Support/com.wallymagill.permissionpulse/` or a user-chosen export URL; (2) no `Process` invocation runs `sudo`, `tccutil reset`, or anything mutating — list every `Process` launch with its binary and arguments and classify each as read-only or not; (3) no kernel/system extensions, no privileged helpers in the bundle or `SMAppService` registrations beyond `mainApp`; (4) no analytics, telemetry, crash reporters, or network calls — list every use of `URLSession`/`Network`/sockets; the only acceptable network touch is opening release/docs URLs in the user's browser via `NSWorkspace`/`openURL`; (5) no code copied from SwiftParseTCC (schema reference only — search for telltale identifiers); (6) entitlements and Info.plist contain nothing that implies Developer-ID-gated capabilities.

**Agent C — Security review of parsing surfaces.** The app parses untrusted external data: TCC.db rows via GRDB, `BackgroundItems-v*.btm` binary plists, LaunchAgent plists, `sfltool`/`mdls` text output, and its own snapshots.db. Review every decode path for: force-unwraps/`try!` on external data, unvalidated assumptions about schema/columns (CLAUDE.md lists TCC schema drift as a known fragile surface — confirm the version-check exists), integer/enum raw-value handling (`unknown(rawValue:)` losslessness), path traversal in export filenames, and SQL built by string concatenation anywhere. Confirm every SQLite open on a foreign database is genuinely read-only at the GRDB configuration level, not just by convention.

**Agent D — Concurrency and correctness.** Swift 6.3, MainActor-by-default, strict concurrency complete. Hunt: `Task { }` closures capturing `self` strongly where the task is long-lived (CLAUDE.md requires `[weak self]` for long-running tasks); spurious `DispatchQueue.main.async` or redundant `@MainActor` inside already-isolated contexts; completion-handler/async mixing not bridged once at the boundary; data races on `nonisolated` types; `@State`/`@Observable` misuse that loses state across view recreation; un-cancelled fire-and-forget tasks tied to view lifetime; retain cycles via delegates or stored closures (`UNUserNotificationCenter.delegate` is weak and must be retained — verify it is).

**Agent E — Tests, fixtures, and CI honesty.** Verify: each of the four packages has a real test target with non-trivial assertions (not just smoke `#expect(true)`); golden-output fixtures exist for `sfltool`/`tccutil` parsing per CLAUDE.md and are wired into tests; MockScanner implementations cannot ship as default (find the wiring that selects live vs mock and prove the release path selects live; confirm the UI "Mock" badge exists); Swift Testing and XCTest are not mixed within one target; CI workflow actually runs the suites it claims and would have caught a build break on the audit HEAD.

**Agent F — Docs, README, and release readiness.** Read `README.md`, `LICENSE`, `docs/06-distribution.md`, `docs/09-roadmap.md` against reality: version status in the roadmap matches the code and the tag about to be cut; README's first-launch Gatekeeper walkthrough (right-click → Open) is present and accurate for an unsigned app on current macOS; no doc promises a feature that doesn't exist (the "Check for Updates…" menu item is documented as not wired up — confirm docs and code agree); install/build-from-source instructions work from a clean clone (actually attempt the documented commands); LICENSE is MIT with correct attribution; no internal/private references (other repos, local paths, account names that shouldn't be public).

**Agent G — User-facing string and localization sweep.** Every user-facing string must go through `String(localized:)` — find hardcoded English in `Text(...)`, `Button(...)`, alerts, notification content, and accessibility labels across `PermissionsUI` and the app target. Also flag: typos, debug phrasing that leaked into UI copy, `print()` statements in production code (should be `os.Logger`), and any UI copy that references behavior changed by recent commits (e.g., the test-notification copy must NOT tell users to switch away — banners now present in the foreground via `NotificationPresentationDelegate`).

## Phase 2 — Adversarial verification

For **every CRITICAL and HIGH finding**, spawn an independent verifier agent (`model: "fable"`, one per finding, batched in parallel) whose prompt is: *"Try to refute this finding. Read the full surrounding context, callers, and configuration. Default to refuted if the evidence does not hold up."* Give it the finding verbatim plus file paths, nothing else from the original agent's reasoning. A finding survives only if the verifier fails to refute it. MEDIUM findings: verify inline yourself by reading the code. LOW: accept as-reported but label unverified.

## Phase 3 — Severity gate

Classify surviving findings:

- **Launch-blocking:** any hard-rule violation, any secret/credential exposure (including history), any crash-on-launch or data-loss path, MockScanner reachable in a release build, LICENSE/legal problems.
- **Fix-before-tag (HIGH):** real bugs users will hit in week one, misleading README/install steps, missing Gatekeeper walkthrough.
- **Post-launch backlog (MEDIUM/LOW):** everything else, written up but not fixed now.

## Phase 4 — Fix and re-verify

Only now may you edit. Fix launch-blocking and HIGH findings with minimal diffs, test-first where a regression test is expressible (Swift Testing, AAA pattern). Re-run the affected package suites and the Release build after each fix. Commit in small conventional-commit units (`fix:`/`docs:`/`test:`). **Do not push** — leave commits local for human review.

If a launch-blocking finding cannot be fixed safely (e.g., requires rotating something, or a secret is in git history and needs history rewriting), **stop and escalate** with exact remediation steps rather than improvising.

## Phase 5 — Final report

End with a single report containing:

1. **Verdict:** SHIP / SHIP AFTER LISTED FIXES / DO NOT SHIP, with the HEAD SHA audited.
2. Baseline results table (suites, Release build, CI).
3. Surviving findings by severity, each with evidence and status (fixed-in-commit / escalated / backlog).
4. Findings refuted in Phase 2 (one line each — what was claimed, why it was wrong).
5. **Human-only gates** the machine cannot clear — list explicitly so they aren't forgotten:
   - smoke-test.sh U1–U10 on Tahoe (deep links, inspector, ⌘-shortcuts, light+dark, Reduce Motion/Transparency)
   - VoiceOver pass (menu-bar label bridging is a known risk)
   - Launch-at-login toggle hand-test (SMAppService on a real machine)
   - Send-test-notification banner check while the app is frontmost
   - Gatekeeper first-launch walkthrough on a machine/account that has never opened the app
   - Notification banner shows "Permission Pulse" (not a generic bundle label) on the unsigned build
6. Anything you bounded or skipped (sampling depth on git history, etc.) — silent truncation is forbidden.

Scale: this is a "thoroughly audit" request — lean toward exhaustive coverage and adversarial verification, not brevity.
