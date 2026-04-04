import XCTest

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

/// UI tests for the Runner tab: navigation, configuration form state, and progress display.
@MainActor
final class XcodeValidationGalleryRunnerUITests: XCTestCase {
  var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = false
    #if os(macOS)
      NSPasteboard.general.clearContents()
    #endif
  }

  override func tearDownWithError() throws {
    if let app, app.state != .notRunning {
      app.terminate()
    }
  }

  // MARK: - Launch

  private func launchApp() {
    let application = XCUIApplication()
    application.launchArguments = ["--ui-testing"]
    application.launch()
    app = application
    app.activate()
    Thread.sleep(forTimeInterval: 1)
  }

  private func element(_ identifier: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  // MARK: - Navigation

  func testRunnerTabIsAccessible() throws {
    launchApp()

    let runnerTab = element("runnerTab")
    XCTAssertTrue(runnerTab.waitForExistence(timeout: 5), "Runner tab should exist")
  }

  func testSwitchToRunnerTabShowsConfigurationForm() throws {
    launchApp()

    let runnerTab = element("runnerTab")
    XCTAssertTrue(runnerTab.waitForExistence(timeout: 5), app.debugDescription)
    #if os(macOS)
      runnerTab.click()
    #else
      runnerTab.tap()
    #endif
    Thread.sleep(forTimeInterval: 1)

    XCTAssertTrue(
      element("startRunButton").waitForExistence(timeout: 5),
      "Start run button should be visible on runner configuration form"
    )
  }

  // MARK: - Configuration Form

  func testConfigurationFormShowsAllControls() throws {
    launchApp()
    navigateToRunnerTab()

    XCTAssertTrue(element("serverURLLabel").waitForExistence(timeout: 5), "Server URL label should exist")
    XCTAssertTrue(element("connectionIndicator").waitForExistence(timeout: 5), "Connection indicator should exist")
    XCTAssertTrue(element("subjectPicker").waitForExistence(timeout: 5), "Subject picker should exist")
    XCTAssertTrue(element("buildProfilePicker").waitForExistence(timeout: 5), "Build profile picker should exist")
    XCTAssertTrue(
      element("executionProfilePicker").waitForExistence(timeout: 5),
      "Execution profile picker should exist"
    )
    XCTAssertTrue(
      element("artifactRetentionPicker").waitForExistence(timeout: 5),
      "Artifact retention picker should exist"
    )
    XCTAssertTrue(
      element("skipRichCaptureToggle").waitForExistence(timeout: 5),
      "Skip rich capture toggle should exist"
    )
    XCTAssertTrue(
      element("skipFullMatrixToggle").waitForExistence(timeout: 5),
      "Skip full matrix toggle should exist"
    )
    XCTAssertTrue(element("startRunButton").waitForExistence(timeout: 5), "Start run button should exist")
  }

  func testStartRunButtonDisabledByDefault() throws {
    launchApp()
    navigateToRunnerTab()

    let startButton = element("startRunButton")
    XCTAssertTrue(startButton.waitForExistence(timeout: 5), "Start run button should exist")
    XCTAssertFalse(startButton.isEnabled, "Start run button should be disabled when not connected")
  }

  // MARK: - Cross-Navigation

  func testGalleryTabIsAccessibleFromRunner() throws {
    launchApp()
    navigateToRunnerTab()

    let galleryTab = element("galleryTab")
    XCTAssertTrue(galleryTab.waitForExistence(timeout: 5), "Gallery tab should exist while on runner")
    #if os(macOS)
      galleryTab.click()
    #else
      galleryTab.tap()
    #endif
    Thread.sleep(forTimeInterval: 1)

    XCTAssertTrue(
      element("open-validation-bundle-button").waitForExistence(timeout: 5)
        || element("validation-gallery-browser").waitForExistence(timeout: 5),
      "Gallery content should be visible after switching back from runner"
    )
  }

  // MARK: - Helpers

  private func navigateToRunnerTab() {
    let runnerTab = element("runnerTab")
    XCTAssertTrue(runnerTab.waitForExistence(timeout: 5), "Runner tab must exist")
    #if os(macOS)
      runnerTab.click()
    #else
      runnerTab.tap()
    #endif
    Thread.sleep(forTimeInterval: 1)
  }
}
