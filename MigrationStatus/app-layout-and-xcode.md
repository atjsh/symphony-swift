# App Layout And Xcode

## Status

- State: refreshed against the first full green Xcode-host `just validate` run on 2026-03-29.
- Confidence: static app/Xcode layout, checked-in test-plan ownership, and live multi-destination app validation are all verified.
- Inventory: keep this task slug; the runtime revalidation gap is closed and does not require a new tracker.

## Spec refs

- `SPEC.md` 17.1
- `SPEC.md` 17.3
- `SPEC.md` 17.4
- `SPEC.md` 17.5
- `SPEC.md` 17.6
- `SPEC.md` 17.7
- `SPEC.md` 17.9
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
- Fresh live validation proved the required checked-in app plan matrix across approved phone and tablet destinations.
  Evidence: `.build/harness/runs/20260328-173457-validate-b001c7f0-6bae-41bc-bf29-ee8db609588f/summary.txt` and `.build/harness/runs/20260328-173457-validate-b001c7f0-6bae-41bc-bf29-ee8db609588f/subjects/SymphonySwiftUIApp/summary.txt`.

## Drift / residual gaps

- The exported xcresult artifacts still legitimately omit simulator recordings and UI-tree captures for some non-UI plans. Those anomalies are present in the green validate run and are not treated as failures by the current artifact contract.
- The migration stream no longer has an app/Xcode runtime revalidation blocker. Remaining work here is routine maintenance if schemes, plans, or simulator destinations change.

## Next update

- Re-run the full app validation matrix whenever scheme ownership, plan membership, or destination policy changes.
- Keep the static project/scheme/test-plan assertions aligned with `SymphonyApps.xcodeproj` whenever target naming, signing, or plan membership changes.
