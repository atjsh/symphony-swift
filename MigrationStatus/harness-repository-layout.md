# Harness Repository Layout

## Status

- State: refresh pass updated against live repository layout and discovery logic on 2026-03-28.
- Confidence: the canonical checked-in layout is verified; dynamic enforcement of "one root package only" is still narrower than the broadest spec wording.
- Inventory: keep this task slug; this pass did not justify splitting, merging, creating, or deleting a migration-status task.

## Spec refs

- `SPEC.md` 20.3.1
- `SPEC.md` 20.5.1
- `SPEC.md` 20.6.1
- `SPEC.md` 20.7.1

## Verified in implementation/tests

- `WorkspaceDiscovery` uses the canonical `.build/harness` root and rejects build-state roots that escape the repository.
  Evidence: `Sources/SymphonyHarness/Discovery/WorkspaceDiscovery.swift` and `Tests/SymphonyHarnessTests/HarnessDiscoveryMigrationTests.swift`.
- Dynamic discovery rejects extra nested package manifests under `Tools/`, including the historical `Tools/SymphonyBuildPackage/Package.swift` shape.
  Evidence: `Sources/SymphonyHarness/Discovery/WorkspaceDiscovery.swift`, `Sources/SymphonyHarness/Diagnostics/DoctorService.swift`, `Tests/SymphonyHarnessTests/HarnessDiscoveryMigrationTests.swift`, and `Tests/SymphonyHarnessTests/SymphonyHarnessPackageTests.swift`.
- `RepositoryLayout` is carried through `WorkspaceContext` and records the canonical project, package, workspace/project, and applications roots.
  Evidence: `Sources/SymphonyHarness/Models/HarnessModels.swift`, `Sources/SymphonyHarness/Models/BuildModels.swift`, and `Tests/SymphonyHarnessTests/HarnessSubjectModelTests.swift`.
- The repository currently contains the canonical app roots under `Applications/SymphonySwiftUIApp*`, checked-in app-owned `.xctestplan` files, and the canonical shared scheme `SymphonySwiftUIApp.xcscheme`, while the removed `Symphony.xcscheme` is absent.
  Evidence: `Tests/SymphonyHarnessTests/SymphonyHarnessPackageTests.swift` and `Tests/SymphonyHarnessTests/SymphonyHarnessTests.swift`.
- The live repository currently has the root `Package.swift` and does not contain `Tools/SymphonyBuildPackage/Package.swift` or `project.yml`.
  Evidence: `Tests/SymphonyHarnessTests/SymphonyHarnessPackageTests.swift`.

## Drift / residual gaps

- The spec says there is no additional `Package.swift` anywhere else in the repository, but the dynamic runtime enforcement in `WorkspaceDiscovery` and `DoctorService` currently scans `Tools/` specifically rather than performing a full recursive repository-wide manifest search.
- The current evidence proves the checked-in repository is in the expected shape. It does not yet prove that arbitrary future nested manifests outside `Tools/` would be rejected by runtime discovery.
- No separate task file is warranted yet; the remaining gap is still part of repository-layout enforcement.

## Next update

- If repository discovery is expanded from a `Tools/`-specific guard to a general nested-manifest audit, record that change here and add direct coverage for the broader scan.
- Keep the scheme/test-plan root assertions aligned with the checked-in workspace and Xcode project layout.
- Revisit task boundaries only if repository-layout enforcement splits into separate manifest-discovery and app-layout migration streams.
