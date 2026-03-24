# Symphony Specification

Status: Draft v2

Purpose: Define Symphony as a Swift-native issue orchestration system made up of a standalone
`Symphony Server` and a cross-platform `Symphony` SwiftUI client.

## 1. Product Definition

Symphony consists of two required products:

1. `Symphony Server`
   - A standalone Swift 6.2 server process.
   - Owns GitHub issue polling, orchestration state, workspace lifecycle, Codex integration,
     persistence, and network APIs.
   - Remains the single authoritative runtime for dispatch, retries, reconciliation, and
     observability data.

2. `Symphony`
   - A SwiftUI client that supports iOS and macOS by default.
   - Connects to a `Symphony Server` by host/domain and port.
   - Provides an observability-first operator UI for issue state, run history, agent sessions, and
     live Codex rollout logs.

Important boundaries:

- The UI is not embedded in the server process.
- GitHub issue orchestration remains the core workflow in this specification version.
- Authentication is out of scope for v1. Operators connect directly to a trusted server endpoint.
- The default client endpoint is `http://localhost:8080`.

## 2. Technology Defaults

This specification targets the following default stack:

- Swift 6.2
- SwiftUI for the client
- Swift Testing for unit, integration, and UI-adjacent logic tests
- Xcode as the default development environment
- SQLite as the required durable store for server metadata and event indexing

The specification describes product behavior and contracts. It does not require a specific Swift
HTTP framework so long as the HTTP and WebSocket behavior defined here is satisfied.

## 3. Goals and Non-Goals

### 3.1 Goals

- Poll GitHub Projects v2 on a fixed cadence and dispatch eligible issues with bounded concurrency.
- Keep one authoritative orchestrator state inside `Symphony Server`.
- Reuse deterministic per-issue workspaces across runs.
- Run Codex in per-issue workspaces only.
- Persist logs and execution metadata so history survives server restarts.
- Expose a required HTTP/JSON and WebSocket API for the native client.
- Let the SwiftUI client view current work, replay prior logs, and live-tail active sessions.
- Preserve raw Codex rollout event fidelity end-to-end.
- Support restart recovery for historical state and observability without requiring active session
  resumption.

### 3.2 Non-Goals

- Authentication, authorization, or multi-tenant access control in v1.
- Replacing GitHub issue orchestration with a generic task runner in v1.
- Embedding orchestration logic in the UI client.
- Requiring a web dashboard in addition to the native client.
- Defining a single mandatory Codex sandbox or approval posture for every deployment.
- Resuming interrupted Codex turns after process restart.

## 4. System Overview

### 4.1 Main Components

1. `Workflow Loader`
   - Reads and parses repository-owned `WORKFLOW.md`.
   - Produces a typed runtime configuration plus prompt template.

2. `Configuration Layer`
   - Applies defaults and environment indirection.
   - Validates tracker, workspace, agent, server, and persistence settings.

3. `Issue Tracker Client`
   - Talks to GitHub GraphQL for Projects v2.
   - Fetches candidate issues, issue state refreshes, and terminal-state issues.

4. `Orchestrator`
   - Owns the poll loop, claim state, retries, reconciliation, and dispatch decisions.

5. `Workspace Manager`
   - Maps issue identifiers to deterministic filesystem workspaces.
   - Enforces root containment and hook execution.

6. `Codex Runner`
   - Starts Codex app-server sessions in the issue workspace.
   - Streams raw rollout events back to the server.

7. `Persistence Layer`
   - Uses SQLite for durable metadata.
   - Persists append-only raw rollout events and indexed server state.

8. `API Layer`
   - Serves required HTTP/JSON endpoints and WebSocket log streams.
   - Reads from authoritative in-memory state plus persisted history.

9. `Symphony` Client
   - Connects to the server.
   - Displays issue lists, run details, session details, and a raw-event-aware log viewer.

### 4.2 Data Flow

1. `Symphony Server` loads `WORKFLOW.md` and validates config.
2. The orchestrator polls GitHub for active issues.
3. Eligible issues are claimed and dispatched into deterministic workspaces.
4. Codex runs in the workspace and emits rollout events.
5. The server persists those events and updates indexed runtime metadata.
6. The API exposes current state, historical state, and log replay/streaming.
7. `Symphony` fetches baseline data over HTTP and uses WebSocket for live log tails.

### 4.3 Deployment Defaults

- The server should bind loopback by default.
- The client should default to `localhost` and port `8080`.
- Remote trusted-network operation is allowed by entering a host/domain and port manually.
- Because v1 has no auth, deployments exposed beyond a trusted network are non-conformant.

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
- `last_codex_event` (string or null)
- `last_codex_message` (string or null)
- `tokens`
  - `input_tokens` (integer)
  - `output_tokens` (integer)
  - `total_tokens` (integer)
- `logs`
  - `event_count` (integer)
  - `latest_sequence` (integer or null)

### 5.5 CodexSession

Session metadata tracked while a Codex worker is active and retained after it ends.

Fields:

- `session_id` (string)
- `thread_id` (string)
- `turn_id` (string)
- `run_id` (string)
- `codex_app_server_pid` (string or null)
- `status` (string)
- `last_event_type` (string or null)
- `last_event_at` (timestamp or null)
- `turn_count` (integer)
- `token_usage`
  - `input_tokens` (integer)
  - `output_tokens` (integer)
  - `total_tokens` (integer)

### 5.6 CodexRolloutEvent

Canonical persisted and streamed event record.

Fields:

- `session_id` (string)
- `sequence` (integer)
- `timestamp` (timestamp)
- `raw_json` (string)
- `top_level_type` (string)
- `payload_type` (string or null)

Notes:

- `raw_json` is the canonical payload.
- `top_level_type` and `payload_type` are indexed helpers only.
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
  - `<thread_id>-<turn_id>`.
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
- `codex`
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

- `max_concurrent_agents` (default `10`)
- `max_turns` (default `20`)
- `max_retry_backoff_ms` (default `300000`)
- `max_concurrent_agents_by_state` (default empty map)

#### 6.3.6 `codex`

Fields:

- `command` (default `codex app-server`)
- `approval_policy` (implementation-defined Codex value)
- `thread_sandbox` (implementation-defined Codex value)
- `turn_sandbox_policy` (implementation-defined Codex value)
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
- concurrency settings
- Codex launch settings
- future prompt renders

Reload does not require:

- restarting in-flight Codex sessions
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

- Stall timeout uses `codex.stall_timeout_ms`.
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

- Codex must run with `cwd == workspace_path`.
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

## 10. Codex Execution Contract

### 10.1 Launch Contract

The server launches Codex using:

- command: `codex.command`
- invocation: `bash -lc <codex.command>`
- working directory: absolute workspace path

### 10.2 Session Startup

The client side of `Symphony Server` must speak the Codex app-server protocol and issue:

1. `initialize`
2. `initialized`
3. `thread/start`
4. `turn/start`

The first turn uses the rendered workflow prompt. Continuation turns reuse the thread and send only
continuation guidance.

### 10.3 Completion Conditions

A turn is terminal on:

- `turn/completed`
- `turn/failed`
- `turn/cancelled`
- turn timeout
- subprocess exit

### 10.4 Session Metadata Extraction

The server must extract and track:

- `thread_id`
- `turn_id`
- `session_id`
- token usage totals when available
- latest rate-limit payload when available

### 10.5 User Input and Tool Calls

Approval, sandbox, and user-input handling are deployment-defined, but must be documented.

Required behavior:

- Unsupported tool calls must fail without stalling the session.
- User-input-required flows must not hang indefinitely.
- The deployment must either resolve them, expose them, or fail the run.

## 11. Persistence and Restart Recovery

### 11.1 Storage Requirement

SQLite is required for v1.

The SQLite database is the durable source of truth for historical metadata and indexed event access.

### 11.2 Required Durable Records

The persistence layer must store enough information to reconstruct:

- issues seen by the server
- run attempts
- Codex sessions
- workspace paths associated with runs
- retry/error history
- indexed event metadata
- append-only raw rollout events

Logical tables:

1. `issues`
   - latest normalized issue snapshot per `issue_id`
2. `runs`
   - one row per worker attempt
3. `codex_sessions`
   - one row per Codex session
4. `workspaces`
   - issue-to-workspace mapping and lifecycle timestamps
5. `rollout_events`
   - one row per persisted raw event with `session_id`, `sequence`, and `raw_json`

Exact SQL names may differ if the schema preserves the same behavior.

### 11.3 Event Persistence Contract

- Raw Codex rollout events are append-only.
- Every persisted event must have a server-assigned per-session sequence.
- The raw JSON body must be stored losslessly.
- The server may additionally index event timestamp, top-level type, and payload type.
- The server may maintain a JSONL export view, but SQLite remains required.

### 11.4 Restart Recovery

After server restart:

- Historical issues, runs, sessions, and logs must remain queryable.
- Log replay must continue to work using persisted sequences and cursors.
- In-flight retry timers do not need to survive restart.
- In-flight Codex sessions do not need to resume.
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
- no claim that partially executed Codex work was resumed if it was not.

## 12. Raw Codex Log Contract

### 12.1 Canonical Format

The canonical stored and streamed observability format is the raw Codex rollout JSON event.

The server may attach transport metadata such as `session_id` and `sequence`, but the event body is
the raw Codex payload.

### 12.2 Required Renderable Event Classes

The UI must correctly render at least these event kinds:

- `session_meta`
- `response_item.message`
- `response_item.function_call`
- `response_item.function_call_output`
- `event_msg.agent_message`
- `event_msg.token_count`
- `event_msg.task_complete`

Rendering expectations:

- assistant, user, system, and developer message content should remain distinguishable
- tool/function calls must show name and arguments
- tool/function outputs must show output text with truncation policy defined by the client
- agent commentary messages should remain readable as timeline entries
- token-count events should be shown as usage metadata, not normal chat content
- task completion should be rendered as terminal session summary state

### 12.3 Unknown Event Handling

- Unknown event types must not crash the server or UI.
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
      "current_run_id": "run_001",
      "current_session_id": "thread-1-turn-7"
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
- recent sessions

### 13.6 Run Detail

`GET /api/v1/runs/{id}`

Returns:

- `RunDetail`
- associated issue snapshot
- session summary
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
  "session_id": "thread-1-turn-7",
  "items": [
    {
      "sequence": 1,
      "timestamp": "2026-03-24T12:00:01Z",
      "top_level_type": "session_meta",
      "payload_type": null,
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
  - `sequence`
  - `timestamp`
  - `top_level_type`
  - `payload_type`
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
- `CodexSession`
- `CodexRolloutEvent`
- `EventCursor`

## 14. Symphony Native Client

### 14.1 Platform Scope

The `Symphony` client must support:

- iOS
- macOS

The client should share SwiftUI presentation and data-flow logic where practical, while allowing
platform-native navigation and windowing differences.

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
- correctly render required Codex event classes
- show raw JSON fallback for unknown event types
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
- `event`
- `error`

### 15.2 Runtime Snapshot

The server should be able to derive:

- active runs
- retry queue
- aggregate token usage
- latest rate-limit snapshot

This may be served through the required APIs rather than a separate dashboard-only surface.

### 15.3 Token Accounting

- Prefer absolute totals when available from Codex events.
- Track deltas carefully to avoid double-counting.
- Preserve latest seen rate-limit payload separately from aggregate token totals.

## 16. Failure Model and Security

### 16.1 Failure Classes

1. workflow/config failures
2. tracker failures
3. workspace failures
4. Codex startup/turn failures
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
- explicit documentation of Codex approval and sandbox posture

Because no auth exists in v1:

- default loopback binding is required
- non-loopback exposure must be treated as an operator override for trusted environments only

## 17. Swift Testing Matrix

This section defines the minimum validation matrix for conformant implementations.

### 17.1 Workflow and Config

- `WORKFLOW.md` load success and failure paths
- YAML front matter parsing
- non-map front matter rejection
- defaults for tracker, polling, workspace, server, and storage
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

### 17.3 Workspace and Codex Launch

- deterministic workspace paths
- root containment enforcement
- hook execution and timeout behavior
- Codex launch with workspace `cwd`
- session startup handshake
- timeout and malformed-event handling

### 17.4 SQLite Durability

- schema creation and migration bootstrap
- persisted issue/run/session writes
- append-only rollout event persistence
- event sequence monotonicity
- restart recovery of historical state

### 17.5 API Contracts

- health serialization
- issue/run detail serialization
- log pagination
- cursor encoding and decoding
- historical replay ordering
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
- correct rendering of:
  - `session_meta`
  - `response_item.message`
  - `response_item.function_call`
  - `response_item.function_call_output`
  - `event_msg.agent_message`
  - `event_msg.token_count`
  - `event_msg.task_complete`
- unknown event raw JSON fallback

### 17.8 Acceptance Scenarios

- server restart preserves logs and run history
- client reconnect replays missed events from a cursor
- unknown raw Codex event types do not break persistence or rendering
- trusted localhost connection works without extra setup
- remote trusted-network connection works when host/domain and port are entered manually

## 18. Definition of Done

An implementation is conformant when all of the following are true:

- `Symphony Server` is implemented in Swift 6.2.
- `Symphony` is implemented in SwiftUI for iOS and macOS.
- GitHub issue orchestration remains server-owned and authoritative.
- SQLite persists issue, run, session, workspace, and raw event metadata.
- Raw Codex rollout events survive restart and are replayable by cursor.
- HTTP/JSON endpoints required by Section 13 are implemented.
- WebSocket log streaming required by Section 13 is implemented.
- The client defaults to `localhost:8080` and allows manual host/domain entry.
- The client can render the required event classes and unknown-event raw fallback.
- The Swift Testing matrix in Section 17 is satisfied.

## 19. Implementation Notes

- Historical durability matters more than in-memory elegance. If a value affects history or log
  replay, it should be persisted.
- The server may maintain additional indexes or caches, but the raw event body remains canonical.
- The client should prefer a thin rendering layer over server-owned behavior rather than duplicating
  orchestration rules locally.
