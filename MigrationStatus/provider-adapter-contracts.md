# Provider Adapter Contracts

## Status

- State: refresh pass updated against the live Codex adapter, workflow parser, and provider tests on 2026-03-28.
- Confidence: the Codex migration work is verified in code and tests; legacy alias support remains explicit migration compatibility rather than a completed final-state cleanup.
- Inventory: keep this task slug; this pass did not justify splitting, merging, creating, or deleting a migration-status task.

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
  Evidence: `Sources/SymphonyServerCore/WorkflowConfiguration.swift`, `Sources/SymphonyServer/ProviderAdapter.swift`, `Tests/SymphonyServerCoreTests/WorkflowConfigurationTests.swift`, and `Tests/SymphonyServerTests/ProviderAdapterTests.swift`.
- Object-shaped Codex sandbox payloads flow from workflow parsing through `thread/start` and `turn/start`.
  Evidence: `Sources/SymphonyServerCore/WorkflowConfiguration.swift`, `Sources/SymphonyServer/ProviderAdapter.swift`, `Tests/SymphonyServerCoreTests/WorkflowConfigurationTests.swift`, and `Tests/SymphonyServerTests/ProviderAdapterTests.swift`.
- Event normalization covers approval-like, file-change, permission, unsupported-tool, and user-input-required shapes without indefinite stall, and terminal handling distinguishes completed, failed, and interrupted outcomes.
  Evidence: `Sources/SymphonyServer/ProviderAdapter.swift`, `Sources/SymphonyServer/SQLiteAgentRunEventSink.swift`, and `Tests/SymphonyServerTests/ProviderAdapterTests.swift`.
- Codex interruption prefers the protocol-native `turn/interrupt` request and only falls back to subprocess termination when needed.
  Evidence: `Sources/SymphonyServer/ProviderAdapter.swift` and `Tests/SymphonyServerTests/ProviderAdapterTests.swift`.
- Provider session metadata continues to surface provider thread, turn, and run identifiers through server state and persistence.
  Evidence: `Sources/SymphonyServer/ProviderAdapter.swift`, `Sources/SymphonyServer/SQLiteAgentRunEventSink.swift`, `Sources/SymphonyServer/ServerState.swift`, and `Tests/SymphonyServerTests/ServerStateAndAPITests.swift`.

## Drift / residual gaps

- Legacy aliases are still intentionally accepted during migration: `approval_policy` still feeds `sessionApprovalPolicy`, and `thread_sandbox` still feeds `sessionSandbox`.
  Evidence: `Sources/SymphonyServerCore/WorkflowConfiguration.swift` and `Tests/SymphonyServerCoreTests/WorkflowConfigurationTests.swift`.
- Because those aliases remain live, this task can no longer describe the spec-shaped Codex keys as the only accepted configuration surface. The final-state alias removal is still pending or must be explicitly declared intentional.
- This refresh reran targeted parser coverage, not the full provider-adapter suite end to end. The verified claims above are grounded in current code plus existing tests.

## Next update

- Decide whether legacy alias handling will be removed or retained as long-term compatibility behavior, and update the parser plus tests accordingly.
- Re-run the focused provider-adapter tests whenever handshake ordering, interrupt behavior, or normalized approval/input handling changes.
- Keep this task slug until the migration-only alias story is resolved and documented as final.
