import XCTest

@MainActor
final class NavigationUITests: SymphonyUITestCase {

  func testLaunchShowsSidebarSearchAndIssueList() throws {
    launchApp()

    assertRootLoaded()
    captureCheckpoint(named: "root")
  }

  func testServerEditorOpensFromToolbar() throws {
    launchApp()

    openServerEditor()

    #if os(macOS)
      XCTAssertTrue(app.radioGroups["server-editor-mode-picker"].waitForExistence(timeout: 5))
      XCTAssertTrue(app.buttons["local-server-start-button"].waitForExistence(timeout: 5))

      let existingMode = app.radioButtons["Existing Server"]
      XCTAssertTrue(existingMode.waitForExistence(timeout: 5))
      existingMode.tap()

      XCTAssertTrue(app.textFields["server-editor-host"].waitForExistence(timeout: 5))
      XCTAssertTrue(app.textFields["server-editor-port"].waitForExistence(timeout: 5))
      XCTAssertTrue(app.buttons["server-editor-connect-button"].waitForExistence(timeout: 5))
    #else
      XCTAssertTrue(app.textFields["server-editor-host"].waitForExistence(timeout: 5))
      XCTAssertTrue(app.textFields["server-editor-port"].waitForExistence(timeout: 5))
      XCTAssertTrue(app.buttons["server-editor-connect-button"].waitForExistence(timeout: 5))
    #endif
  }

  #if os(macOS)
    func testWorkflowAuthoringWizardCanGenerateWorkflowAndAdvanceToLocalServer() throws {
      launchApp(
        launchEnvironment: ["SYMPHONY_UI_TESTING_EMPTY_LOCAL_SERVER_PROFILE": "1"]
      )

      openServerEditor()

      let ownerField = app.textFields["workflow-tracker-project-owner"]
      XCTAssertTrue(ownerField.waitForExistence(timeout: 5))
      captureCheckpoint(named: "workflow-authoring")
      XCTAssertTrue(app.buttons["workflow-save-button"].waitForExistence(timeout: 5))
      ownerField.tap()
      ownerField.typeText("atjsh")

      let saveButton = app.buttons["workflow-save-button"]
      XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
      saveButton.tap()

      XCTAssertTrue(app.buttons["local-server-start-button"].waitForExistence(timeout: 5))
      XCTAssertTrue(
        app.buttons["local-server-edit-generated-workflow-button"].waitForExistence(timeout: 5)
      )
      captureCheckpoint(named: "workflow-local-server")
    }

    func testLocalServerModeCanStartInUITesting() throws {
      launchApp()

      openServerEditor()

      let startButton = app.buttons["local-server-start-button"]
      XCTAssertTrue(startButton.waitForExistence(timeout: 5))
      startButton.tap()

      XCTAssertTrue(sidebarSearchField().waitForExistence(timeout: 5))
      XCTAssertTrue(app.descendants(matching: .any)["issue-list"].waitForExistence(timeout: 10))
    }
  #endif

  func testSearchSelectIssueAndShowOverview() throws {
    launchApp()

    openSeededIssueOverview()
    captureCheckpoint(named: "overview")
  }

  func testSwitchBetweenDetailTabs() throws {
    launchApp()

    openSeededIssueOverview()
    openSessionsTab()
    captureCheckpoint(named: "sessions")

    openLogsTab()
    captureCheckpoint(named: "logs")
  }

  func testApplyLogFilterShowsScopedResults() throws {
    launchApp()

    openSeededIssueOverview()
    openLogsTab()

    let toolsFilter = logFilterElement(title: "Tools", identifier: "log-filter-tools")
    XCTAssertTrue(toolsFilter.waitForExistence(timeout: 5))
    toolsFilter.tap()

    XCTAssertTrue(app.descendants(matching: .any)["log-event-2"].waitForExistence(timeout: 5))
  }
}
