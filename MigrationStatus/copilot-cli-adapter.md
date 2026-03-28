# Copilot CLI Adapter

## Status

- State: created from the first full green integrated validate run on 2026-03-29.
- Confidence: the Copilot CLI adapter is aligned with the current spec-shaped session contract in code and package tests.
- Inventory: this new tracker owns Copilot-specific protocol and continuation behavior that was previously overloaded into the shared provider tracker.

## Spec refs

- `SPEC.md` 10.2
- `SPEC.md` 10.9
- `SPEC.md` 12.1

## Verified in implementation/tests

- Copilot startup now sends `initialize` followed by `newSession`, not the older `session/start` flow.
  Evidence: `Sources/SymphonyServer/ProviderAdapter.swift` and `Tests/SymphonyServerTests/ProviderAdapterTests.swift`.
- Copilot protocol handling recognizes both `session/request_permission` and `requestPermission`, and automatically responds through the adapter bridge.
  Evidence: `Sources/SymphonyServer/ProviderAdapter.swift` and `Tests/SymphonyServerTests/ProviderAdapterTests.swift`.
- Copilot session metadata updates are recognized through both `session/update` and `sessionUpdate` forms.
  Evidence: `Sources/SymphonyServer/ProviderAdapter.swift` and `Tests/SymphonyServerTests/ProviderAdapterTests.swift`.
- Copilot continuation no longer throws `unsupportedProvider(.copilotCLI)` and instead reuses the active managed session with a continuation prompt message derived from Symphony guidance.
  Evidence: `Sources/SymphonyServer/ProviderAdapter.swift` and `Tests/SymphonyServerTests/ProviderAdapterTests.swift`.
- The integrated `SymphonyServer` subject passed in the first full green validate run after these contract changes landed.
  Evidence: `.build/harness/runs/20260328-173457-validate-b001c7f0-6bae-41bc-bf29-ee8db609588f/subjects/SymphonyServer/summary.txt`.

## Drift / residual gaps

- Copilot interruption is still not a protocol-native feature in this adapter path. The current `interruptSession` implementation returns `false`, so interruption semantics remain weaker than the richer Codex adapter path.
- The strongest evidence here is package-test and integrated server-subject validation. There is not yet a separate live Copilot CLI host transcript captured under `MigrationStatus`.

## Next update

- Add a dedicated live Copilot CLI transcript artifact only if a future migration pass needs to prove provider-host interoperability beyond package-test coverage.
- Re-run the focused provider-adapter tests whenever Copilot method names, session metadata handling, or continuation behavior changes.
