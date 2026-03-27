# Symphony Specification

Status: Draft v4

Purpose: Define Symphony as a Swift-native issue orchestration system made up of
`Symphony Server`, the `Symphony` SwiftUI app, and the repository-local
`SymphonyHarness` developer tool.

## 1. Product Definition

Symphony consists of three required products:

1. `Symphony Server`
   - A standalone Swift 6.2 server process built on Hummingbird and HummingbirdWebSocket.
   - Is implemented by a pure `SymphonyServerCore` library, a host-facing
     `SymphonyServer` library, and a thin `SymphonyServerCLI` executable wrapper.
   - Keeps the human-facing executable product name `symphony-server`.
   - Owns the SQLite-backed runtime state, HTTP query API, WebSocket log stream,
     refresh trigger, and persisted observability data.
   - Owns GitHub issue polling, orchestration state, workspace lifecycle, provider
     integration, dispatch, retries, and reconciliation.

2. `Symphony`
   - A SwiftUI client that supports iOS and macOS by default.
   - Is implemented by the `SymphonySwiftUIApp` target with
     `SymphonySwiftUIAppTests` as its default companion and
     `SymphonySwiftUIAppUITests` as its explicit-only UI test bundle.
   - Keeps the user-facing display name `Symphony`.
   - Connects to a `Symphony Server` by host/domain and port.
   - Provides an observability-first operator UI for issue state, run history,
     agent sessions, and live provider event logs.

3. `SymphonyHarness`
   - A repository-local developer tool consisting of the `harness` executable,
     the `SymphonyHarness` library, and the `SymphonyHarnessCLI` command layer.
   - Owns deterministic build, test, run, validate, artifact, coverage, and
     diagnostics workflows for the Symphony repository.
   - Uses subject-based execution rather than the older `--product server|client`
     model.
   - Remains the canonical source of truth for subject resolution, shared run
     artifacts, local environment validation, and contributor workflows.

Important boundaries:

- The UI is not embedded in the server process.
- Authentication is out of scope for v1. Operators connect directly to a trusted
  server endpoint.
- The default client endpoint is `http://localhost:8080`.
- `SymphonyHarness` is repository-specific developer tooling and is not part of
  the deployed `Symphony Server` or `Symphony` runtime topology.
- The final state provides no backward-compatibility aliases for the old
  implementation identifiers `SymphonyBuild`, `SymphonyBuildCore`,
  `SymphonyBuildCLI`, `SymphonyRuntime`, `SymphonyClientUI`, `Symphony`,
  `SymphonyTests`, `SymphonyUITests`, or `symphony-build`.

## 2. Technology Defaults

This specification targets the following default stack:

- Swift 6.2
- SwiftUI for the client
- Swift Testing for unit, integration, and UI-adjacent logic tests
- one root `Package.swift` for shared, server, and harness targets
- the checked-in `Symphony.xcworkspace` and `SymphonyApps.xcodeproj` as the app
  source of truth
- SQLite as the required durable store for server metadata and event indexing
- Hummingbird as the default server framework
- HummingbirdWebSocket as the default WebSocket transport companion
- HummingbirdTesting and HummingbirdWSTesting as the default server test
  companions
- `just` as the preferred contributor entrypoint over `swift run harness ...`

The specification describes product behavior and contracts. The server requires
Hummingbird-backed HTTP routing and WebSocket handling rather than a custom
transport.

The one-root-package architecture is also an intentional tooling choice. The
root package is the first-class SwiftPM, SourceKit-LSP, and VS Code integration
surface for shared, server, and harness targets, while the Apple app remains an
Xcode-first environment.

`SymphonyHarness`-specific defaults, commands, and filesystem contracts are
defined in Section 20.

## 3. Goals and Non-Goals

### 3.1 Goals

- Serve a Hummingbird-backed server process on the configured host and port.
- Persist server state in SQLite so issues, runs, sessions, workspaces, and logs
  survive restarts.
- Expose HTTP JSON endpoints for health, issue lists, issue detail, run detail,
  log replay, and refresh.
- Expose WebSocket log streaming with backlog replay followed by live tailing.
- Expose a required HTTP/JSON and WebSocket API for the native client.
- Let the SwiftUI client view current work, replay prior logs, and live-tail
  active sessions.
- Preserve raw provider-event fidelity end-to-end.
- Support restart recovery for historical state and observability without
  requiring active session resumption.
- Poll GitHub for active issues, orchestrate dispatch, manage workspaces, and run
  provider agents.
- Reconcile running issues against native GitHub state.
- Standardize repository workflows around `just` on top of `harness`.
- Model package, server, harness, and app work through explicit subject names with
  strict dependency isolation.
- Preserve a future portability path for `SymphonyShared` and
  `SymphonyServerCore`, including alternate hosts such as browser or WASM
  experiments, without making those hosts normative for v1.
- Preserve standard SwiftPM workflows and editor integrations for the root
  package while keeping the Apple app Xcode-first.

### 3.2 Non-Goals

- Authentication, authorization, or multi-tenant access control in v1.
- Replacing GitHub issue orchestration with a generic task runner in v1.
- Embedding orchestration logic in the UI client.
- Requiring a web dashboard in addition to the native client.
- Defining a single mandatory provider sandbox, tool, or approval posture for
  every deployment.
- Resuming interrupted provider sessions after process restart.
- Preserving compatibility aliases for the pre-rearchitecture target names or
  command names.
- Delivering a browser-hosted or WASM-hosted Symphony runtime in v1.
- Requiring non-Xcode editor environments to achieve full parity with Xcode for
  Apple app editing.
- Treating single-root target isolation as a promise of separate package
  resolution universes.

## 4. System Overview

### 4.1 Main Components

Components:

1. `API Layer`
   - Serves the Hummingbird-backed HTTP endpoints and HummingbirdWebSocket log
     stream.
   - Reads from SQLite-backed state and persisted history.

2. `Persistence Layer`
   - Uses SQLite for durable metadata.
   - Persists issue, run, session, workspace, and raw event records used by the
     client.

3. `SymphonySwiftUIApp`
   - Connects to the server.
   - Displays issue lists, run details, session details, and a provider-aware
     raw-event log viewer.

4. `SymphonyHarness`
   - Owns deterministic build, test, run, validate, artifact, coverage, and
     diagnostics workflows for the Symphony repository.
   - Resolves explicit subjects and produces per-subject artifacts under one
     shared run root.

5. `Workflow Loader`
   - Reads and parses repository-owned `WORKFLOW.md`.
   - Produces a typed runtime configuration plus prompt template.

6. `Configuration Layer`
   - Applies defaults and environment indirection.
   - Validates tracker, workspace, agent, provider, server, and persistence
     settings.

7. `Issue Tracker Client`
   - Talks to GitHub GraphQL for Projects v2.
   - Fetches candidate issues, issue state refreshes, and terminal-state issues.

8. `Orchestrator`
   - Owns the poll loop, claim state, retries, reconciliation, and dispatch
     decisions.

9. `Workspace Manager`
   - Maps issue identifiers to deterministic filesystem workspaces.
   - Enforces root containment and hook execution.

10. `Agent Runner`
    - Starts provider-backed agent sessions in the issue workspace.
    - Streams raw provider events back to the server.

### 4.2 Data Flow

1. `Symphony Server` starts the Hummingbird runtime and loads SQLite-backed
   state.
2. `Symphony Server` loads `WORKFLOW.md` and validates config.
3. The orchestrator polls GitHub for active issues.
4. Eligible issues are claimed and dispatched into deterministic workspaces.
5. The configured provider runs in the workspace and emits raw provider events.
6. The server persists those events and updates indexed runtime metadata.
7. The API exposes current state, historical state, and log replay or streaming.
8. `SymphonySwiftUIApp` fetches baseline data over HTTP and uses WebSocket for
   live log tails.
9. `SymphonyHarness` builds, tests, runs, validates, and diagnoses repository
   subjects while keeping artifacts isolated per subject under one shared run
   root.

### 4.3 Deployment Defaults

- The server should bind loopback by default.
- The client should default to `localhost` and port `8080`.
- Remote trusted-network operation is allowed by entering a host/domain and port
  manually.
- Because v1 has no auth, deployments exposed beyond a trusted network are
  non-conformant.

### 4.4 Architectural Boundary Intent

- `SymphonyShared` is the innermost shared contract layer and should prefer
  portable value types, serializable primitives, and host-agnostic logic where
  practical.
- `SymphonyServerCore` is the innermost orchestration and policy layer and
  should own state transitions, retry logic, scheduling policy, and dependency
  protocols without directly owning HTTP transport, SQLite host wiring,
  filesystem mutation, process launch, or app lifecycle behavior.
- `SymphonyServer` owns host-facing integrations such as Hummingbird,
  HummingbirdWebSocket, SQLite adapters, workspace management, provider
  processes, tracker clients, and bootstrap composition.
- `SymphonyServerCLI` and `SymphonyHarnessCLI` are delivery wrappers, not policy
  layers.
- These boundaries are intentionally chosen to preserve future alternate-host
  reuse, including browser or WASM-oriented experiments, without making those
  hosts part of v1 conformance.

## 5. Core Domain Model

### 5.1 Issue

Normalized issue record used by orchestration and the client UI.

Fields:

- `id` (string)
- `identifier` (string)
- `repository` (string)
- `number` (integer)
- `title` (string)
- `description` (string or null)
- `priority` (integer or null)
- `state` (string)
- `issue_state` (string)
- `project_item_id` (string or null)
- `url` (string or null)
- `labels` (list of lowercase strings)
- `blocked_by` (list of blocker refs)
- `created_at` (timestamp or null)
- `updated_at` (timestamp or null)

### 5.2 WorkflowDefinition

Parsed `WORKFLOW.md` payload.

Fields:

- `config` (map)
- `prompt_template` (string)

### 5.3 RunSummary

Top-level run row suitable for issue and run lists.

Fields:

- `run_id` (string)
- `issue_id` (string)
- `issue_identifier` (string)
- `attempt` (integer)
- `status` (string)
- `provider` (string)
- `provider_session_id` (string or null)
- `provider_run_id` (string or null)
- `started_at` (timestamp)
- `ended_at` (timestamp or null)
- `workspace_path` (string)
- `session_id` (string or null)
- `last_error` (string or null)

### 5.4 RunDetail

Detailed run payload for the run detail screen.

Fields:

- all `RunSummary` fields
- `issue` (`Issue`)
- `turn_count` (integer)
- `last_agent_event_type` (string or null)
- `last_agent_message` (string or null)
- `tokens`
  - `input_tokens` (integer)
  - `output_tokens` (integer)
  - `total_tokens` (integer)
- `logs`
  - `event_count` (integer)
  - `latest_sequence` (integer or null)

### 5.5 AgentSession

Session metadata tracked while a provider-backed worker is active and retained after it ends.

Fields:

- `session_id` (string)
- `provider` (string)
- `provider_session_id` (string or null)
- `provider_thread_id` (string or null)
- `provider_turn_id` (string or null)
- `provider_run_id` (string or null)
- `run_id` (string)
- `provider_process_pid` (string or null)
- `status` (string)
- `last_event_type` (string or null)
- `last_event_at` (timestamp or null)
- `turn_count` (integer)
- `token_usage`
  - `input_tokens` (integer)
  - `output_tokens` (integer)
  - `total_tokens` (integer)
- `latest_rate_limit_payload` (string or null)

### 5.6 AgentRawEvent

Canonical persisted and streamed event record.

Fields:

- `session_id` (string)
- `provider` (string)
- `sequence` (integer)
- `timestamp` (timestamp)
- `raw_json` (string)
- `provider_event_type` (string)
- `normalized_event_kind` (string or null)

Notes:

- `raw_json` is the canonical payload.
- `provider_event_type` and `normalized_event_kind` are indexed helpers only.
- The server must not normalize away, rewrite, or lossy-transform the raw body.

### 5.7 EventCursor

Opaque pagination and replay token used by log APIs.

Requirements:

- Encodes at least `session_id` and the last delivered `sequence`.
- Must be stable across reconnects.
- Must let the server return "events after sequence N" semantics.

### 5.8 ServerEndpoint

Client connection target.

Fields:

- `scheme` (string, default `http`)
- `host` (string, default `localhost`)
- `port` (integer, default `8080`)

### 5.9 Stable Identifiers

- `Issue ID`
  - Internal tracker-stable ID.
- `Issue Identifier`
  - Human-readable `owner/repo#number`.
- `Workspace Key`
  - Sanitized issue identifier using `[A-Za-z0-9._-]`, with all other characters replaced by `_`.
- `Run ID`
  - Server-generated unique identifier for one worker attempt.
- `Session ID`
  - Symphony-generated stable identifier for one provider-backed session.
- `Provider Session ID`
  - Provider-defined primary session identifier when available.
- `Provider Thread ID`
  - Optional provider-defined thread identifier.
- `Provider Turn ID`
  - Optional provider-defined turn identifier.
- `Provider Run ID`
  - Optional provider-defined run identifier.
- `Event Sequence`
  - Server-assigned, strictly increasing per-session sequence number.

## 6. Workflow and Configuration

### 6.1 File Discovery

Workflow path precedence:

1. Explicit runtime setting or CLI argument.
2. `WORKFLOW.md` in the current working directory.

Errors:

- unreadable file -> `missing_workflow_file`
- invalid YAML -> `workflow_parse_error`
- front matter not mapping -> `workflow_front_matter_not_a_map`

### 6.2 File Format

`WORKFLOW.md` is Markdown with optional YAML front matter.

Parsing rules:

- If the file begins with `---`, parse until the next `---` as YAML front matter.
- The remaining Markdown becomes the prompt template.
- Front matter must decode to an object/map.
- Prompt body is trimmed.

### 6.3 Front Matter Schema

Top-level keys:

- `tracker`
- `polling`
- `workspace`
- `hooks`
- `agent`
- `providers`
- `server`
- `storage`

Unknown keys should be ignored for forward compatibility.

#### 6.3.1 `tracker`

Fields:

- `kind` (required string, currently `github`)
- `endpoint` (default `https://api.github.com/graphql`)
- `api_key` (literal or `$VAR_NAME`, canonical env `GITHUB_TOKEN`)
- `project_owner` (required for GitHub)
- `project_owner_type` (required: `user` or `organization`)
- `project_number` (required integer or string integer)
- `repository_allowlist` (optional list of `owner/repo`)
- `status_field_name` (default `Status`)
- `active_states` (default `["Todo", "In Progress"]`)
- `terminal_states` (default `["Done"]`)
- `blocked_states` (default `["Todo"]`)

#### 6.3.2 `polling`

Fields:

- `interval_ms` (default `30000`)

#### 6.3.3 `workspace`

Fields:

- `root` (default `<system-temp>/symphony_workspaces`)

#### 6.3.4 `hooks`

Fields:

- `after_create` (optional multiline shell script)
- `before_run` (optional multiline shell script)
- `after_run` (optional multiline shell script)
- `before_remove` (optional multiline shell script)
- `timeout_ms` (default `60000`)

#### 6.3.5 `agent`

Fields:

- `default_provider` (default `codex`)
- `max_concurrent_agents` (default `10`)
- `max_turns` (default `20`)
- `max_retry_backoff_ms` (default `300000`)
- `max_concurrent_agents_by_state` (default empty map)

#### 6.3.6 `providers`

Provider blocks are keyed by provider name. Supported provider keys for v1:

- `codex`
- `claude_code`
- `copilot_cli`

Unknown provider blocks should be ignored for forward compatibility.

##### 6.3.6.1 `providers.codex`

Fields:

- `command` (default `codex app-server`)
- `approval_policy` (implementation-defined Codex value)
- `thread_sandbox` (implementation-defined Codex value)
- `turn_sandbox_policy` (implementation-defined Codex value)
- `turn_timeout_ms` (default `3600000`)
- `read_timeout_ms` (default `5000`)
- `stall_timeout_ms` (default `300000`)

##### 6.3.6.2 `providers.claude_code`

Fields:

- `command` (default `claude`)
- `permission_mode` (implementation-defined Claude Code CLI value)
- `allowed_tools` (optional list of strings)
- `disallowed_tools` (optional list of strings)
- `turn_timeout_ms` (default `3600000`)
- `read_timeout_ms` (default `5000`)
- `stall_timeout_ms` (default `300000`)

##### 6.3.6.3 `providers.copilot_cli`

Fields:

- `command` (default `copilot --acp --stdio`)
- `turn_timeout_ms` (default `3600000`)
- `read_timeout_ms` (default `5000`)
- `stall_timeout_ms` (default `300000`)

#### 6.3.7 `server`

Fields:

- `host` (default `127.0.0.1`)
- `port` (default `8080`)

Requirements:

- `0` may be used only for development or tests that intentionally request an ephemeral port.
- Changing listener settings may require restart.

#### 6.3.8 `storage`

Fields:

- `sqlite_path` (default `<application-support>/symphony/symphony.sqlite3`)
- `retain_raw_events` (required behavior, default `true`)

### 6.4 Resolution Semantics

- Path values support `~` expansion.
- `$VAR_NAME` indirection is supported for secret and path-like values.
- URI values must not be path-expanded.
- Invalid reloads must not crash the process; the server keeps the last known good config.

### 6.5 Prompt Template Contract

The Markdown body of `WORKFLOW.md` is the per-issue prompt template.

Rendering rules:

- Use strict template rendering.
- Unknown variables must fail rendering.
- Unknown filters must fail rendering.

Template inputs:

- `issue`
- `attempt`

Fallback behavior:

- Empty prompt bodies may use a minimal default prompt.
- Parse errors and template errors are never silently ignored.

### 6.6 Dynamic Reload

`Symphony Server` should watch `WORKFLOW.md` and hot-reload future behavior when possible.

Reload applies to:

- polling cadence
- issue-state policy
- workspace hooks
- default provider selection
- concurrency settings
- provider launch settings
- future prompt renders

Reload does not require:

- restarting in-flight provider sessions
- hot-rebinding server ports
- mutating historical persisted records

## 7. GitHub Orchestration Contract

### 7.1 Required Operations

The tracker adapter must provide:

1. `fetch_candidate_issues()`
2. `fetch_issues_by_states(state_names)`
3. `fetch_issue_states_by_ids(issue_ids)`

### 7.2 Candidate Eligibility

An issue is dispatch-eligible only if all are true:

- It is backed by a GitHub Issue in the configured Project v2.
- Pull requests and draft issues are excluded.
- Native issue state is `OPEN`.
- Project status is in `active_states`.
- Project status is not terminal.
- It is not already running or claimed.
- Blocker rules pass.
- Global and per-state concurrency slots are available.

Sorting order:

1. `priority` ascending, with `null` last
2. `created_at` oldest first
3. `identifier` lexicographic

### 7.3 Blocker Semantics

- If any blocker is open and in `blocked_states`, the issue is blocked.
- If a blocker is open but not represented in the configured project, treat it as blocked.
- Closed blockers never block dispatch.

### 7.4 Reconciliation

Reconciliation runs every tick.

Rules:

- Closed native issues are terminal overrides.
- Terminal project states stop the run and trigger workspace cleanup.
- Non-active, non-terminal states stop the run without workspace cleanup.
- Active states refresh the in-memory issue snapshot.

### 7.5 Startup Cleanup

On startup, the server should fetch terminal issues and remove their workspaces before entering the
steady-state loop.

## 8. Orchestrator State Machine

### 8.1 Runtime Authority

`Symphony Server` is the only component allowed to mutate orchestration state.

The client is an observer and command initiator only. It does not own scheduling state.

### 8.2 Internal Claim States

- `Unclaimed`
- `Claimed`
- `Running`
- `RetryQueued`
- `Released`

### 8.3 Run Lifecycle States

- `PreparingWorkspace`
- `BuildingPrompt`
- `LaunchingAgentProcess`
- `InitializingSession`
- `StreamingTurn`
- `Finishing`
- `Succeeded`
- `Failed`
- `TimedOut`
- `Stalled`
- `CanceledByReconciliation`

### 8.4 Tick Sequence

Each tick performs:

1. Reconcile running issues.
2. Validate config for dispatch.
3. Fetch candidates.
4. Sort candidates.
5. Dispatch until slots are exhausted.
6. Publish state updates to observability consumers.

### 8.5 Retry and Backoff

- Normal continuation retry after clean worker exit: `1000 ms`
- Failure retry: `min(10000 * 2^(attempt - 1), agent.max_retry_backoff_ms)`

Retry queue records:

- `issue_id`
- `issue_identifier`
- `attempt`
- `due_at`
- `error`

### 8.6 Stall Detection

- Stall timeout uses the active provider's `stall_timeout_ms`.
- When `<= 0`, stall detection is disabled.
- Stalled sessions are terminated and retried.

## 9. Workspace Management

### 9.1 Layout

Per-issue workspace:

- `<workspace.root>/<workspace_key>`

Rules:

- Workspaces are reused across runs.
- Successful runs do not delete workspaces automatically.

### 9.2 Safety Invariants

- The configured provider command must run with `cwd == workspace_path`.
- `workspace_path` must remain within the configured workspace root.
- Workspace keys must be sanitized.

### 9.3 Hooks

Supported hooks:

- `after_create`
- `before_run`
- `after_run`
- `before_remove`

Execution contract:

- Run in the workspace directory.
- Enforce `hooks.timeout_ms`.
- Log start, timeout, and failure.

Failure semantics:

- `after_create` failure aborts workspace creation.
- `before_run` failure aborts the run attempt.
- `after_run` failure is logged and ignored.
- `before_remove` failure is logged and ignored.

## 10. Agent Provider Contracts

### 10.1 Core Launch Contract

The server launches the configured provider using:

- provider: `agent.default_provider` unless a future workflow override is defined
- command: `providers.<provider>.command`
- invocation: `bash -lc <providers.<provider>.command>`
- working directory: absolute workspace path

Provider transports may differ internally, but the Symphony adapter must treat stderr as
diagnostics only and must never parse stderr as protocol data.

### 10.2 Core Session Contract

The provider adapter inside `Symphony Server` must:

1. start a provider-backed session for the run
2. submit the rendered workflow prompt for the first turn
3. submit continuation guidance for later turns
4. assign a stable Symphony `session_id`
5. persist raw provider events in receive order
6. detect terminal completion, failure, cancellation, timeout, or subprocess exit

If a provider supports native continuation or resume semantics, the adapter should use them.
Otherwise, the adapter may emulate continuation while preserving Symphony's run/session model.

### 10.3 Provider Capability Model

Each provider adapter must document or expose these capability flags:

- `supports_resume`
  - provider can resume a prior provider-backed session
- `supports_interrupt`
  - provider can cancel or interrupt in-flight work without killing the whole process
- `supports_usage_totals`
  - provider exposes absolute token or usage totals
- `supports_rate_limits`
  - provider exposes rate-limit metadata suitable for persistence
- `supports_explicit_approvals`
  - provider exposes approval or permission events in a structured way
- `supports_structured_tool_events`
  - provider emits machine-readable tool call and tool result events
- `tool_execution_mode`
  - one of `provider_managed`, `orchestrator_managed`, or `mixed`

`tool_execution_mode` semantics:

- `provider_managed`
  - the provider executes tools internally and Symphony observes results
- `orchestrator_managed`
  - Symphony executes provider-requested tools and returns outputs
- `mixed`
  - some tools or approvals are provider-managed and others require external participation

### 10.4 Session Metadata Extraction

The server must extract and track:

- `session_id`
- `provider`
- `provider_session_id` when available
- `provider_thread_id` when available
- `provider_turn_id` when available
- `provider_run_id` when available
- token usage totals when available
- latest rate-limit payload when available

Missing provider metadata is represented as `null` or omission where the API already models the
field as optional.

### 10.5 Tool Calls, Approvals, and Input

Approval, sandbox, tool, and user-input handling are provider-specific, but must be documented.

Required behavior:

- Symphony must not stall indefinitely on provider approval or user-input flows.
- If a provider emits structured tool events, Symphony must persist them and expose them to the UI.
- If a provider manages tools internally, Symphony observes and records tool activity but does not
  claim to execute those tools itself.
- If a provider requires external tool execution in the future, unsupported tools must fail
  deterministically without deadlocking the session.
- A deployment must either resolve, expose, or fail user-input-required flows.

### 10.6 Capability Degradation Rules

- Providers that do not expose absolute usage totals may leave usage fields null.
- Providers that do not expose rate-limit data may omit it entirely.
- Providers that do not expose structured approvals must still avoid indefinite hangs.
- Providers that do not support resume are still conformant because restart-time session resumption
  is not required in v1.

### 10.7 Codex Adapter

Normative target:

- `codex app-server` over stdio

Required adapter behavior:

- speak the Codex app-server protocol and issue:
  1. `initialize`
  2. `initialized`
  3. `thread/start`
  4. `turn/start`
- treat `turn/completed`, `turn/failed`, `turn/cancelled`, timeout, or subprocess exit as
  terminal
- treat Codex `thread_id` and `turn_id` as provider-specific identifiers
- persist raw Codex app-server notifications and rollout events as provider events

Codex-specific notes:

- the wire protocol is JSON-RPC-like but not strict JSON-RPC 2.0
- Codex may require deployment-defined approval, sandbox, or tool participation
- `tool_execution_mode` is `mixed`

### 10.8 Claude Code CLI Adapter

Normative target:

- Claude Code CLI non-interactive print mode using structured JSON streaming

Required adapter behavior:

- launch Claude Code CLI in a machine-readable mode such as `-p --output-format stream-json`
- use the first rendered workflow prompt as the initial request
- use provider-native continuation via `--continue`, `--resume`, `--session-id`, or equivalent
  documented session controls when available
- treat CLI stream JSON records as raw provider events
- treat built-in Claude Code tools as provider-managed tool execution

Claude-specific notes:

- raw provider events are the CLI's stream-json event records
- `tool_execution_mode` is `provider_managed`
- `tmux` is not part of the normative contract; if used at all, it is only an implementation-level
  supervision mechanism for a local CLI wrapper

### 10.9 Copilot CLI Adapter

Normative target:

- Copilot CLI ACP over stdio

Required adapter behavior:

- initialize the ACP session and start a Copilot session using the provider's documented ACP flow
- submit prompts through ACP session methods and treat ACP session updates as raw provider events
- support terminal detection from ACP completion, cancellation, timeout, or subprocess exit
- persist ACP updates without lossy normalization

Copilot-specific notes:

- raw provider events are ACP notifications and updates
- `tool_execution_mode` is `provider_managed` unless a future ACP integration externalizes tool
  execution

## 11. Persistence and Restart Recovery

### 11.1 Storage Requirement

SQLite is required for v1.

The SQLite database is the durable source of truth for historical metadata and indexed event access.
The server uses this store for runtime state exposed over HTTP and WebSocket, orchestration
metadata, and provider recovery state.

### 11.2 Required Durable Records

The persistence layer must store enough information to reconstruct:

- issues seen by the server
- run attempts
- provider-backed agent sessions
- workspace paths associated with runs
- retry/error history
- indexed event metadata
- append-only raw provider events

Logical tables:

1. `issues`
   - latest normalized issue snapshot per `issue_id`
2. `runs`
   - one row per worker attempt
3. `agent_sessions`
   - one row per provider-backed session
4. `workspaces`
   - issue-to-workspace mapping and lifecycle timestamps
5. `agent_events`
   - one row per persisted raw event with `session_id`, `sequence`, and `raw_json`

Exact SQL names may differ if the schema preserves the same behavior.

### 11.3 Event Persistence Contract

- Raw provider events are append-only.
- Every persisted event must have a server-assigned per-session sequence.
- The raw JSON body must be stored losslessly.
- The server may additionally index event timestamp, provider, provider event type, and normalized
  event kind.
- The server may maintain a JSONL export view, but SQLite remains required.

### 11.4 Restart Recovery

After server restart:

- Historical issues, runs, sessions, and logs must remain queryable.
- Log replay must continue to work using persisted sequences and cursors.
- In-flight retry timers do not need to survive restart.
- In-flight provider sessions do not need to resume.
- The orchestrator should recover by:
  - loading persisted historical metadata,
  - re-running startup workspace cleanup,
  - polling GitHub for current active issues,
  - dispatching new eligible work.

### 11.5 Recovery Guarantees

Conformant behavior guarantees:

- no historical event loss after a clean shutdown,
- historical log availability after restart,
- stable event ordering for replay,
- no claim that partially executed provider work was resumed if it was not.

## 12. Shared Raw Provider Event Contract

### 12.1 Canonical Format

The canonical stored and streamed observability format is the raw provider event.

The server may attach transport metadata such as `session_id`, `provider`, and `sequence`, but the
event body is the raw provider payload.

### 12.2 Required Normalized Event Kinds

The UI must correctly render at least these normalized event kinds:

- `message`
- `tool_call`
- `tool_result`
- `status`
- `usage`
- `approval_request`
- `error`
- `unknown`

Rendering expectations:

- provider, role, and message content should remain distinguishable
- tool calls must show tool name and arguments when available
- tool outputs must show output text with truncation policy defined by the client
- usage events should be shown as metadata, not normal chat content
- approval requests should be rendered distinctly from normal messages
- terminal status should be rendered as session summary state

### 12.3 Unknown Event Handling

- Unknown provider event types must not crash the server or UI.
- The UI must provide a raw JSON fallback presentation for unknown records.
- The server must still persist and stream those unknown events.

### 12.4 Ordering

- Event order is defined by server-assigned `sequence`.
- API consumers must not infer order from socket receive time or client clock.
- Historical replay and live tail must use the same ordering model.

## 13. Required Network API

### 13.1 Transport

`Symphony Server` must expose:

- HTTP/JSON for queries and commands
- WebSocket for live log streaming
- Hummingbird routes for the HTTP surface
- HummingbirdWebSocket for the WebSocket surface

Required defaults:

- host: `127.0.0.1`
- port: `8080`
- base URL: `http://localhost:8080`

Authentication:

- none in v1
- trusted-network only

### 13.2 Error Envelope

Errors should use:

```json
{
  "error": {
    "code": "string_code",
    "message": "human readable message"
  }
}
```

### 13.3 Health Endpoint

`GET /api/v1/health`

Purpose:

- basic liveness and configuration-readiness check

Response:

```json
{
  "status": "ok",
  "server_time": "2026-03-24T12:00:00Z",
  "version": "1.0.0",
  "tracker_kind": "github"
}
```

### 13.4 Issues List

`GET /api/v1/issues`

Returns:

- current normalized issue summaries known to the server
- enough data for issue list and dashboard views

Suggested response:

```json
{
  "items": [
    {
      "issue_id": "I_123",
      "identifier": "atjsh/example#42",
      "title": "Implement feature",
      "state": "In Progress",
      "issue_state": "OPEN",
      "priority": 1,
      "current_provider": "codex",
      "current_run_id": "run_001",
      "current_session_id": "sess_001"
    }
  ]
}
```

### 13.5 Issue Detail

`GET /api/v1/issues/{id}`

Returns:

- `IssueDetail`
- latest run summary if present
- workspace path
- recent agent sessions

### 13.6 Run Detail

`GET /api/v1/runs/{id}`

Returns:

- `RunDetail`
- associated issue snapshot
- agent session summary
- aggregate token usage
- latest log counters

### 13.7 Historical Logs

`GET /api/v1/logs/{session_id}?cursor=...&limit=...`

Requirements:

- returns ordered raw events for one session
- supports cursor-based pagination
- supports first-page fetch when `cursor` is omitted
- `limit` must be bounded by the server

Suggested response:

```json
{
  "session_id": "sess_001",
  "provider": "codex",
  "items": [
    {
      "sequence": 1,
      "timestamp": "2026-03-24T12:00:01Z",
      "provider": "codex",
      "provider_event_type": "session_meta",
      "normalized_event_kind": "status",
      "raw_json": "{\"timestamp\":\"2026-03-24T12:00:01Z\",\"type\":\"session_meta\",\"payload\":{}}"
    }
  ],
  "next_cursor": "opaque_cursor",
  "has_more": false
}
```

Replay semantics:

- results contain events strictly after the cursor's last delivered sequence
- `next_cursor` represents the last event included in the response
- event order always matches persisted `sequence`

### 13.8 Refresh Trigger

`POST /api/v1/refresh`

Purpose:

- trigger an immediate best-effort poll and reconciliation cycle

Suggested response:

```json
{
  "queued": true,
  "requested_at": "2026-03-24T12:00:00Z"
}
```

### 13.9 WebSocket Log Stream

`WS /api/v1/logs/stream?session_id=...&cursor=...`

Behavior:

- If `cursor` is provided, the server first sends backlog events after that cursor.
- Once backlog is exhausted, the stream transitions into live tail mode.
- Each event frame carries:
  - `session_id`
  - `provider`
  - `sequence`
  - `timestamp`
  - `provider_event_type`
  - `normalized_event_kind`
  - `raw_json`

Client expectations:

- duplicate suppression should use `sequence`
- reconnect should re-use the last received cursor
- if the session is already complete, the socket may send backlog then close gracefully

### 13.10 API Type Contracts

The required API surface must expose or imply these types:

- `ServerEndpoint`
- `IssueSummary`
- `IssueDetail`
- `RunSummary`
- `RunDetail`
- `AgentSession`
- `AgentRawEvent`
- `EventCursor`

## 14. Symphony Native Client

### 14.1 Platform Scope

The `Symphony` client must support:

- iOS
- macOS

The client should share SwiftUI presentation and data-flow logic where practical, while allowing
platform-native navigation and windowing differences.

Implementation-facing identities:

- app target and scheme: `SymphonySwiftUIApp`
- default app test bundle: `SymphonySwiftUIAppTests`
- explicit-only UI test bundle: `SymphonySwiftUIAppUITests`
- display name: `Symphony`

### 14.2 Connection Flow

The client must provide a connection screen with:

- host/domain input
- port input
- localhost default values
- connect/reconnect action
- basic server health feedback

Default values:

- host: `localhost`
- port: `8080`

### 14.3 Required Screens

1. Connection view
2. Issue list view
3. Issue detail view
4. Run/session detail view
5. Live log viewer

### 14.4 Required Client Capabilities

- browse current issues and runs
- inspect persisted run metadata
- replay historical logs from HTTP
- live-tail logs from WebSocket
- show provider badge on runs and sessions
- correctly render the normalized event kinds defined in Section 12
- show raw JSON fallback for unknown provider event types
- trigger manual refresh via `POST /api/v1/refresh`

### 14.5 Out of Scope for v1

- workflow editing
- server configuration editing
- auth/account management
- multi-user collaboration features
- embedded server hosting on iPhone or iPad

## 15. Logging and Observability

### 15.1 Structured Server Logging

The server must emit structured logs with enough context to debug orchestration and API behavior.

Recommended fields:

- `issue_id`
- `issue_identifier`
- `run_id`
- `session_id`
- `provider`
- `provider_session_id`
- `event`
- `error`

### 15.2 Runtime Snapshot

The server should be able to derive:

- active runs
- retry queue
- aggregate token usage
- latest provider rate-limit snapshot when available

This may be served through the required APIs rather than a separate dashboard-only surface.

### 15.3 Token Accounting

- Prefer absolute totals when available from provider events.
- Track deltas carefully to avoid double-counting.
- Preserve latest seen rate-limit payload separately from aggregate token totals when the provider
  exposes it.

## 16. Failure Model and Security

### 16.1 Failure Classes

1. workflow/config failures
2. tracker failures
3. workspace failures
4. provider startup/session failures
5. persistence failures
6. API/streaming failures

### 16.2 Recovery Rules

- Config validation failure blocks dispatch but should not crash a healthy already-running process.
- Tracker fetch failure skips dispatch for that tick.
- Reconciliation refresh failure keeps running workers alive.
- Persistence failure for raw events is critical because it breaks durability guarantees.
- WebSocket delivery failure must not corrupt the persisted event log.

### 16.3 Security Posture

Baseline requirements:

- workspace root containment
- secret redaction in logs
- trusted-network-only deployment
- explicit documentation of provider approval, tool, and sandbox posture

Because no auth exists in v1:

- default loopback binding is required
- non-loopback exposure must be treated as an operator override for trusted environments only

## 17. Swift Testing Matrix

This section defines the minimum validation matrix for conformant implementations.

### 17.1 Workflow and Config

- `WORKFLOW.md` load success and failure paths
- YAML front matter parsing
- non-map front matter rejection
- defaults for tracker, polling, workspace, agent, providers, server, and storage
- `$VAR` resolution
- `~` path expansion
- strict prompt render behavior

### 17.2 GitHub Orchestration

- candidate fetch and normalization
- repository allowlist behavior
- active/terminal/blocked state handling
- blocker logic
- reconciliation updates
- continuation retry and failure backoff

### 17.3 Workspace and Provider Launch

- deterministic workspace paths
- root containment enforcement
- hook execution and timeout behavior
- provider launch with workspace `cwd`
- provider session startup and continuation behavior
- per-provider capability downgrade handling
- timeout and malformed-event handling

### 17.4 SQLite Durability

- schema creation and migration bootstrap
- persisted issue/run/session writes
- append-only raw provider event persistence
- event sequence monotonicity
- restart recovery of historical state

### 17.5 API Contracts

- health serialization
- issue/run detail serialization
- log pagination
- cursor encoding and decoding
- historical replay ordering
- provider field exposure on run/session/event payloads
- refresh trigger semantics

### 17.6 WebSocket Streaming

- backlog-from-cursor delivery
- transition from backlog to live tail
- sequence ordering under live updates
- reconnect using last cursor

### 17.7 Symphony Client Rendering

- localhost default connection values
- manual remote host/domain entry
- issue list loading
- run detail loading
- provider badge rendering
- correct rendering of:
  - `message`
  - `tool_call`
  - `tool_result`
  - `status`
  - `usage`
  - `approval_request`
  - `error`
  - `unknown`
- unknown event raw JSON fallback

### 17.8 Acceptance Scenarios

- server restart preserves logs and run history
- client reconnect replays missed events from a cursor
- provider-managed tool activity is persisted and rendered when structured events are available
- unknown raw provider event types do not break persistence or rendering
- trusted localhost connection works without extra setup
- remote trusted-network connection works when host/domain and port are entered manually

### 17.9 SymphonyHarness

- command rename from `symphony-build` to `harness`
- `build` accepts only canonical production subjects and rejects explicit test
  subjects
- subject parsing for the canonical final names
- production-subject to default-test-companion mapping
- explicit test-subject execution
- multiple positional subjects in one invocation
- no-argument default-set expansion for `test` and `validate`
- no subject hierarchy between `SymphonyServer` and `SymphonyServerCLI`
- scheduler serialization for simulator-exclusive or UI-exclusive subjects
- root-package target isolation:
  - server-only packages are referenced only by server targets
  - `ArgumentParser` is referenced only by `SymphonyHarnessCLI`
  - `SymphonyHarness` does not depend on server-only packages
- one-root-manifest enforcement and removal of the shell-package pattern
- removal of XcodeGen as a normative source of truth
- migration checks for `just validate`, its delegation to
  `swift run harness validate`, and the final pre-commit behavior
- `doctor` reporting for missing `just` and missing Xcode clearly and
  deterministically
- `100%` first-party source coverage enforcement under the renamed targets and
  paths
- app scheme, bundle, and signing cleanup checks for `SymphonySwiftUIApp`

## 18. Definition of Done

Symphony is conformant when all of the following are true:

- `Symphony Server` is implemented in Swift 6.2 using Hummingbird and
  HummingbirdWebSocket.
- `Symphony` is implemented in SwiftUI for iOS and macOS through the
  `SymphonySwiftUIApp` target family.
- `SymphonyHarness` is implemented as the repository-local developer tool with
  the command, subject, artifact, coverage, and diagnostics contracts defined in
  Section 20.
- The repository has exactly one root `Package.swift`.
- There is no additional `Package.swift` anywhere else in the repository.
- There is no `project.yml` or XcodeGen-driven build-definition source of truth.
- The checked-in `Symphony.xcworkspace` and `SymphonyApps.xcodeproj` remain the
  app source of truth, while the root package remains the source of truth for
  shared, server, and harness targets.
- The final-state pre-commit hook runs `just validate`.
- SQLite persists issue, run, session, workspace, and raw event metadata.
- The server exposes HTTP JSON endpoints and WebSocket log streaming required by
  Section 13.
- Raw provider events survive restart and are replayable by cursor.
- The client defaults to `localhost:8080` and allows manual host/domain entry.
- The client can render the required normalized event kinds and unknown-event
  raw fallback.
- The orchestrator polls GitHub, dispatches to workspaces, runs providers, and
  reconciles.
- The final target names and command names are used without compatibility aliases.
- Generated summaries, diagnostics, artifacts, and contributor guidance use only
  the final names and do not surface legacy identifiers outside explicit
  migration-only assertions.
- The Swift Testing matrix in Section 17 is satisfied.

## 19. Implementation Notes

- Historical durability matters more than in-memory elegance. If a value affects
  history or log replay, it should be persisted.
- The server may maintain additional indexes or caches, but the raw event body
  remains canonical.
- The client should prefer a thin rendering layer over server-owned behavior
  rather than duplicating orchestration rules locally.
- Hummingbird is the normative server framework, and custom HTTP parsing is not a
  target architecture.
- `SymphonyServerCore` should stay free of HTTP transport wiring, SQLite host
  wiring, and app concerns whenever possible.
- `SymphonyShared` should prefer portable Swift value semantics over host-bound
  convenience APIs when practical; filesystem, process, transport, and
  persistence helpers belong in outer layers.
- `SymphonyHarness` should stay free of server-only package dependencies.
- Future alternate-host experiments, including browser or WASM-oriented
  orchestration or replay surfaces, should build on `SymphonyShared` and
  `SymphonyServerCore`, not on `SymphonyServer` host integrations.
- `tmux` may be used as a local supervision technique for a CLI wrapper, but it
  is not part of the normative provider contract.

## 20. SymphonyHarness

`SymphonyHarness` defines the repository-local build, test, run, validate, and
diagnostics workflow for Symphony development. It is developer tooling, not part
of the deployed server or client runtime.

### 20.1 Product Definition

SymphonyHarness consists of three required products:

1. `harness`
   - The operator-facing executable.
   - Exposes the canonical subject-based command surface for the repository.

2. `SymphonyHarness`
   - A Swift library that owns subject resolution, dependency isolation checks,
     shared run planning, artifact writing, coverage policy, and environment
     validation.

3. `SymphonyHarnessCLI`
   - A thin command layer that parses CLI arguments and delegates to
     `SymphonyHarness`.
   - Is the only harness target allowed to depend on `ArgumentParser`.

Important boundaries:

- `SymphonyHarness` is repository-specific.
- It does not own GitHub issue orchestration, persisted server state, or network
  API behavior.
- Its public interface is subject-based, not product-based.
- `just` is the preferred human-facing wrapper over `swift run harness ...`.

### 20.2 Architectural Goals and Non-Goals

#### 20.2.1 Goals

- Model the repository as one root Swift package with narrowly scoped targets.
- Keep the app outside SwiftPM target ownership while allowing the Xcode project
  to depend on root package products.
- Preserve standard SwiftPM, SourceKit-LSP, and VS Code compatibility for the
  root package so contributors can still reason about package targets with
  normal Swift tooling beneath the higher-level `just` and `harness` workflows.
- Provide deterministic build, test, run, validate, and doctor workflows through
  explicit subject names.
- Run multiple subjects in parallel by default while auto-serializing
  simulator-exclusive and UI-exclusive work.
- Produce one shared run root with separate summaries, logs, and coverage outputs
  per subject.
- Support capability-aware execution on hosts without Xcode.
- Make `just` the standard contributor workflow layer.

#### 20.2.2 Non-Goals

- Preserving the shell-package pattern under `Tools/`.
- Preserving `project.yml` or XcodeGen as the app source of truth.
- Preserving the `symphony-build` command surface.
- Replacing the checked-in Xcode project or workspace with SwiftPM ownership of
  the app target.
- Generic CI orchestration for arbitrary repositories.
- Mandatory compatibility aliases for old target, product, or command names.

### 20.3 Repository Structure and Dependency Boundaries

#### 20.3.1 Canonical Layout

The final repository layout is:

- `Package.swift`
- `Sources/SymphonyShared`
- `Sources/SymphonyServerCore`
- `Sources/SymphonyServer`
- `Sources/SymphonyServerCLI`
- `Sources/SymphonyHarness`
- `Sources/SymphonyHarnessCLI`
- `Tests/SymphonySharedTests`
- `Tests/SymphonyServerCoreTests`
- `Tests/SymphonyServerTests`
- `Tests/SymphonyServerCLITests`
- `Tests/SymphonyHarnessTests`
- `Tests/SymphonyHarnessCLITests`
- `Applications/SymphonySwiftUIApp`
- `Applications/SymphonySwiftUIAppTests`
- `Applications/SymphonySwiftUIAppUITests`

Repository rules:

- There is exactly one root `Package.swift`.
- No additional `Package.swift` exists anywhere else in the repository.
- `Tools/SymphonyBuildPackage/Package.swift` does not exist in the final state.
- `project.yml` does not exist in the final state.
- `Sources/SymphonyClientUI` does not exist in the final state.
- `Tests/SymphonyClientUITests` does not exist in the final state.
- `Symphony.xcworkspace` and `SymphonyApps.xcodeproj` filenames remain stable.
- The app target, scheme, and test bundle names inside the Xcode project become:
  - `SymphonySwiftUIApp`
  - `SymphonySwiftUIAppTests`
  - `SymphonySwiftUIAppUITests`
- The app display name remains `Symphony`.

#### 20.3.2 Target Isolation Rules

- `SymphonyShared` is the shared contract and value-type layer.
- `SymphonyServerCore` contains pure orchestration, policy, and state logic.
- `SymphonyServer` contains HTTP, WebSocket, SQLite host wiring, workspace
  wiring, provider wiring, tracker wiring, and bootstrap host logic.
- `SymphonyServerCLI` is a thin executable wrapper around `SymphonyServer`.
- The human-facing server executable product is `symphony-server`.
- `SymphonyHarness` may depend on `SymphonyShared` and internal harness helpers,
  but never on server-only packages.
- Only server targets may depend on Hummingbird, HummingbirdWebSocket, or Yams.
- Only `SymphonyHarnessCLI` may depend on `ArgumentParser`.
- Former `SymphonyClientUI` production code belongs under
  `Applications/SymphonySwiftUIApp`, and its test coverage belongs under
  `Applications/SymphonySwiftUIAppTests`.
- `SymphonyRuntime` is removed as a public target. Pure orchestration, policy,
  and state logic belongs in `SymphonyServerCore`; host/runtime integrations
  belong in `SymphonyServer`.
- Target isolation is a dependency-boundary contract within one root package,
  not a requirement for separate package manifests or separate dependency
  resolution universes.
- External package declarations may appear once at the root manifest even when
  only one target family consumes them; conformance is determined by target
  dependency edges, not by per-subsystem `Package.resolved` files.
- Conformance includes source-level import hygiene as well as manifest
  dependency hygiene. Non-server targets must not import server-only modules or
  smuggle server-only packages through convenience helper targets.

### 20.4 Command Surface

#### 20.4.1 Canonical Public CLI

Executable: `harness`

Commands:

- `harness build <subjects...>`
- `harness test [subjects...]`
- `harness run <subject>`
- `harness validate [subjects...]`
- `harness doctor`

Contributor wrapper:

- `just build <subjects...>`
- `just test [subjects...]`
- `just run <subject>`
- `just validate [subjects...]`
- `just doctor`

Rules:

- `just` is the preferred human-facing entrypoint.
- `swift run harness ...` remains the low-level fallback.
- `just` is a thin wrapper over `harness` and must not change subject
  resolution, validation policy, or artifact contracts.
- `build` requires at least one subject and accepts only the canonical
  production subjects listed below. Explicit test subjects are never valid build
  inputs.
- `run` requires exactly one runnable subject.
- `test` and `validate` accept zero or more production or explicit test
  subjects.
- Explicit test subjects are valid only for `test` and `validate`. They must
  never be inferred, promoted, or accepted by `build` or `run`.
- `doctor` takes no subject list.
- The public command surface consists only of the five commands above.

#### 20.4.2 Canonical Subjects

Production subjects:

- `SymphonyShared`
- `SymphonyServerCore`
- `SymphonyServer`
- `SymphonyServerCLI`
- `SymphonyHarness`
- `SymphonyHarnessCLI`
- `SymphonySwiftUIApp`

Explicit test subjects:

- `SymphonySharedTests`
- `SymphonyServerCoreTests`
- `SymphonyServerTests`
- `SymphonyServerCLITests`
- `SymphonyHarnessTests`
- `SymphonyHarnessCLITests`
- `SymphonySwiftUIAppTests`
- `SymphonySwiftUIAppUITests`

Runnable subjects:

- `SymphonyServerCLI`
- `SymphonySwiftUIApp`

Subject rules:

- Subject hierarchy does not exist.
- Test resolution is driven by declared subject-to-companion mappings and
  explicit test subjects, not by filename heuristics, folder traversal, or
  implicit target prefix matching.
- Production subjects map to default test companions only:
  - `SymphonyShared` -> `SymphonySharedTests`
  - `SymphonyServerCore` -> `SymphonyServerCoreTests`
  - `SymphonyServer` -> `SymphonyServerTests`
  - `SymphonyServerCLI` -> `SymphonyServerCLITests`
  - `SymphonyHarness` -> `SymphonyHarnessTests`
  - `SymphonyHarnessCLI` -> `SymphonyHarnessCLITests`
  - `SymphonySwiftUIApp` -> `SymphonySwiftUIAppTests`
- `SymphonySwiftUIAppUITests` is always explicit-only and destination-exclusive
  unless separate simulator destinations are provisioned.

#### 20.4.3 Default Subject Sets

- `harness test` with no subjects runs:
  - `SymphonyShared`
  - `SymphonyServerCore`
  - `SymphonyServer`
  - `SymphonyServerCLI`
  - `SymphonyHarness`
  - `SymphonyHarnessCLI`
  - `SymphonySwiftUIApp` when Xcode is available
- `harness validate` with no subjects runs the same set plus repository-wide
  validation policy for coverage, artifacts, and environment checks.
- `SymphonySwiftUIAppUITests` is excluded from both default sets.

#### 20.4.4 Scheduling and Execution Rules

- Multiple subjects in one command run in parallel by default.
- Subjects that require exclusive simulator or UI-test destinations must be
  auto-serialized by the scheduler.
- Capability-aware behavior is required:
  - package, server, and harness subjects run on Xcode-less hosts
  - app subjects report explicit unsupported or skipped outcomes when Xcode is
    unavailable
  - those capability-aware skips are not hard failures
- `run SymphonySwiftUIApp` may inject endpoint overrides for
  `http://localhost:8080` without mutating checked-in defaults.
- `SymphonyServer` is a buildable and testable host layer, not a direct run
  subject. Server execution goes through `SymphonyServerCLI`.
- `run SymphonyServerCLI` targets host macOS.
- `run SymphonySwiftUIApp` targets iOS Simulator or macOS according to the app's
  checked-in project configuration.

#### 20.4.5 Success Contracts

- `build`, `test`, `run`, and `validate` print the absolute path to the shared
  run root `summary.txt`.
- The shared summary identifies the run root and the per-subject artifact roots.
- `doctor` prints a full diagnostics report and may also emit a machine-readable
  form.

### 20.5 Core Interfaces and Models

#### 20.5.1 Repository and Subject Types

`RepositoryLayout`

- Role: describe the active checkout and authoritative build-definition roots.
- Fields:
  - `projectRoot`
  - `rootPackagePath`
  - `xcodeWorkspacePath`
  - `xcodeProjectPath`
  - `applicationsRoot`
- Required behavior:
  - discover the active checkout dynamically,
  - reject layouts that contain extra package manifests under `Tools/`,
  - prefer the workspace over the project when both are needed for app work.

`HarnessSubject`

- Role: describe one canonical repository subject.
- Fields:
  - `name`
  - `kind`
  - `buildSystem`
  - `defaultTestCompanion`
  - `requiresXcode`
  - `requiresExclusiveDestination`

`SubjectKind`

- Cases:
  - `library`
  - `executable`
  - `app`
  - `test`
  - `uiTest`

`BuildSystem`

- Cases:
  - `swiftpm`
  - `xcode`

#### 20.5.2 Planning and Scheduling Types

`ExecutionRequest`

- Role: describe one parsed command request.
- Fields:
  - `command`
  - `subjects`
  - `explicitTestSubjects`
  - `environment`
  - `outputMode`

`ExecutionPlan`

- Role: describe the fully expanded subject plan for one invocation.
- Fields:
  - ordered `subjectRuns`
  - `sharedRunRoot`
  - `defaultedSubjects`
  - `validationPolicies`

`ScheduledSubjectRun`

- Role: describe one subject execution within a plan.
- Fields:
  - `subject`
  - `command`
  - `schedulerLane`
  - `requiresExclusiveDestination`
  - `capabilityOutcome`

#### 20.5.3 Artifact and Reporting Types

`SubjectArtifactSet`

- Role: describe the artifact bundle for one subject under a shared run root.
- Fields:
  - `subject`
  - `artifactRoot`
  - `summaryPath`
  - `indexPath`
  - `coverageTextPath`
  - `coverageJSONPath`
  - `resultBundlePath`
  - `logPath`
  - `anomalies`

`SharedRunSummary`

- Role: describe the aggregate result of one command invocation.
- Fields:
  - `command`
  - `runID`
  - `startedAt`
  - `endedAt`
  - ordered `subjects`
  - `subjectResults`
  - `anomalies`

`ArtifactAnomaly`

- Role: describe a degraded export condition.
- Fields:
  - `code`
  - `message`
  - `phase`
  - optional `subject`

#### 20.5.4 Diagnostics Types

`DiagnosticIssue`

- Role: describe one readiness finding.
- Fields:
  - `severity`
  - `code`
  - `message`
  - `suggestedFix`

`DiagnosticsReport`

- Role: describe the full readiness result.
- Fields:
  - ordered `issues`
  - `checkedPaths`
  - `checkedExecutables`
  - `xcodeAvailability`
  - `justAvailability`
  - derived `isHealthy`

### 20.6 Artifact and Filesystem Contracts

#### 20.6.1 Canonical Root

The canonical harness build-state root is:

- `<project-root>/.build/harness`

Required subtrees:

- `runs/<run-id>/`
- `runs/latest`
- `derived-data/<subject>/`
- `results/<subject>/`
- `runtime/<subject>/`

`run-id` rules:

- `run-id` is stable for one invocation and is unique within the repository.
- `runs/latest` resolves to the latest shared run root.

#### 20.6.2 Shared Run Root

Every `build`, `test`, `run`, or `validate` invocation must create a shared run
root:

- `<project-root>/.build/harness/runs/<run-id>/`

Required shared entries:

- `summary.txt`
- `summary.json`
- `index.json`
- `subjects/`

The shared summary must include:

- the resolved command
- the requested subjects
- any defaulted subjects
- the start and end timestamps
- the aggregate exit outcome
- the absolute shared run root
- the per-subject artifact roots
- aggregate anomalies

#### 20.6.3 Per-Subject Artifact Roots

Each subject executed in a shared run must write:

- `subjects/<subject>/summary.txt`
- `subjects/<subject>/summary.json`
- `subjects/<subject>/index.json`
- `subjects/<subject>/process-stdout-stderr.txt`

When applicable, a subject root must also expose:

- `subjects/<subject>/coverage.txt`
- `subjects/<subject>/coverage.json`
- `subjects/<subject>/result.xcresult`
- `subjects/<subject>/diagnostics/`
- `subjects/<subject>/attachments/`
- `subjects/<subject>/recording.mp4`
- `subjects/<subject>/screen.png`
- `subjects/<subject>/ui-tree.txt`

Rules:

- coverage outputs are required when coverage is enabled for the subject
- optional exports must be represented as anomalies when absent
- successful Xcode-backed subject runs must not report `missing_result_bundle`
- subject summaries are the canonical human-readable truth source
- subject indexes are the canonical machine-readable truth source

#### 20.6.4 Export and Failure Semantics

- Harness must still write shared and per-subject summaries or indexes before
  surfacing execution failure.
- Missing optional exports must be recorded explicitly as anomalies.
- Xcode-backed app runs that fail because Xcode is unavailable must record an
  explicit unsupported outcome instead of a silent omission.
- Coverage policy is enforced against first-party source files only.
- `validate` and the final-state pre-commit hook must enforce `100%` first-party
  source coverage under the canonical target names and paths, excluding tests,
  generated files, and dependency sources.
- `validate` is the authoritative repository-wide gate for coverage, artifacts,
  dependency isolation, and environment policy.

### 20.7 Operational Requirements

#### 20.7.1 Repository Assumptions

The repository must provide:

- exactly one root `Package.swift`
- no additional `Package.swift` anywhere else in the repository
- checked-in `Symphony.xcworkspace`
- checked-in `SymphonyApps.xcodeproj`
- a writable `.build/` directory under the repository root

Authority split:

- the root package is authoritative for `SymphonyShared`,
  `SymphonyServerCore`, `SymphonyServer`, `SymphonyServerCLI`,
  `SymphonyHarness`, and `SymphonyHarnessCLI`
- the checked-in Xcode workspace or project is authoritative for
  `SymphonySwiftUIApp`, `SymphonySwiftUIAppTests`, and
  `SymphonySwiftUIAppUITests`

#### 20.7.2 Toolchain and Runtime Requirements

Required contributor tools:

- `swift`
- `just`

Conditionally required tools for app work:

- `xcodebuild`
- `xcrun`
- Simulator tooling and `xcresulttool`

Runtime rules:

- package, server, and harness work remains valid on hosts without Xcode
- app build, test, and run flows are capability-aware and report explicit
  unsupported or skipped outcomes on Xcode-less hosts
- successful package, server, and harness validation plus explicit app skips is
  a conformant contributor outcome on Xcode-less hosts
- ambiguous simulator-name resolution must fail with a clear remediation message
- `doctor` must report missing `just` or missing Xcode clearly and
  deterministically
- the root package is the first-class SourceKit-LSP and VS Code integration
  surface for `SymphonyShared`, `SymphonyServerCore`, `SymphonyServer`,
  `SymphonyServerCLI`, `SymphonyHarness`, and `SymphonyHarnessCLI`
- `SymphonySwiftUIApp` remains Xcode-first for editing, debugging, simulator,
  and signing workflows

#### 20.7.3 Endpoint Injection Contract

The canonical local endpoint override keys are:

- `SYMPHONY_SERVER_SCHEME`
- `SYMPHONY_SERVER_HOST`
- `SYMPHONY_SERVER_PORT`

Rules:

- `run SymphonySwiftUIApp` must support injecting those keys without modifying
  checked-in defaults
- when endpoint overrides are absent, the app defaults to
  `http://localhost:8080`

#### 20.7.4 Signing and Project Rules

- The Xcode project must not commit a fixed signing identity.
- The Xcode project must not commit a fixed development team.
- Local developer selection or CI-injected settings supply signing values when
  needed.

#### 20.7.5 Dependency Materialization Rules

- No shell package, XcodeGen input, or undocumented support script is part of the
  required dependency-materialization flow.
- If future local prerequisites need explicit preparation, they must surface
  through the canonical `harness` or `just` workflow rather than hidden tooling.
- Any required bootstrap, dependency materialization, or environment
  preparation step must be invocable through `harness` or `just`; no
  editor-specific bootstrap or wrapper-specific hidden prerequisite is part of
  the conformant contributor workflow.
