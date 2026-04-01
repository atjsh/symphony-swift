import XCTest

@MainActor
final class RichMediaAndValidationUITests: SymphonyUITestCase {

  func testRichMediaWalkthroughCapturesExtensibleSurfaceMatrix() throws {
    launchApp(launchEnvironment: richMediaLaunchEnvironment())

    assertRootLoaded()
    captureCheckpoint(named: "root")
    try captureLandscapeCheckpointIfSupported(named: "root-landscape")

    openSeededIssueOverview()
    try captureScrollVariants(
      for: app.descendants(matching: .any).matching(identifier: "overview-scroll").firstMatch,
      surface: "overview"
    )

    openSessionsTab()
    try captureScrollVariants(
      for: app.descendants(matching: .any).matching(identifier: "sessions-scroll").firstMatch,
      surface: "sessions"
    )

    openLogsTab()
    try captureScrollVariants(
      for: app.descendants(matching: .any).matching(identifier: "logs-list").firstMatch,
      surface: "logs"
    )

    openServerEditor()
    captureCheckpoint(surface: "server-editor")

    #if os(macOS)
      let workflowAuthoringStep = app.descendants(matching: .any)
        .matching(identifier: "workflow-authoring-step").firstMatch
      if workflowAuthoringStep.waitForExistence(timeout: 5) {
        captureCheckpoint(surface: "workflow-authoring", variant: "top")
        try captureScrollVariants(for: workflowAuthoringStep, surface: "workflow-authoring")

        let ownerField = app.textFields["workflow-tracker-project-owner"]
        XCTAssertTrue(ownerField.waitForExistence(timeout: 5))
        ownerField.tap()
        ownerField.typeText("atjsh")

        let saveButton = app.buttons["workflow-save-button"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()
      }

      let localServerStep = app.descendants(matching: .any)
        .matching(identifier: "local-server-step").firstMatch
      XCTAssertTrue(localServerStep.waitForExistence(timeout: 5))
      captureCheckpoint(surface: "workflow-local-server", variant: "top")
      try captureScrollVariants(for: localServerStep, surface: "workflow-local-server")
    #endif
  }

  func testValidationMatrixCapturesNamedCheckpointsAndAuditsVisibleScreens() throws {
    launchApp()

    assertRootLoaded()
    captureCheckpoint(named: "root")
    try captureLandscapeCheckpointIfSupported(named: "root-landscape")

    openSeededIssueOverview()
    captureCheckpoint(named: "overview")

    openSessionsTab()
    captureCheckpoint(named: "sessions")

    openLogsTab()
    captureCheckpoint(named: "logs")
  }

  func testAccessibilityAuditCoversRequiredCheckpoints() throws {
    launchApp()

    assertRootLoaded()
    try performAccessibilityAuditForCurrentCheckpoint(named: "root")
    try performLandscapeAccessibilityAuditIfSupported(named: "root-landscape")

    openSeededIssueOverview()
    try performAccessibilityAuditForCurrentCheckpoint(named: "overview")

    openSessionsTab()
    try performAccessibilityAuditForCurrentCheckpoint(named: "sessions")

    openLogsTab()
    try performAccessibilityAuditForCurrentCheckpoint(named: "logs")
  }
}
