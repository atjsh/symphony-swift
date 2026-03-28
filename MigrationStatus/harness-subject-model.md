# Harness Subject Model

## Status

- State: refreshed against the live subject registry, execution planner, and the first full green Xcode-host `just validate` run on 2026-03-29.
- Confidence: the canonical subject model is verified in code, targeted harness tests, and fresh app-subject runtime execution.
- Inventory: keep this task slug; no additional tracker is needed.

## Spec refs

- `SPEC.md` 20.4.2
- `SPEC.md` 20.5.1

## Verified in implementation/tests

- The harness model layer defines `RepositoryLayout`, `SubjectKind`, `BuildSystem`, `HarnessSubject`, and `HarnessSubjects`.
  Evidence: `Sources/SymphonyHarness/Models/HarnessModels.swift` and `Tests/SymphonyHarnessTests/HarnessSubjectModelTests.swift`.
- The canonical production, explicit-test, and runnable subject registries match the migrated shared, server, harness, and app target families, including the final default production-to-test-companion mappings.
  Evidence: `Sources/SymphonyHarness/Models/HarnessModels.swift` and `Tests/SymphonyHarnessTests/HarnessSubjectModelTests.swift`.
- `ExecutionRequest`, `ExecutionPlan`, `ScheduledSubjectRun`, `SubjectArtifactSet`, and `SharedRunSummary` are defined as first-class harness planning/reporting types and are used by the runtime execution bridge.
  Evidence: `Sources/SymphonyHarness/Models/HarnessPlanningModels.swift`, `Sources/SymphonyHarness/SymphonyHarnessTool.swift`, and `Tests/SymphonyHarnessTests/HarnessPlanningModelsTests.swift`.
- The public reporting layer now keeps subject-neutral types at the boundary: artifact summaries expose `ArtifactCommand`, and inspection artifacts expose `RuntimeTarget` rather than the older product/command enums.
  Evidence: `Sources/SymphonyHarness/Models/BuildModels.swift`, `Tests/SymphonyHarnessTests/BuildModelCoverageTests.swift`, `Tests/SymphonyHarnessTests/SymphonyHarnessPackageTests.swift`, and the green `just preflight-swiftpm` run on 2026-03-29.
- Zero-subject `test` and `validate` expand through the canonical production subject set with Xcode-aware app inclusion, and mixed production plus explicit-test `validate` requests execute through the subject-native bridge.
  Evidence: `Sources/SymphonyHarness/SymphonyHarnessTool.swift` and `Tests/SymphonyHarnessTests/SymphonyHarnessToolCoverageTests.swift`.
- Scheduler lanes and exclusive-destination behavior are represented explicitly in the plan model and drive runtime queue selection.
  Evidence: `Sources/SymphonyHarness/SymphonyHarnessTool.swift` and `Tests/SymphonyHarnessTests/HarnessPlanningModelsTests.swift`.
- Per-subject artifact summaries stamp canonical `subject:` identity, including Xcode-routed explicit subjects such as `SymphonySwiftUIAppUITests`.
  Evidence: `Sources/SymphonyHarness/SymphonyHarnessTool.swift`, `Tests/SymphonyHarnessTests/SymphonyHarnessToolCoverageTests.swift`, and `.build/harness/runs/20260328-173457-validate-b001c7f0-6bae-41bc-bf29-ee8db609588f/subjects/SymphonySwiftUIApp/summary.txt`.
- Internal coverage recursion through `CommitHarness` resolves against canonical subject mappings and now correctly handles multiline `harness test` stdout that includes the CLI coverage preview.
  Evidence: `Sources/SymphonyHarness/Harness/CommitHarness.swift` and `Tests/SymphonyHarnessTests/ProcessHarnessCoverageTests.swift`.

## Drift / residual gaps

- No active runtime revalidation gap remains for the app-backed subject path. The current live evidence already covers the required app, app-test, and UI-test plan matrix through `validate`.
- Internal legacy product routing still exists inside execution helpers for backend/scheme selection, but it no longer leaks through the public subject/reporting model.

## Next update

- Keep the canonical subject registry and companion mappings synchronized when adding or removing production or explicit-test subjects.
- Re-run the focused harness planning and coverage bridge tests whenever subject expansion or scheduling rules change.
