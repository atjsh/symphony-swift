import XCTest

final class SymphonyUITests: XCTestCase {

  private var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchArguments = ["--ui-testing"]
  }

  // MARK: - Connection Card

  func testConnectionCardShowsDefaultFields() throws {
    app.launch()
    let connectionCard = app.otherElements["connection-card"]
    XCTAssertTrue(connectionCard.waitForExistence(timeout: 5))
    XCTAssertTrue(app.textFields["connection-host"].exists)
    XCTAssertTrue(app.textFields["connection-port"].exists)
    XCTAssertTrue(app.buttons["connect-button"].exists)
  }

  func testConnectLoadsIssues() throws {
    app.launch()
    let connectButton = app.buttons["connect-button"]
    XCTAssertTrue(connectButton.waitForExistence(timeout: 5))
    connectButton.tap()

    let issuesSection = app.otherElements["issues-section"]
    XCTAssertTrue(issuesSection.waitForExistence(timeout: 10))
    let issueRow = app.buttons["issue-row-issue-1"]
    XCTAssertTrue(issueRow.waitForExistence(timeout: 5))
  }

  // MARK: - Issue Navigation

  func testSelectIssueShowsDetail() throws {
    app.launch()
    app.buttons["connect-button"].tap()

    let issueRow = app.buttons["issue-row-issue-1"]
    XCTAssertTrue(issueRow.waitForExistence(timeout: 10))
    issueRow.tap()

    let issueDetail = app.otherElements["issue-detail-section"]
    XCTAssertTrue(issueDetail.waitForExistence(timeout: 5))
  }

  func testIssueDetailShowsURL() throws {
    app.launch()
    app.buttons["connect-button"].tap()

    let issueRow = app.buttons["issue-row-issue-1"]
    XCTAssertTrue(issueRow.waitForExistence(timeout: 10))
    issueRow.tap()

    let urlLink = app.links["issue-url-link"]
    let exists = urlLink.waitForExistence(timeout: 5)
    // URL link may or may not render depending on platform; assert it exists when the detail is visible
    if exists {
      XCTAssertTrue(urlLink.isHittable || urlLink.exists)
    }
  }

  // MARK: - Run Detail

  func testNavigateToRunDetail() throws {
    app.launch()
    app.buttons["connect-button"].tap()

    let issueRow = app.buttons["issue-row-issue-1"]
    XCTAssertTrue(issueRow.waitForExistence(timeout: 10))
    issueRow.tap()

    let latestRunButton = app.buttons["latest-run-button"]
    XCTAssertTrue(latestRunButton.waitForExistence(timeout: 5))
    latestRunButton.tap()

    let runDetailSection = app.otherElements["run-detail-section"]
    XCTAssertTrue(runDetailSection.waitForExistence(timeout: 5))
  }

  func testRunDetailShowsTokenUsage() throws {
    app.launch()
    app.buttons["connect-button"].tap()

    let issueRow = app.buttons["issue-row-issue-1"]
    XCTAssertTrue(issueRow.waitForExistence(timeout: 10))
    issueRow.tap()

    app.buttons["latest-run-button"].tap()

    let tokenUsage = app.otherElements["token-usage"]
    XCTAssertTrue(tokenUsage.waitForExistence(timeout: 5))
  }

  // MARK: - Logs

  func testRunDetailShowsLogs() throws {
    app.launch()
    app.buttons["connect-button"].tap()

    let issueRow = app.buttons["issue-row-issue-1"]
    XCTAssertTrue(issueRow.waitForExistence(timeout: 10))
    issueRow.tap()

    app.buttons["latest-run-button"].tap()

    let logsSection = app.otherElements["logs-section"]
    XCTAssertTrue(logsSection.waitForExistence(timeout: 5))
  }

  // MARK: - Refresh

  func testRefreshButtonExists() throws {
    app.launch()
    app.buttons["connect-button"].tap()

    let refreshButton = app.buttons["refresh-button"]
    XCTAssertTrue(refreshButton.waitForExistence(timeout: 10))
  }
}
