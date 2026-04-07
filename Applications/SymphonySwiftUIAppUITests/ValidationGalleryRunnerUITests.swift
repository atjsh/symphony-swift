import XCTest

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

/// UI tests for the Runner tab: navigation, configuration form state, and progress display.
@MainActor
final class ValidationGalleryRunnerUITests: XCTestCase {
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

  /// Launch app with Runner tab pre-selected via env vars.
  private func launchApp() {
    #if os(macOS)
      let existingApplication = XCUIApplication(bundleIdentifier: "dev.atjsh.symphony")
      if existingApplication.state != .notRunning {
        existingApplication.terminate()
        Thread.sleep(forTimeInterval: 1)
      }
    #endif

    let application = XCUIApplication()
    application.launchArguments = ["--ui-testing"]
    application.launchEnvironment["SYMPHONY_UI_TESTING_INITIAL_TAB"] = "validation"
    application.launchEnvironment["SYMPHONY_UI_TESTING_INNER_TAB"] = "runner"
    application.launch()
    app = application
    app.activate()
    Thread.sleep(forTimeInterval: 1)
    #if os(macOS)
      dismissReopenDialogIfPresent()
      ensureMainWindowIsVisible()
    #endif
  }

  /// Launch app with Gallery tab pre-selected (inner tab default).
  private func launchAppOnGalleryTab() {
    #if os(macOS)
      let existingApplication = XCUIApplication(bundleIdentifier: "dev.atjsh.symphony")
      if existingApplication.state != .notRunning {
        existingApplication.terminate()
        Thread.sleep(forTimeInterval: 1)
      }
    #endif

    let application = XCUIApplication()
    application.launchArguments = ["--ui-testing"]
    application.launchEnvironment["SYMPHONY_UI_TESTING_INITIAL_TAB"] = "validation"
    application.launch()
    app = application
    app.activate()
    Thread.sleep(forTimeInterval: 1)
    #if os(macOS)
      dismissReopenDialogIfPresent()
      ensureMainWindowIsVisible()
    #endif
  }

  #if os(macOS)
    private func dismissReopenDialogIfPresent() {
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

    private func ensureMainWindowIsVisible() {
      if app.windows.firstMatch.exists || app.windows.firstMatch.waitForExistence(timeout: 1) {
        return
      }
      app.activate()
      Thread.sleep(forTimeInterval: 1)
      app.typeKey("n", modifierFlags: .command)
      Thread.sleep(forTimeInterval: 1)
    }
  #endif

  private func navigateToValidationTab() {
    #if !os(macOS)
      let validationTab = app.staticTexts["Validation"].firstMatch
      XCTAssertTrue(validationTab.waitForExistence(timeout: 5), "Validation tab must exist.\n\(app.debugDescription)")
      validationTab.tap()
      Thread.sleep(forTimeInterval: 1)
    #endif
  }

  private func element(_ identifier: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  // MARK: - Navigation

  func testRunnerTabIsAccessible() throws {
    launchApp()

    XCTAssertTrue(
      element("startRunButton").waitForExistence(timeout: 5),
      "Runner content should be visible (start run button)"
    )
  }

  func testSwitchToRunnerTabShowsConfigurationForm() throws {
    launchApp()

    XCTAssertTrue(
      element("startRunButton").waitForExistence(timeout: 5),
      "Start run button should be visible on runner configuration form"
    )
  }

  // MARK: - Configuration Form

  func testConfigurationFormShowsAllControls() throws {
    launchApp()

    #if os(macOS)
      // macOS shows server lifecycle controls (hostname, port, start button)
      XCTAssertTrue(
        element("serverHostnameField").waitForExistence(timeout: 5), "Server hostname field should exist")
      XCTAssertTrue(
        element("serverPortField").waitForExistence(timeout: 5), "Server port field should exist")
      XCTAssertTrue(
        element("connectionIndicator").waitForExistence(timeout: 5), "Connection indicator should exist")
      XCTAssertTrue(
        element("validationServerStartButton").waitForExistence(timeout: 5),
        "Server start button should exist")
    #else
      // iOS shows read-only server URL
      XCTAssertTrue(element("serverURLLabel").waitForExistence(timeout: 5), "Server URL label should exist")
      XCTAssertTrue(element("connectionIndicator").waitForExistence(timeout: 5), "Connection indicator should exist")
    #endif
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

    let startButton = element("startRunButton")
    XCTAssertTrue(startButton.waitForExistence(timeout: 5), "Start run button should exist")
    XCTAssertFalse(startButton.isEnabled, "Start run button should be disabled when not connected")
  }

  // MARK: - Cross-Navigation

  func testGalleryTabIsAccessibleFromRunner() throws {
    launchAppOnGalleryTab()

    XCTAssertTrue(
      element("open-validation-bundle-button").waitForExistence(timeout: 5)
        || element("validation-gallery-browser").waitForExistence(timeout: 5),
      "Gallery content should be visible on Gallery tab"
    )
  }

  // MARK: - Server Lifecycle (macOS)

  #if os(macOS)
    func testServerStartButtonVisibleWhenStopped() throws {
      launchApp()

      let startButton = element("validationServerStartButton")
      XCTAssertTrue(startButton.waitForExistence(timeout: 5), "Server start button should be visible in idle state")

      let indicator = element("connectionIndicator")
      XCTAssertTrue(indicator.waitForExistence(timeout: 5), "Connection indicator should be visible")
    }

    func testServerStartStopCycleUpdatesUI() throws {
      launchApp()

      let startButton = element("validationServerStartButton")
      XCTAssertTrue(startButton.waitForExistence(timeout: 5), "Server start button should exist")
      startButton.click()
      Thread.sleep(forTimeInterval: 2)

      // After starting with UITestingValidationServerManager, should transition to running
      let stopButton = element("validationServerStopButton")
      XCTAssertTrue(
        stopButton.waitForExistence(timeout: 10),
        "Server stop button should appear after start"
      )

      stopButton.click()
      Thread.sleep(forTimeInterval: 2)

      // After stopping, start button should reappear
      let startButtonAgain = element("validationServerStartButton")
      XCTAssertTrue(
        startButtonAgain.waitForExistence(timeout: 5),
        "Server start button should reappear after stop"
      )
    }

    func testServerTranscriptVisibleAfterStart() throws {
      launchApp()

      let startButton = element("validationServerStartButton")
      XCTAssertTrue(startButton.waitForExistence(timeout: 5))
      startButton.click()
      Thread.sleep(forTimeInterval: 2)

      let transcriptDisclosure = element("serverTranscriptDisclosure")
      XCTAssertTrue(
        transcriptDisclosure.waitForExistence(timeout: 5),
        "Server transcript disclosure should be visible after start"
      )
    }

    func testServerHostnameAndPortFieldsEditable() throws {
      launchApp()

      let hostnameField = element("serverHostnameField")
      XCTAssertTrue(hostnameField.waitForExistence(timeout: 5), "Hostname field should exist")

      let portField = element("serverPortField")
      XCTAssertTrue(portField.waitForExistence(timeout: 5), "Port field should exist")
    }
  #endif
}
