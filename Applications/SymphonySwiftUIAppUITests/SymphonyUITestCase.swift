import XCTest

@MainActor
class SymphonyUITestCase: XCTestCase {

  var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  // MARK: - Launch

  func launchApp(launchEnvironment: [String: String] = [:]) {
    let existingApplication = XCUIApplication(bundleIdentifier: "dev.atjsh.symphony")
    if existingApplication.state != .notRunning {
      existingApplication.terminate()
      Thread.sleep(forTimeInterval: 1)
    }
    let application = XCUIApplication()
    application.launchArguments = ["--ui-testing"]
    application.launchEnvironment.merge(launchEnvironment) { _, newValue in newValue }
    app = application
    app.launch()
    app.activate()
    #if os(macOS)
      dismissReopenDialogIfPresent()
      ensureMainWindowIsVisible()
    #endif
    waitForUIStability()
  }

  func richMediaLaunchEnvironment() -> [String: String] {
    #if os(macOS)
      ["SYMPHONY_UI_TESTING_EMPTY_LOCAL_SERVER_PROFILE": "1"]
    #else
      [:]
    #endif
  }

  // MARK: - Navigation

  func assertRootLoaded() {
    XCTAssertTrue(sidebarSearchField().waitForExistence(timeout: 5))
    XCTAssertTrue(app.descendants(matching: .any)["issue-list"].waitForExistence(timeout: 10))
  }

  func openSeededIssueOverview() {
    let issueRow = app.buttons["issue-row-issue-1"]
    XCTAssertTrue(issueRow.waitForExistence(timeout: 10))

    let searchField = sidebarSearchField()
    XCTAssertTrue(searchField.waitForExistence(timeout: 5))
    app.activate()
    #if os(macOS)
      searchField.click()
      app.typeText("feature")
    #else
      searchField.tap()
      searchField.typeText("feature")
    #endif

    let filteredIssueRow = app.buttons["issue-row-issue-1"]
    XCTAssertTrue(filteredIssueRow.waitForExistence(timeout: 5))
    app.activate()
    filteredIssueRow.doubleTap()
    XCTAssertTrue(
      detailTabElement(title: "Sessions", identifier: "detail-tab-sessions")
        .waitForExistence(timeout: 5)
    )
  }

  func openServerEditor() {
    ensureServerEditorEntryIsVisibleIfNeeded()

    let toolbarButton = app.descendants(matching: .button)
      .matching(identifier: "server-editor-button").firstMatch
    let summaryButton = app.descendants(matching: .button)
      .matching(identifier: "server-editor-summary-button").firstMatch

    XCTAssertTrue(
      toolbarButton.waitForExistence(timeout: 3) || summaryButton.waitForExistence(timeout: 7))
    app.activate()

    for candidate in preferredServerEditorButtons(
      toolbarButton: toolbarButton,
      summaryButton: summaryButton
    ) {
      guard candidate.exists || candidate.waitForExistence(timeout: 2) else {
        continue
      }
      candidate.tap()
      if waitForServerEditorPresentation(timeout: 5) {
        return
      }
    }

    XCTAssertTrue(waitForServerEditorPresentation(timeout: 1))
  }

  func openSessionsTab() {
    let sessionsTab = detailTabElement(title: "Sessions", identifier: "detail-tab-sessions")
    XCTAssertTrue(sessionsTab.waitForExistence(timeout: 5))
    sessionsTab.tap()
    waitForUIStability()
    XCTAssertTrue(app.descendants(matching: .any)["recent-sessions"].waitForExistence(timeout: 10))
  }

  func openLogsTab() {
    let logsTab = detailTabElement(title: "Logs", identifier: "detail-tab-logs")
    XCTAssertTrue(logsTab.waitForExistence(timeout: 5))
    #if os(macOS)
      logsTab.click()
    #else
      logsTab.tap()
    #endif
    waitForUIStability()
    XCTAssertTrue(
      logFilterElement(title: "Tools", identifier: "log-filter-tools")
        .waitForExistence(timeout: 10)
    )
  }

  // MARK: - Element Finders

  func sidebarSearchField() -> XCUIElement {
    let labeledSearchField = app.searchFields["Search issues"]
    if labeledSearchField.exists {
      return labeledSearchField
    }
    return app.searchFields.firstMatch
  }

  func detailTabElement(title: String, identifier: String) -> XCUIElement {
    let identifiedButton = app.buttons[identifier]
    if identifiedButton.exists {
      return identifiedButton
    }
    let radioButton = app.radioButtons[title]
    if radioButton.exists {
      return radioButton
    }
    return app.segmentedControls.buttons[title]
  }

  func logFilterElement(title: String, identifier: String) -> XCUIElement {
    let identifiedButton = app.buttons[identifier]
    if identifiedButton.exists {
      return identifiedButton
    }
    let radioButton = app.radioButtons[title]
    if radioButton.exists {
      return radioButton
    }
    return app.segmentedControls.buttons[title]
  }

  // MARK: - Server Editor Helpers

  func preferredServerEditorButtons(
    toolbarButton: XCUIElement,
    summaryButton: XCUIElement
  ) -> [XCUIElement] {
    #if os(macOS)
      [summaryButton, toolbarButton]
    #else
      [toolbarButton, summaryButton]
    #endif
  }

  func ensureServerEditorEntryIsVisibleIfNeeded() {
    #if os(iOS)
      guard UIDevice.current.userInterfaceIdiom == .phone else {
        return
      }

      let toolbarButton = app.descendants(matching: .button)
        .matching(identifier: "server-editor-button").firstMatch
      let summaryButton = app.descendants(matching: .button)
        .matching(identifier: "server-editor-summary-button").firstMatch
      if toolbarButton.exists || summaryButton.exists {
        return
      }

      let backButton = app.buttons["BackButton"]
      if backButton.waitForExistence(timeout: 2) {
        backButton.tap()
        waitForUIStability()
      }
    #endif
  }

  func waitForServerEditorPresentation(timeout: TimeInterval) -> Bool {
    if app.descendants(matching: .any)["server-editor-sheet"].waitForExistence(timeout: timeout) {
      return true
    }

    #if os(macOS)
      return app.radioGroups["server-editor-mode-picker"].waitForExistence(timeout: timeout)
        || app.descendants(matching: .any)["workflow-authoring-step"].waitForExistence(
          timeout: timeout)
        || app.buttons["local-server-start-button"].waitForExistence(timeout: timeout)
        || app.textFields["server-editor-host"].waitForExistence(timeout: timeout)
    #else
      return app.textFields["server-editor-host"].waitForExistence(timeout: timeout)
        || app.buttons["local-server-start-button"].waitForExistence(timeout: timeout)
    #endif
  }

  // MARK: - Screenshots & Checkpoints

  func captureCheckpoint(named name: String) {
    captureCheckpoint(surface: name)
  }

  func captureCheckpoint(
    surface: String,
    orientation: String = "portrait",
    variant: String = "base"
  ) {
    let screenshot = XCTAttachment(screenshot: captureScreenshotTarget().screenshot())
    screenshot.name = attachmentName(
      surface: surface,
      orientation: orientation,
      variant: variant,
      artifact: "screenshot"
    )
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  func captureScreenshotTarget() -> XCUIElement {
    #if os(macOS)
      let window = app.windows.firstMatch
      if window.exists || window.waitForExistence(timeout: 2) {
        return window
      }
    #endif
    return app
  }

  func captureLandscapeCheckpointIfSupported(named name: String) throws {
    #if os(iOS)
      XCUIDevice.shared.orientation = .landscapeLeft
      waitForUIStability()
      captureCheckpoint(surface: name, orientation: "landscape")
      XCUIDevice.shared.orientation = .portrait
      waitForUIStability()
    #endif
  }

  func captureScrollVariants(
    for surfaceElement: XCUIElement,
    surface: String
  ) throws {
    XCTAssertTrue(surfaceElement.waitForExistence(timeout: 5))
    captureCheckpoint(surface: surface, variant: "top")
    drag(surfaceElement, from: CGVector(dx: 0.5, dy: 0.8), to: CGVector(dx: 0.5, dy: 0.35))
    waitForUIStability()
    captureCheckpoint(surface: surface, variant: "middle")
    drag(surfaceElement, from: CGVector(dx: 0.5, dy: 0.8), to: CGVector(dx: 0.5, dy: 0.2))
    waitForUIStability()
    captureCheckpoint(surface: surface, variant: "bottom")
    drag(surfaceElement, from: CGVector(dx: 0.5, dy: 0.2), to: CGVector(dx: 0.5, dy: 0.8))
    drag(surfaceElement, from: CGVector(dx: 0.5, dy: 0.2), to: CGVector(dx: 0.5, dy: 0.8))
    waitForUIStability()
  }

  func drag(_ element: XCUIElement, from startOffset: CGVector, to endOffset: CGVector) {
    app.activate()
    let start = element.coordinate(withNormalizedOffset: startOffset)
    let end = element.coordinate(withNormalizedOffset: endOffset)
    start.press(forDuration: 0.05, thenDragTo: end)
  }

  // MARK: - Utilities

  func waitForUIStability() {
    Thread.sleep(forTimeInterval: 1)
  }

  #if os(macOS)
    func dismissReopenDialogIfPresent() {
      let dialog = app.dialogs.firstMatch
      guard dialog.waitForExistence(timeout: 2) else { return }
      let dontReopenButton = dialog.buttons
        .matching(NSPredicate(format: "title CONTAINS %@", "Reopen"))
        .element(boundBy: 1)
      if dontReopenButton.exists {
        dontReopenButton.click()
      } else {
        let buttons = dialog.buttons
        if buttons.count > 0 {
          buttons.element(boundBy: buttons.count - 1).click()
        }
      }
      Thread.sleep(forTimeInterval: 1)
    }

    func ensureMainWindowIsVisible() {
      if app.windows.firstMatch.exists || app.windows.firstMatch.waitForExistence(timeout: 1) {
        return
      }
      app.activate()
      Thread.sleep(forTimeInterval: 1)
      app.typeKey("n", modifierFlags: .command)
      Thread.sleep(forTimeInterval: 1)
    }
  #endif

  func attachmentName(
    surface: String,
    orientation: String,
    variant: String,
    artifact: String,
    prefix: String? = nil
  ) -> String {
    if let prefix {
      return "\(prefix)__surface=\(surface)__orientation=\(orientation)__variant=\(variant)__artifact=\(artifact)"
    }
    return "surface=\(surface)__orientation=\(orientation)__variant=\(variant)__artifact=\(artifact)"
  }
}
