# Permission Pulse Agent Access Foundation Design

**Status:** Approved in brainstorming on 2026-07-15; pending written-spec review

**Slice:** 1 of 3 in the Agent Access program

**Depends on:** Current v0.7.2 scanner coverage, snapshot schema v5, diff, inspector, export, and weekly-digest infrastructure

**Follow-on slices:** Mainstream Adapter Expansion; Extensible Harness Expansion

## Purpose

AI coding agents accumulate durable approvals across user settings, repository settings, managed policy, MCP servers, hooks, trusted directories, sandbox rules, and macOS host permissions. Each vendor exposes a current configuration view, but developers lack a calm, independent history of what persistent access has accumulated and what became broader.

Agent Access extends Permission Pulse's existing permission-hygiene model to answer:

> What durable access have AI coding agents accumulated on this Mac, and what became broader since the last trustworthy snapshot?

The foundation slice delivers authoritative persistent-posture coverage for Codex and Claude Code, separate macOS-permission evidence for related desktop applications, detection-only coverage for eight additional agent families, daily history, and evidence-backed Permission Debt findings.

## Program decomposition

The ten-agent ambition is intentionally split into independently releasable slices.

1. **Agent Access Foundation:** shared evidence model, bounded discovery, persistence, drift, UI, full Codex and Claude Code adapters, desktop-app TCC context, and detection for the other eight agents.
2. **Mainstream Adapter Expansion:** full adapters for Cursor, Gemini CLI, OpenCode, GitHub Copilot CLI, and Grok Build.
3. **Extensible Harness Expansion:** full adapters for Pi, Oh My Pi, and Kiro, including their extension, custom-policy, and agent-specific configuration surfaces.

This specification covers only the foundation slice.

## Goals

- Detect Codex, Claude Code, Cursor, Gemini CLI, Pi, Oh My Pi, Grok Build, OpenCode, GitHub Copilot CLI, and Kiro CLI without launching them.
- Interpret all supported persistent local Codex and Claude Code permission layers within documented and monitored locations.
- Normalize agent-specific rules without discarding their source, matcher, precedence, or uncertainty.
- Correlate supported desktop surfaces with existing TCC evidence while keeping every process boundary explicit.
- Store secret-free daily Agent Access evidence and show trustworthy yesterday and seven-day drift.
- Surface concrete Permission Debt reasons instead of a numerical security score.
- Preserve Permission Pulse's read-only, local-only, no-telemetry trust model.
- Keep existing TCC, BTM, and LaunchAgent history working when Agent Access is degraded or failed.

## Non-goals

- Recording commands, tool calls, file reads, prompts, transcripts, or session histories.
- Monitoring live agent processes or proving that an agent accessed a particular file.
- Inspecting cloud-account, organization, or server-side permissions.
- Reading source code, user documents, arbitrary repository files, credential stores, authentication state, or secret values.
- Executing an agent CLI, evaluating configuration, starting MCP servers, loading plugins, or running hooks.
- Enforcing, rewriting, or automatically remediating agent policies.
- Assigning a universal risk score or classifying an agent as malicious.
- Providing full permission interpretation for the eight detection-only agents in this slice.
- Inferring that a CLI agent used Terminal, an IDE, or another host without explicit local evidence.

## Approved scope exception

The existing product scope says Permission Pulse does not read file contents. Agent permission posture cannot be interpreted without reading agent configuration. This design introduces one narrow exception:

> Permission Pulse may read documented agent configuration and policy files solely to extract permission posture. It never reads source code, documents, prompts, transcripts, session history, credentials, authentication stores, or arbitrary files. It never persists raw configuration or secret values; it persists only normalized permission facts and safe provenance.

The implementation must update the project vision, scope, architecture, data-source, permission, risk, and README documentation so this exception is public and unambiguous.

## Product truth model

Agent Access distinguishes five concepts.

### Agent posture

Durable rules declared by a supported local agent configuration. Posture includes approvals, denials, sandbox mode, writable roots, trusted directories, network policy, MCP approval, hooks, and other supported persistent capabilities.

### macOS capability

TCC access held by a concrete desktop application or host process. A macOS grant remains attributed to that bundle. It is never merged into a CLI rule.

### Potential access path

A carefully worded relationship between an agent surface and a host capability. A relationship may be shown only when one of these evidence conditions holds:

- the desktop bundle is itself the agent surface;
- a documented local integration explicitly names the host;
- the user explicitly associates a CLI agent with a host in Agent Access preferences.

Otherwise, host applications appear as separate context with copy such as "If you run CLI agents through this host" rather than as a proven relationship.

### Observed change

A normalized persistent fact changed between two complete Agent Access captures. Changes do not prove runtime use.

### Unknown

Session flags, in-memory approvals, cloud-side settings, dynamic configuration, unresolved environment expansion, unsupported syntax, configuration outside monitored roots, and any source Permission Pulse cannot interpret confidently.

Unknown never means safe. The UI must state the boundary instead of filling it with a default.

## Support and availability are separate

Every agent surface has two independent dimensions.

**Support level** describes what Permission Pulse knows how to interpret:

- `full`: all documented persistent local permission sources in this slice are supported;
- `partial`: some documented persistent permission sources are supported;
- `detectedOnly`: installation or configuration presence is recognized, but permission meaning is not interpreted.

**Scan availability** describes the latest attempt:

- `never`;
- `complete`;
- `degraded` with explicit omitted or ambiguous sources;
- `failed` with optional last-known evidence.

A detected-only agent can have a complete detection scan. A fully supported adapter can be degraded. The UI must never collapse these dimensions into one badge.

## Foundation support matrix

| Family | Surface | Foundation support |
|---|---|---|
| OpenAI | Codex CLI and Codex agent configuration | Full persistent-posture coverage |
| OpenAI | Codex desktop app | Agent posture plus separately attributed TCC evidence |
| OpenAI | ChatGPT desktop app | TCC evidence only; cloud and session state unknown |
| Anthropic | Claude Code | Full persistent-posture coverage |
| Anthropic | Claude desktop app | TCC evidence only |
| Cursor | Cursor agent/IDE | Detected only |
| Google | Gemini CLI | Detected only |
| Pi | Pi coding agent | Detected only |
| Oh My Pi | OMP coding agent | Detected only and distinct from Pi |
| xAI | Grok Build | Detected only |
| OpenCode | OpenCode | Detected only |
| GitHub | Copilot CLI | Detected only |
| Amazon | Kiro CLI | Detected only |

Detection-only rows state that permission interpretation ships in a later adapter. They do not emit Permission Debt findings from uninterpreted configuration.

## Full-coverage boundary

"Full" means full coverage of documented, persistent, locally readable permission posture for the supported configuration versions and monitored locations. It does not include session-only state or cloud policy.

The Codex adapter covers persisted approval policy, sandbox mode, writable roots, network policy, trusted project state, MCP server/tool approval configuration, profiles that affect those settings, and supported managed requirements.

The Claude Code adapter covers persisted allow/ask/deny rules, default permission mode, bypass restrictions, additional directories, sandbox settings, project trust, MCP declarations and approval configuration, hooks, and supported managed settings.

Adapters must preserve precedence and source layer. They must not merely concatenate rules. When the effective decision cannot be proven, the adapter emits the contributing rules and an unknown effective result.

Command-line flags, environment-only overrides, in-memory approvals, and temporary session decisions are always outside full coverage and are named in the coverage report.

## Bounded hybrid discovery

Agent Access never crawls the entire home directory. Discovery uses only these inputs:

1. Adapter-owned allowlists of documented global, managed, and application configuration locations.
2. Repository or trusted-directory paths explicitly declared by already allowlisted configuration.
3. Developer roots explicitly added in Agent Access preferences.
4. Known application bundle identifiers and installation locations used for surface detection and TCC grouping.

Inside a monitored developer root, the scanner looks only for adapter-allowlisted relative paths and filenames. It does not enumerate or read arbitrary project content.

Discovery standardizes paths, bounds traversal depth and file count, rejects unexpected symlink escapes, and does not follow an include outside documented locations or monitored roots. An explicitly declared absolute configuration path may be read only when its adapter documents that field as a configuration include and the resolved file itself is allowlisted.

Foundation safety ceilings are 32 user-added developer roots, 10,000 visited directory entries per root, 2,000 candidate configuration files per adapter, 1 MiB per configuration file, eight nested configuration includes, 64 decoded container levels, and 16 symlink resolutions for one candidate. An adapter may use a stricter documented limit. Crossing any ceiling degrades only the affected adapter and records the omitted source category.

Removing a monitored root stops future reads immediately. Previously normalized facts age out through ordinary snapshot retention; no raw configuration was retained.

## Architecture

The foundation follows Permission Pulse's package boundaries and scanner pattern.

### PermissionsCore

Owns normalized value types and protocols. The core has no filesystem, AppKit, TOML, JSON, GRDB, or SwiftUI dependency.

Primary concepts:

- `AgentVendor`;
- `AgentSurfaceKind`;
- `AgentSurface`;
- `AgentSupportLevel`;
- `AgentCapability`;
- `AgentDecision`;
- `AgentScope`;
- `AgentEvidenceSource`;
- `AgentPermissionFact`;
- `AgentCoverageReport`;
- `AgentHostEvidence`;
- `AgentAccessScan`;
- `AgentConfigAdapter`;
- `AgentAccessScanning`.

Forward-compatible enums retain unknown raw values instead of collapsing them. Persisted representations follow the existing kind-plus-raw pattern where necessary.

### PermissionsScanners

Owns bounded filesystem discovery, surface detection, Codex and Claude adapters, safe parsing, source precedence, mock adapters, and host-evidence lookup inputs.

`AgentSurfaceDetector` recognizes all ten agent families through allowlisted bundle IDs, executable/install metadata, and configuration presence. It does not execute binaries.

Each `AgentConfigAdapter` receives an immutable discovery context and returns normalized facts plus a coverage report. Adapters do not update shared state or call one another.

`AgentAccessScanner` runs detection and the applicable adapters, merges results by stable surface identity, and returns a typed scanner output. One adapter failure does not erase another adapter's evidence.

`AgentHostCorrelator` is a pure, non-scanning component in `PermissionsScanners`. It combines normalized agent surfaces, existing TCC grants, documented integration metadata, and explicit user associations into `AgentHostEvidence`. It emits a relationship only when one of the evidence conditions in the product truth model is satisfied.

### TOML decoding dependency

Codex configuration uses TOML. The foundation adds `dduan/TOMLDecoder` as the second third-party runtime dependency alongside GRDB.

Constraints:

- use the MIT-licensed Swift-native package;
- add it only to `PermissionsScanners`;
- use decoding only;
- hide it behind an internal `AgentTOMLDecoding` protocol;
- limit input size before decoding;
- pin the resolved dependency version, initially 0.4.5;
- keep normalized models independent of the decoder;
- test malformed, adversarial, deeply nested, and oversized TOML fixtures.

Foundation JSON APIs parse Claude configuration. No YAML dependency is added in this slice.

### PermissionsStore

Owns snapshot schema v6, Agent Access row encoding and decoding, coverage persistence, and drift queries.

### PermissionsUI

Owns vendor-family presentation, Permission Debt derivation, search, inspectors, coverage copy, preferences, export rendering, recent-change rows, accessibility, and view-model state.

Permission Debt is derived from normalized facts by pure rules. It is not an independent stored truth.

### App target

`AgentAccessCoordinator` owns the concrete scanner and publishes live results to `AppViewModel`. The app refresh lifecycle runs the existing system scan and Agent Access scan concurrently, then hands their independently typed availability to `SnapshotCoordinator`.

The app never invokes an agent CLI to obtain effective settings.

## Normalized evidence model

### Agent surface

A stable surface identifies vendor, product, surface kind, and a non-secret installation or configuration-root identity. CLI, desktop app, IDE, and host are separate kinds even when they share a vendor family.

### Permission fact

Every fact contains:

- stable surface identity;
- capability;
- decision;
- scope and matcher;
- source layer;
- standardized safe source path;
- safe rule locator such as a configuration key path;
- adapter-authored plain-language explanation;
- support and scan coverage references.

The stable fact identity contains surface, source, capability, scope, and matcher. Decision and explanation are mutable fields and are excluded from identity so a decision change produces a changed event.

If scope or matcher changes, the foundation reports an honest removal and addition. It does not guess that structurally different rules are one broadened or narrowed rule unless the adapter supplies a provable semantic pairing.

### Coverage report

Each report records expected source categories, inspected source categories, omitted or ambiguous categories, unsupported runtime-only categories, timestamp, support level, and scan availability.

Coverage stores categories and safe paths, never raw file contents or secret-bearing values.

### Host evidence

Host evidence references existing `PermissionGrant` data and records the relationship basis. It does not duplicate TCC truth or claim observed use.

## Permission Debt derivation

The Needs Review inbox is a deterministic projection of current normalized facts. The foundation can surface these reasons when the adapter has sufficient evidence:

- bypass or never-ask modes;
- unrestricted or unusually broad writable roots;
- persistent approval of broad shell-command patterns;
- unrestricted network policy;
- blanket MCP tool approval;
- command-running hooks;
- trust granted to a broad parent directory;
- a trusted or approved path that no longer exists;
- a related desktop surface holding a powerful macOS permission;
- an ambiguous security-relevant rule requiring manual review.

Findings use factual copy, source evidence, and a reason code. They do not use a numeric score, malware language, or vendor reputation.

Changing a finding explanation later changes the current projection without rewriting historical permission facts.

## Snapshot schema v6

Migration v6 adds:

- `agent_access_captured` to `snapshots`, non-null and defaulting to false for pre-v6 history;
- `agent_surfaces`, keyed to a parent snapshot;
- `agent_permission_facts`, keyed to a parent snapshot and surface;
- `agent_coverage`, keyed to a parent snapshot and surface.

Pre-v6 snapshots are not valid Agent Access baselines because the domain was not captured.

The existing TCC, BTM, and LaunchAgent production snapshot remains eligible when those existing domains are complete even if Agent Access is degraded or failed. In that case the snapshot is written with `agent_access_captured == false` and no Agent Access fact rows.

When Agent Access is complete, the same production snapshot stores surfaces, facts, and coverage atomically and marks the domain captured.

The existing once-per-calendar-day guard remains. If Agent Access is incomplete when that day's snapshot is written and recovers later the same day, live evidence updates immediately but historical Agent Access capture resumes on the next eligible day. The foundation does not mutate an already written daily snapshot.

Agent drift queries select only snapshots with `agent_access_captured == true`. A degraded or failed capture can never serve as either side of a diff and therefore cannot create false mass removals.

Snapshot retention cascades through all Agent Access child rows.

## Drift semantics

Agent Access supports added, removed, and changed permission facts.

- New stable identity: added.
- Missing stable identity between two complete captures: removed.
- Same stable identity with a different decision or other mutable posture field: changed.
- Changed source path, scope, or matcher without adapter pairing: removal plus addition.
- Coverage-only change: coverage event, not a permission grant event.
- Detection-only agent installation or removal: surface event with explicit detection-only copy.

Recent Changes, yesterday and seven-day views, unreviewed counts, weekly digest totals, JSON/Markdown export, search, dismissal, and snooze include Agent Access events using the same semantic-key discipline as existing domains.

## User experience

### Navigation

Agent Access appears in the detail-window sidebar when at least one supported or detectable agent surface exists. The Agent Access preferences section remains available when no agent is detected so the user can add a monitored developer root.

### Main page

The page shows:

1. last scan time and overall coverage;
2. a Needs Review list of concrete Permission Debt findings;
3. vendor-family sections;
4. separate rows for every CLI, desktop app, IDE, and host surface;
5. full, partial, or detected-only support plus current scan availability.

OpenAI groups Codex, Codex desktop, and ChatGPT desktop while keeping each surface separate. Anthropic groups Claude Code and Claude desktop while keeping each surface separate. Other vendors follow the same rule.

### Inspector

Selecting a supported fact opens the existing inspector pattern with:

- agent surface;
- plain-language capability;
- decision;
- scope and matcher;
- source layer and safe path;
- coverage and uncertainty;
- host context when evidence exists;
- first-observed or change context when history exists.

Read-only remediation actions may reveal the source file in Finder, open a documented safe deep link, open the relevant System Settings pane, or show manual instructions. Permission Pulse never launches an agent CLI, executes a command, or edits configuration. If a vendor has no safe deep link, the UI does not pretend that it can open the native permission manager.

### Search and export

Search covers vendor, surface, capability, matcher, repository, safe source path, support level, and rendered explanation. Exports contain normalized facts and coverage only. Secret-bearing raw values are never exported.

### Preferences

The Agent Access preferences section shows:

- monitored developer roots;
- add and remove root actions;
- detected agents and support levels;
- exact inspected and omitted source categories;
- the configuration-file privacy exception;
- the runtime and cloud-state limitations.

Root changes apply on the next scan. Removing a root does not delete existing history outside ordinary retention.

## Failure and privacy handling

### Missing and unknown configuration

A missing optional configuration file means documented defaults are in effect and is not an error. A documented required or explicitly referenced file that cannot be read degrades the adapter.

Unknown presentation-only keys do not degrade permission coverage. Unknown security-relevant keys, invalid syntax, unsupported configuration versions, unresolved includes, and ambiguous precedence degrade the relevant adapter.

### Last-known behavior

When a fully supported adapter degrades or fails, the live UI retains last-known facts when available and labels them stale. It shows no successful data when no prior complete scan exists. The failed adapter contributes no facts to a captured snapshot.

Detection-only agents never block a complete Codex or Claude capture.

### Independent host coverage

Missing FDA or TCC schema failure degrades host context without invalidating complete agent-configuration evidence. Agent facts remain visible with host context unavailable.

### Parser safety

All parsers:

- read bytes only from allowlisted resolved paths;
- enforce conservative input-size, nesting, and collection limits;
- decode data without evaluation;
- never expand a secret environment variable into stored output;
- never load extensions, plugins, hooks, or MCP processes;
- never log configuration contents;
- emit user-safe errors without raw values;
- preserve ambiguous security evidence as unknown rather than dropping it.

### Secret handling

Keys, tokens, headers, environment-variable values, OAuth material, and credential-store contents are outside the data model. Fixtures with fake secrets must prove these values do not enter view-model state, SQLite, OSLog messages, dismissal keys, notifications, or exports.

## Performance limits

- Agent Access scans run off the main actor and publish one bounded result.
- Adapters scan independently with a conservative concurrency cap.
- Discovery never performs an unrestricted recursive home-directory walk.
- Each adapter enforces the foundation ceilings for files, bytes, depth, includes, symlink resolution, and monitored-root traversal, and may document stricter limits.
- Exceeding a limit degrades coverage and names the omitted category without exposing content.
- UI grouping, Permission Debt derivation, search, and diff formatting operate on normalized in-memory facts and never reopen configuration files.

## Testing strategy

### PermissionsCore

- Stable identities for surfaces and facts.
- Capability, decision, scope, provenance, unknown-raw-value, support-level, and coverage semantics.
- Deterministic Permission Debt reason mapping inputs.

### PermissionsScanners

- Golden Codex and Claude fixtures for every supported configuration layer and precedence combination.
- Allow, ask, deny, sandbox, network, writable-root, MCP, hook, trust, and managed-policy fixtures.
- Detection fixtures for all ten agent families.
- Missing optional files, malformed files, unsupported versions, unknown security keys, ambiguous precedence, symlink escapes, recursion limits, file-count limits, and oversized inputs.
- TOMLDecoder seam tests and hostile TOML fixtures.
- Fake-secret fixtures that assert normalized output never contains secret values.
- Filesystem-spy tests proving no read occurs outside the requested adapter allowlist and monitored roots.

### PermissionsStore

- Clean v5-to-v6 migration.
- Pre-v6 history remains unchanged and is not treated as captured Agent Access data.
- Surface, fact, and coverage round trips.
- Agent rows contain no raw configuration.
- Diffs skip uncaptured snapshots.
- Parser failures never appear as mass removals.
- Added, removed, changed, coverage, and detection events are deterministic.
- Duplicate identities, retention, export redaction, and date ordering remain correct.

### App and coordination

- System and Agent Access scans run independently.
- Agent failure does not suppress an otherwise valid existing-domain snapshot.
- Same-day recovery updates live state but does not mutate that day's uncaptured history.
- Last-known and first-failure behavior match existing scanner semantics.
- Reset All Data clears Agent Access history, monitored-root preferences, dismissal state, and live view-model state.

### PermissionsUI

- Conditional sidebar visibility.
- Vendor-family grouping with separate surfaces.
- Support and availability labels.
- Needs Review derivation.
- Search across every rendered field.
- Inspector evidence and safe read-only actions.
- Recent Changes, dismissal, snooze, digest, badge count, and export integration.
- Complete, degraded, failed, stale, detected-only, empty, and no-history states.
- VoiceOver labels, keyboard navigation, contrast, and localization-ready strings.

### Manual gates

On a real Mac with current Codex and Claude Code installations:

1. Confirm detected sources and effective persistent facts against each product's own permission UI and documentation.
2. Change one persistent permission and verify the next eligible daily diff.
3. Verify Codex, ChatGPT, Claude, Terminal, and IDE TCC records remain separately attributed.
4. Verify any shown host relationship has a visible evidence basis.
5. Inspect SQLite, logs, notifications, and exports for raw configuration or fake secret leakage.
6. Confirm no configuration file is modified and no agent process is launched.
7. Verify behavior with FDA granted and denied.
8. Run every existing Permission Pulse suite and release gate without regression.

## Acceptance criteria

- A supported Codex installation produces normalized persistent facts with exact safe provenance and a complete coverage report.
- A supported Claude Code installation produces normalized persistent facts with exact safe provenance and a complete coverage report.
- Configuration precedence is reflected in effective decisions or explicitly labeled ambiguous.
- Desktop-app TCC evidence is shown separately from agent rules.
- Detection-only agents are visible without interpreted permission claims.
- A new, removed, or changed supported permission appears in Recent Changes only across two complete Agent Access captures.
- A degraded Agent Access scan cannot create false removals or block valid existing-domain history.
- Permission Debt findings are factual, explainable, and score-free.
- No raw configuration, transcript, prompt, command, credential, token, header, or secret value is persisted, logged, notified, or exported.
- No file outside adapter allowlists and monitored roots is read.
- No agent CLI, hook, plugin, extension, or MCP server is executed.
- All new and existing automated tests pass, and the real-Mac manual gates are recorded before release.

## Follow-on boundaries

Later adapter slices reuse the normalized model and UI. An adapter may graduate from detected-only to partial or full only when its documented persistent permission sources, precedence, fixtures, failure behavior, and privacy-negative tests meet the same gates as Codex and Claude.

Runtime enforcement, command logging, session inspection, cloud administration, and policy editing remain outside the Agent Access program unless a future approved design explicitly changes Permission Pulse's trust model.

## References

- [OpenAI Codex approvals and security](https://learn.chatgpt.com/docs/agent-approvals-security)
- [OpenAI Codex sandboxing](https://learn.chatgpt.com/docs/sandboxing)
- [OpenAI Codex advanced configuration](https://learn.chatgpt.com/docs/config-file/config-advanced)
- [OpenAI Codex MCP configuration](https://learn.chatgpt.com/docs/extend/mcp)
- [Claude Code permissions](https://code.claude.com/docs/en/permissions)
- [Claude Code sandboxing](https://code.claude.com/docs/en/sandboxing)
- [TOMLDecoder](https://github.com/dduan/TOMLDecoder)
