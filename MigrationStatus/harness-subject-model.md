# Harness Subject Model

## Status

- State: refresh pass updated against the live subject registry and execution planner on 2026-03-28.
- Confidence: the canonical subject model is verified in code and harness tests; app-subject runtime behavior still depends on host-specific Xcode reruns for full end-to-end confirmation.
- Inventory: keep this task slug; this pass did not justify splitting, merging, creating, or deleting a migration-status task.

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
- Zero-subject `test` and `validate` expand through the canonical production subject set with Xcode-aware app inclusion, and mixed production plus explicit-test `validate` requests execute through the subject-native bridge.
  Evidence: `Sources/SymphonyHarness/SymphonyHarnessTool.swift` and `Tests/SymphonyHarnessTests/SymphonyHarnessToolCoverageTests.swift`.
- Scheduler lanes and exclusive-destination behavior are represented explicitly in the plan model and drive runtime queue selection.
  Evidence: `Sources/SymphonyHarness/SymphonyHarnessTool.swift` and `Tests/SymphonyHarnessTests/HarnessPlanningModelsTests.swift`.
- Per-subject artifact summaries stamp canonical `subject:` identity, including Xcode-routed explicit subjects such as `SymphonySwiftUIAppUITests`.
  Evidence: `Sources/SymphonyHarness/SymphonyHarnessTool.swift` and `Tests/SymphonyHarnessTests/SymphonyHarnessToolCoverageTests.swift`.
- Internal coverage recursion through `CommitHarness` now resolves against canonical subject mappings rather than the removed public `--product` CLI contract.
  Evidence: `Sources/SymphonyHarness/Harness/CommitHarness.swift` and `Tests/SymphonyHarnessTests/ProcessHarnessCoverageTests.swift`.

## Drift / residual gaps

- The current evidence is strongest for model shape, plan expansion, and harness-side execution logic. This refresh did not rerun full Xcode-host subject execution for app-backed subjects, so runtime app-subject behavior remains verified by code and tests rather than fresh headless execution.
- No new task file is needed yet; the remaining uncertainty is runtime revalidation, not subject-model ownership.

## Next update

- Re-run Xcode-host subject execution before restoring stronger runtime wording around app-backed subject behavior.
- Keep the canonical subject registry and companion mappings synchronized when adding or removing production or explicit-test subjects.
- Revisit task boundaries only if the subject registry or scheduler grows into a distinct migration stream beyond the current harness subject model.
