# Doctor Audit Migration

## Status

- State: refresh pass updated against live `DoctorService` behavior on 2026-03-28.
- Confidence: doctor field coverage and repository-policy gating are verified; broader app-surface cleanup remains outside `DoctorService`'s current scope.
- Inventory: keep this task slug; this pass did not justify splitting, merging, creating, or deleting a migration-status task.

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
- Repository-policy checks cover the legacy `project.yml` manifest and the required app-owned `.xctestplan` location under `SymphonyApps.xcodeproj/xcshareddata/xctestplans`.
  Evidence: `Sources/SymphonyHarness/Diagnostics/DoctorService.swift`, `Tests/SymphonyHarnessTests/HarnessDoctorMigrationTests.swift`, and `Tests/SymphonyHarnessTests/BuildServicesCoverageTests.swift`.
- On Xcode-capable hosts, doctor validates the canonical `SymphonySwiftUIApp` scheme instead of the removed `Symphony` alias.
  Evidence: `Sources/SymphonyHarness/Diagnostics/DoctorService.swift` and `Tests/SymphonyHarnessTests/HarnessDoctorMigrationTests.swift`.
- Zero-subject `validate` consumes doctor output as an environment-policy gate rather than leaving those findings disconnected from command execution.
  Evidence: `Tests/SymphonyHarnessTests/SymphonyHarnessToolCoverageTests.swift`.

## Drift / residual gaps

- `DoctorService` does not currently audit the full app bundle/module/signing/test-target cleanup described elsewhere in the migration stream. Those checks are covered by static project assertions, not by doctor.
- The test-plan check verifies presence and canonical location, but not the full contents or semantics of every plan configuration.
- This refresh reran the targeted migration doctor slice, not a broader Xcode-host doctor execution with live `xcodebuild` and simulator tooling.

## Next update

- Extend this task only if `DoctorService` itself gains broader Xcode project or plan-content auditing; otherwise keep broader app-surface cleanup in the app-layout migration stream.
- Re-run the focused doctor tests whenever repository-policy checks or capability reporting change.
- Keep this task slug stable unless doctor grows into a larger repository-readiness migration area that deserves a separate tracker.
