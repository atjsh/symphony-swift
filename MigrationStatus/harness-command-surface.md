# Harness Command Surface Migration

## Status

- State: refresh pass updated against the live CLI, harness runtime, and harness tests on 2026-03-28.
- Confidence: the user-facing command surface is verified as subject-based; some product-centric support types still remain in the public model layer.
- Inventory: keep this task slug; this pass did not justify splitting, merging, creating, or deleting a migration-status task.

## Spec refs

- `SPEC.md` 17.8
- `SPEC.md` 20.1
- `SPEC.md` 20.4
- `SPEC.md` 20.6
- `SPEC.md` 20.7

## Verified in implementation/tests

- The root SwiftPM executable product is `harness`, and `ArgumentParser` exposes the root command name as `harness`.
  Evidence: `Package.swift`, `Sources/SymphonyHarnessCLI/SymphonyHarnessCommand.swift`, and `Tests/SymphonyHarnessCLITests/SymphonyHarnessCLITests.swift`.
- The public CLI surface exposes only `build`, `test`, `run`, `validate`, and `doctor`, and rejects legacy `--product` input at the CLI boundary.
  Evidence: `Sources/SymphonyHarnessCLI/SymphonyHarnessCommand.swift` and `Tests/SymphonyHarnessCLITests/SymphonyHarnessCLITests.swift`.
- The repository ships the checked-in `just build|test|run|validate|doctor` wrapper layer over `swift run harness ...`.
  Evidence: `justfile` and `Tests/SymphonyHarnessTests/SymphonyHarnessPackageTests.swift`.
- The library-facing execution API is subject-based through `ExecutionRequest`, `ExecutionPlan`, and the public `build`, `test`, `run`, `validate`, and `doctor` entry points on `SymphonyHarnessTool`.
  Evidence: `Sources/SymphonyHarness/Models/HarnessPlanningModels.swift`, `Sources/SymphonyHarness/SymphonyHarnessTool.swift`, and `Tests/SymphonyHarnessTests/SymphonyHarnessPackageTests.swift`.
- Shared run-root output is implemented under `.build/harness/runs/<run-id>/` with `summary.txt`, `summary.json`, `index.json`, and per-subject artifact roots. Per-subject summaries stamp canonical `subject:` identity.
  Evidence: `Sources/SymphonyHarness/SymphonyHarnessTool.swift`, `Sources/SymphonyHarness/Discovery/WorkspaceDiscovery.swift`, and `Tests/SymphonyHarnessTests/SymphonyHarnessToolCoverageTests.swift`.
- Zero-subject `validate` enforces repository-wide coverage, artifact, and doctor policies, and default Xcode-host validation runs the checked-in app plans across approved phone and tablet destinations while reporting `xcodeTestPlans` and `accessibility` separately.
  Evidence: `Sources/SymphonyHarness/SymphonyHarnessTool.swift` and `Tests/SymphonyHarnessTests/SymphonyHarnessToolCoverageTests.swift`.
- `harness run` normalizes app endpoint injection onto `SYMPHONY_SERVER_SCHEME`, `SYMPHONY_SERVER_HOST`, and `SYMPHONY_SERVER_PORT`.
  Evidence: `Sources/SymphonyHarnessCLI/SymphonyHarnessCommand.swift`, `Sources/SymphonyHarness/Runtime/EndpointOverrideStore.swift`, and `Tests/SymphonyHarnessCLITests/SymphonyHarnessCLITests.swift`.
- Runtime scheduling uses non-exclusive parallel lanes plus an exclusive Xcode lane for simulator/UI-constrained work.
  Evidence: `Sources/SymphonyHarness/SymphonyHarnessTool.swift` and `Tests/SymphonyHarnessTests/HarnessPlanningModelsTests.swift`.

## Drift / residual gaps

- The CLI and public execution entry points are subject-based, but `Sources/SymphonyHarness/Models/BuildModels.swift` still exposes public product-centric support types such as `BuildCommandFamily`, `ProductKind`, `SchemeSelector`, and `XcodeCommandRequest`. The task can no longer claim that all legacy product-mode surface has been fully buried.
- Internal harness code still carries some product-oriented terminology for coverage, artifacts, and compatibility helpers. That does not change the public command contract, but it is still migration residue.
- This refresh did not rerun a live Xcode-host `harness validate` invocation; the Xcode validation claims remain grounded in code plus tests rather than a fresh headless run.

## Next update

- Decide whether the remaining public product-centric support types are intentional or should be internalized/renamed to match the final subject-first contract.
- Re-run the focused harness CLI and harness runtime coverage when command parsing, plan scheduling, or summary classification changes.
- Keep this task slug until the remaining product-centric model residue is either removed or explicitly documented as intentional.
