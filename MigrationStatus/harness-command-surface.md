# Harness Command Surface Migration

## Status

- State: refreshed against the live CLI, harness runtime, and the first full green Xcode-host `just validate` run on 2026-03-29.
- Confidence: the user-facing command surface is verified as subject-based and stable.
- Inventory: keep this task slug; this remains the right place for command-surface tracking.

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
- The repository ships the checked-in `just build|test|run|validate|doctor` wrapper layer over cached scratch-path `swift run --quiet harness ...`.
  Evidence: `justfile` and `Tests/SymphonyHarnessTests/SymphonyHarnessPackageTests.swift`.
- The library-facing execution API is subject-based through `ExecutionRequest`, `ExecutionPlan`, and the public `build`, `test`, `run`, `validate`, and `doctor` entry points on `SymphonyHarnessTool`.
  Evidence: `Sources/SymphonyHarness/Models/HarnessPlanningModels.swift`, `Sources/SymphonyHarness/SymphonyHarnessTool.swift`, and `Tests/SymphonyHarnessTests/SymphonyHarnessPackageTests.swift`.
- Public reporting/support models no longer expose the legacy `BuildCommandFamily` or `ProductKind` enums. Artifact records now surface `ArtifactCommand`, while coverage inspection reports surface `RuntimeTarget`; the old product/command enums remain internal implementation detail only.
  Evidence: `Sources/SymphonyHarness/Models/BuildModels.swift`, `Sources/SymphonyHarness/Artifacts/ArtifactManager.swift`, `Tests/SymphonyHarnessTests/BuildModelCoverageTests.swift`, `Tests/SymphonyHarnessTests/SymphonyHarnessPackageTests.swift`, and the green `just preflight-swiftpm` run on 2026-03-29.
- Successful `harness test <subject>` now prints the absolute `summary.txt` path first and then a compact best-effort coverage preview sourced from structured artifacts.
  Evidence: `Sources/SymphonyHarnessCLI/TestCoveragePreviewFormatter.swift`, `Sources/SymphonyHarnessCLI/SymphonyHarnessCommand.swift`, and `Tests/SymphonyHarnessCLITests/TestCoveragePreviewFormatterTests.swift`.
- Shared run-root output is implemented under `.build/harness/runs/<run-id>/` with `summary.txt`, `summary.json`, `index.json`, and per-subject artifact roots. Per-subject summaries stamp canonical `subject:` identity.
  Evidence: `Sources/SymphonyHarness/SymphonyHarnessTool.swift`, `Sources/SymphonyHarness/Discovery/WorkspaceDiscovery.swift`, and `Tests/SymphonyHarnessTests/SymphonyHarnessToolCoverageTests.swift`.
- Zero-subject `validate` enforces repository-wide coverage, artifact, and doctor policies, and default Xcode-host validation runs the checked-in app plans across approved phone and tablet destinations while reporting `xcodeTestPlans` and `accessibility` separately.
  Evidence: `Sources/SymphonyHarness/SymphonyHarnessTool.swift`, `Tests/SymphonyHarnessTests/SymphonyHarnessToolCoverageTests.swift`, and `.build/harness/runs/20260328-173457-validate-b001c7f0-6bae-41bc-bf29-ee8db609588f/summary.txt`.
- `harness run` normalizes app endpoint injection onto `SYMPHONY_SERVER_SCHEME`, `SYMPHONY_SERVER_HOST`, and `SYMPHONY_SERVER_PORT`.
  Evidence: `Sources/SymphonyHarnessCLI/SymphonyHarnessCommand.swift`, `Sources/SymphonyHarness/Runtime/EndpointOverrideStore.swift`, and `Tests/SymphonyHarnessCLITests/SymphonyHarnessCLITests.swift`.
- Runtime scheduling uses non-exclusive parallel lanes plus an exclusive Xcode lane for simulator/UI-constrained work.
  Evidence: `Sources/SymphonyHarness/SymphonyHarnessTool.swift` and `Tests/SymphonyHarnessTests/HarnessPlanningModelsTests.swift`.

## Drift / residual gaps

- A small amount of product-oriented terminology still exists behind the public API in internal execution and compatibility helpers. The public command, request, and reporting surface is now subject-first and no longer leaks the legacy product/command enums.

## Next update

- Re-run the focused harness CLI and harness runtime coverage when command parsing, plan scheduling, or summary classification changes.
- Revisit this task only if product-oriented support metadata begins to leak back into public command or request APIs.
