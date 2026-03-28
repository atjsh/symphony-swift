# App Layout And Xcode

## Status

- State: refresh pass updated against the live repository on 2026-03-28.
- Confidence: static app/Xcode layout and repo assertions are verified; prior runtime Xcode/UI pass claims are now treated as pending revalidation.
- Inventory: keep this task slug; this pass did not justify splitting, merging, creating, or deleting a migration-status task.

## Spec refs

- `SPEC.md` 17.1
- `SPEC.md` 17.3
- `SPEC.md` 17.4
- `SPEC.md` 17.5
- `SPEC.md` 17.6
- `SPEC.md` 20.3
- `SPEC.md` 20.7.5

## Verified in implementation/tests

- The canonical app roots exist at `Applications/SymphonySwiftUIApp`, `Applications/SymphonySwiftUIAppTests`, and `Applications/SymphonySwiftUIAppUITests`, and the removed legacy app roots are absent.
  Evidence: `Tests/SymphonyHarnessTests/SymphonyHarnessPackageTests.swift`.
- The checked-in Xcode surface uses the canonical app family, shared schemes, and app-owned `.xctestplan` files under `SymphonyApps.xcodeproj/xcshareddata/xctestplans`.
  Evidence: `SymphonyApps.xcodeproj/project.pbxproj`, `SymphonyApps.xcodeproj/xcshareddata/xcschemes/SymphonySwiftUIApp.xcscheme`, `SymphonyApps.xcodeproj/xcshareddata/xcschemes/SymphonySwiftUIAppUITests.xcscheme`, and `Tests/SymphonyHarnessTests/SymphonyHarnessPackageTests.swift`.
- The app keeps `PRODUCT_NAME = Symphony`, `PRODUCT_MODULE_NAME = SymphonySwiftUIApp`, `INFOPLIST_KEY_CFBundleDisplayName = Symphony`, automatic signing, empty `DEVELOPMENT_TEAM`, and `TEST_TARGET_NAME = SymphonySwiftUIApp`.
  Evidence: `SymphonyApps.xcodeproj/project.pbxproj` and `Tests/SymphonyHarnessTests/SymphonyHarnessPackageTests.swift`.
- `Applications/SymphonySwiftUIAppTests` remains Swift Testing based, while `Applications/SymphonySwiftUIAppUITests` remains XCTest/XCUI based and owns screenshot plus accessibility audit logic.
  Evidence: `Applications/SymphonySwiftUIAppTests/BootstrapSupportTests.swift`, `Applications/SymphonySwiftUIAppUITests/SymphonySwiftUIAppUITests.swift`, and `Tests/SymphonyHarnessTests/SymphonyHarnessPackageTests.swift`.
- The UI-plan fixtures remain code-driven rather than coordinate-driven: the toolbar editor uses scoped `tap()`, required accessibility identifiers exist, screenshot checkpoints include `root`, `root-landscape`, `overview`, `sessions`, and `logs`, and the UI suite calls `performAccessibilityAudit`.
  Evidence: `Applications/SymphonySwiftUIAppUITests/SymphonySwiftUIAppUITests.swift`, `Applications/SymphonySwiftUIApp/SymphonyOperatorRootView.swift`, and `Applications/SymphonySwiftUIApp/OperatorSidebarView.swift`.
- The dedicated UI test plan still declares `SYMPHONY_UI_TESTING=1`, while the non-UI plans remain separate.
  Evidence: `SymphonyApps.xcodeproj/xcshareddata/xctestplans/SymphonySwiftUIApp.xctestplan`, `SymphonyApps.xcodeproj/xcshareddata/xctestplans/SymphonySwiftUIAppTests.xctestplan`, and `SymphonyApps.xcodeproj/xcshareddata/xctestplans/SymphonySwiftUIAppUITests.xctestplan`.

## Drift / residual gaps

- This refresh did not rerun the checked-in Xcode test plans or the seeded app UI flows. Earlier claims that the plans "compile and run", "complete end to end", or that specific seeded scenarios "pass" were stronger than the evidence collected in this pass and have been downgraded to pending revalidation.
- The current evidence is strongest for checked-in structure and static test coverage. It does not independently prove live Xcode-host behavior such as macOS UI-plan completion, screenshot attachment generation, or accessibility-audit pass status on a current host.
- No additional task file is needed for this migration stream yet; the remaining uncertainty is runtime revalidation, not a separate migration axis.

## Next update

- Re-run the checked-in `SymphonySwiftUIApp`, `SymphonySwiftUIAppTests`, and `SymphonySwiftUIAppUITests` plans on an Xcode host before restoring any "passes", "builds", or "completes" language.
- Keep the static project/scheme/test-plan assertions aligned with `SymphonyApps.xcodeproj` whenever target naming, signing, or plan membership changes.
- Revisit task boundaries only if app naming, plan ownership, or UI-test responsibilities move into a distinct migration stream.
