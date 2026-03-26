import XCTest

@MainActor
final class SymphonyUITests: XCTestCase {

  private var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchArguments = ["--ui-testing"]
  }

  func testLaunchShowsSidebarSearchAndIssueList() throws {
    app.launch()

    XCTAssertTrue(app.textFields["sidebar-search"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.descendants(matching: .any)["issue-list"].waitForExistence(timeout: 10))
  }

  func testServerEditorOpensFromToolbar() throws {
    app.launch()

    let serverButton = app.descendants(matching: .any)["server-editor-button"]
    XCTAssertTrue(serverButton.waitForExistence(timeout: 10))
    serverButton.tap()

    XCTAssertTrue(
      app.descendants(matching: .any)["server-editor-sheet"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.textFields["server-editor-host"].exists)
    XCTAssertTrue(app.textFields["server-editor-port"].exists)
    XCTAssertTrue(app.buttons["server-editor-connect-button"].exists)
  }

  func testSearchSelectIssueAndShowOverview() throws {
    app.launch()

    let issueRow = app.descendants(matching: .any)["issue-row-issue-1"]
    XCTAssertTrue(issueRow.waitForExistence(timeout: 10))

    let searchField = app.textFields["sidebar-search"]
    XCTAssertTrue(searchField.waitForExistence(timeout: 5))
    searchField.tap()
    searchField.typeText("feature")

    XCTAssertTrue(issueRow.waitForExistence(timeout: 5))
    issueRow.tap()

    XCTAssertTrue(app.descendants(matching: .any)["detail-summary"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["detail-tab-overview"].waitForExistence(timeout: 5))
  }

  func testSwitchBetweenDetailTabs() throws {
    app.launch()

    let issueRow = app.descendants(matching: .any)["issue-row-issue-1"]
    XCTAssertTrue(issueRow.waitForExistence(timeout: 10))
    issueRow.tap()

    let sessionsTab = app.buttons["detail-tab-sessions"]
    XCTAssertTrue(sessionsTab.waitForExistence(timeout: 5))
    sessionsTab.tap()
    XCTAssertTrue(app.descendants(matching: .any)["recent-sessions"].waitForExistence(timeout: 5))

    let logsTab = app.buttons["detail-tab-logs"]
    XCTAssertTrue(logsTab.waitForExistence(timeout: 5))
    logsTab.tap()
    XCTAssertTrue(app.buttons["log-filter-tools"].waitForExistence(timeout: 5))
  }

  func testApplyLogFilterShowsScopedResults() throws {
    app.launch()

    let issueRow = app.descendants(matching: .any)["issue-row-issue-1"]
    XCTAssertTrue(issueRow.waitForExistence(timeout: 10))
    issueRow.tap()

    app.buttons["detail-tab-logs"].tap()

    let toolsFilter = app.buttons["log-filter-tools"]
    XCTAssertTrue(toolsFilter.waitForExistence(timeout: 5))
    toolsFilter.tap()

    XCTAssertTrue(app.descendants(matching: .any)["log-event-2"].waitForExistence(timeout: 5))
  }
}
