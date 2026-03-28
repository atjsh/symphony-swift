# Doctor Audit Migration

## Status

- State: refreshed against live `DoctorService` behavior and a full green Xcode-host `just validate` run on 2026-03-29.
- Confidence: doctor field coverage, repository-policy gating, and its integration into environment validation are verified.
- Inventory: keep this task slug; the current behavior does not justify splitting or merging this tracker.

## Spec refs

- `SPEC.md` 17.8
- `SPEC.md` 20.3.1
- `SPEC.md` 20.5.4
- `SPEC.md` 20.7.1

## Verified in implementation/tests

- `DiagnosticsReport` carries explicit `xcodeAvailability` and `justAvailability` fields and exposes `isHealthy`.
  Evidence: `Sources/SymphonyHarness/Models/BuildModels.swift` and `Tests/SymphonyHarnessTests/HarnessDoctorMigrationTests.swift`.
- `DoctorService` checks for `just`, reports `missing_just`, records checked executables deterministically, and distinguishes Xcode-capable from Xcode-less hosts.
  Evidence: `Sources/SymphonyHarness/Diagnostics/DoctorService.swift`, `Tests/SymphonyHarnessTests/HarnessDoctorMigrationTests.swift`, and `Tests/SymphonyHarnessTests/BuildServicesCoverageTests.swift`.
- Repository-policy checks now cover extra nested `Package.swift` manifests repository-wide, the removed `project.yml` manifest, and the required app-owned `.xctestplan` location under `SymphonyApps.xcodeproj/xcshareddata/xctestplans`.
  Evidence: `Sources/SymphonyHarness/Diagnostics/DoctorService.swift`, `Sources/SymphonyHarness/Discovery/WorkspaceDiscovery.swift`, `Tests/SymphonyHarnessTests/HarnessDoctorMigrationTests.swift`, and `Tests/SymphonyHarnessTests/HarnessDiscoveryMigrationTests.swift`.
- On Xcode-capable hosts, doctor validates the canonical `SymphonySwiftUIApp` scheme instead of the removed `Symphony` alias.
  Evidence: `Sources/SymphonyHarness/Diagnostics/DoctorService.swift` and `Tests/SymphonyHarnessTests/HarnessDoctorMigrationTests.swift`.
- Zero-subject `validate` consumes doctor output as an environment-policy gate rather than leaving those findings disconnected from command execution.
  Evidence: `Tests/SymphonyHarnessTests/SymphonyHarnessToolCoverageTests.swift` and `.build/harness/runs/20260328-173457-validate-b001c7f0-6bae-41bc-bf29-ee8db609588f/summary.txt`.

## Drift / residual gaps

- `DoctorService` still does not fully audit every app bundle/module/signing/test-target field in the Xcode project. Some of those assertions remain static project/package tests rather than doctor findings.
- The test-plan check verifies canonical location and basic policy, not the full semantics of every plan entry. Full plan execution remains owned by `validate`, not `doctor`.

## Next update

- Extend this task only if `DoctorService` itself gains broader Xcode project or plan-content auditing; otherwise keep broader app-surface cleanup in the app-layout migration stream.
- Re-run the focused doctor tests whenever repository-policy checks or capability reporting change.
