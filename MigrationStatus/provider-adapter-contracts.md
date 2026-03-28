# Provider Adapter Contracts

## Status

- State: refreshed against the live Codex adapter, workflow parser, and the first full green integrated validate run on 2026-03-29.
- Confidence: the provider contract is verified in code and package tests, and the Codex legacy-key cleanup is now reflected in the parser.
- Inventory: keep this task slug for shared provider contract tracking; Copilot-specific protocol details now have their own tracker.

## Spec refs

- `SPEC.md` 4.4
- `SPEC.md` 6.3.6.1
- `SPEC.md` 10.5
- `SPEC.md` 10.7
- `SPEC.md` 12.1
- `SPEC.md` 17.2.3

## Verified in implementation/tests

- Codex continuation reuses the live provider thread and preserves per-session event sequencing across initial and continued turns.
  Evidence: `Sources/SymphonyServer/ProviderAdapter.swift` and `Tests/SymphonyServerTests/ProviderAdapterTests.swift`.
- Provider parsing buffers partial stdout lines until newline-delimited protocol frames are available and treats stderr as diagnostics only.
  Evidence: `Sources/SymphonyServer/ProviderAdapter.swift` and `Tests/SymphonyServerTests/ProviderAdapterTests.swift`.
- Codex startup and turn submission use the spec-shaped `session_approval_policy`, `session_sandbox`, `turn_approval_policy`, and `turn_sandbox_policy` values, including issue-title propagation into `turn/start`.
  Evidence: `Sources/SymphonyServerCore/WorkflowConfiguration.swift`, `Sources/SymphonyServer/ProviderAdapter.swift`, and `Tests/SymphonyServerCoreTests/WorkflowConfigurationTests.swift`.
- Legacy Codex aliases such as `approval_policy` and `thread_sandbox` are ignored rather than accepted as active configuration input.
  Evidence: `Sources/SymphonyServerCore/WorkflowConfiguration.swift` and `Tests/SymphonyServerCoreTests/WorkflowConfigurationTests.swift`.
- Object-shaped Codex sandbox payloads flow from workflow parsing through `thread/start` and `turn/start`.
  Evidence: `Sources/SymphonyServerCore/WorkflowConfiguration.swift`, `Sources/SymphonyServer/ProviderAdapter.swift`, and `Tests/SymphonyServerTests/ProviderAdapterTests.swift`.
- Event normalization covers approval-like, file-change, permission, unsupported-tool, and user-input-required shapes without indefinite stall, and terminal handling distinguishes completed, failed, and interrupted outcomes.
  Evidence: `Sources/SymphonyServer/ProviderAdapter.swift`, `Sources/SymphonyServer/SQLiteAgentRunEventSink.swift`, and `Tests/SymphonyServerTests/ProviderAdapterTests.swift`.
- Codex interruption prefers the protocol-native `turn/interrupt` request and only falls back to subprocess termination when needed.
  Evidence: `Sources/SymphonyServer/ProviderAdapter.swift` and `Tests/SymphonyServerTests/ProviderAdapterTests.swift`.
- The integrated `SymphonyServer` subject passed in the first full green validate run.
  Evidence: `.build/harness/runs/20260328-173457-validate-b001c7f0-6bae-41bc-bf29-ee8db609588f/subjects/SymphonyServer/summary.txt`.

## Drift / residual gaps

- This tracker now covers shared provider and Codex contract behavior only. Copilot-specific ACP/session semantics are tracked separately in `MigrationStatus/copilot-cli-adapter.md`.

## Next update

- Re-run the focused provider-adapter tests whenever handshake ordering, interrupt behavior, or normalized approval/input handling changes.
- Keep this task slug stable unless provider-specific contract tracking is split further.
