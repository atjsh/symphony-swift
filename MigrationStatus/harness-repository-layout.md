# Harness Repository Layout

## Status

- State: refreshed against live repository layout and discovery logic on 2026-03-29.
- Confidence: the canonical checked-in layout and repository-wide nested-manifest enforcement are verified.
- Inventory: keep this task slug; no split or merge is warranted.

## Spec refs

- `SPEC.md` 20.3.1
- `SPEC.md` 20.5.1
- `SPEC.md` 20.6.1
- `SPEC.md` 20.7.1

## Verified in implementation/tests

- `WorkspaceDiscovery` uses the canonical `.build/harness` root and rejects build-state roots that escape the repository.
  Evidence: `Sources/SymphonyHarness/Discovery/WorkspaceDiscovery.swift` and `Tests/SymphonyHarnessTests/HarnessDiscoveryMigrationTests.swift`.
- Dynamic discovery and doctor now reject extra nested package manifests repository-wide rather than only under `Tools/`.
  Evidence: `Sources/SymphonyHarness/Discovery/WorkspaceDiscovery.swift`, `Sources/SymphonyHarness/Diagnostics/DoctorService.swift`, `Tests/SymphonyHarnessTests/HarnessDiscoveryMigrationTests.swift`, and `Tests/SymphonyHarnessTests/HarnessDoctorMigrationTests.swift`.
- `RepositoryLayout` is carried through `WorkspaceContext` and records the canonical project, package, workspace/project, and applications roots.
  Evidence: `Sources/SymphonyHarness/Models/HarnessModels.swift`, `Sources/SymphonyHarness/Models/BuildModels.swift`, and `Tests/SymphonyHarnessTests/HarnessSubjectModelTests.swift`.
- The repository currently contains the canonical app roots under `Applications/SymphonySwiftUIApp*`, checked-in app-owned `.xctestplan` files, and the canonical shared scheme `SymphonySwiftUIApp.xcscheme`, while the removed `Symphony.xcscheme` is absent.
  Evidence: `Tests/SymphonyHarnessTests/SymphonyHarnessPackageTests.swift` and `Tests/SymphonyHarnessTests/SymphonyHarnessTests.swift`.
- The live repository currently has only the root `Package.swift` and no checked-in extra nested manifest or `project.yml`, and the fresh full green validate accepted that layout.
  Evidence: `Tests/SymphonyHarnessTests/SymphonyHarnessPackageTests.swift` and `.build/harness/runs/20260328-173457-validate-b001c7f0-6bae-41bc-bf29-ee8db609588f/summary.txt`.

## Drift / residual gaps

- No active repository-layout migration gap remains in runtime discovery for nested manifests. Remaining work in this area is routine maintenance if the repository adds new generated directories or checked-in tool roots.

## Next update

- Keep the scheme/test-plan root assertions aligned with the checked-in workspace and Xcode project layout.
- Re-run the focused discovery and doctor tests whenever repository-root invariants change.
