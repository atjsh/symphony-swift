import XCTest

/// Deterministic performance tests for validation gallery embedded in SymphonySwiftUIApp.
///
/// Each test loads the canonical smoke bundle via
/// `PERF_BUNDLE_PATH`, performs a scripted interaction sequence, and records
/// metrics using `measure(metrics:)`.
@MainActor
final class ValidationGalleryPerformanceUITests: XCTestCase {

  // MARK: - Properties

  private let app = XCUIApplication()

  /// Absolute path to a canonical smoke bundle for performance tests.
  /// Set the `PERF_BUNDLE_PATH` environment variable to point to a local
  /// `.symphonyvalidation` bundle. Tests that require this bundle are
  /// skipped when the variable is not set.
  private var canonicalBundlePath: String? {
    let value = ProcessInfo.processInfo.environment["PERF_BUNDLE_PATH"] ?? ""
    return value.isEmpty ? nil : value
  }

  private let bundledFixtureSelectionSlugs = [
    "macos-app-tests-progress-report-base-screenshot",
    "macos-ui-tests-root-base-screenshot",
  ]

  // MARK: - Lifecycle

  override func setUp() async throws {
    continueAfterFailure = true
  }

  override func tearDown() async throws {
    app.terminate()
  }

  // MARK: - Performance Tests

  #if os(macOS)

  func testAppLaunchPerformance() throws {
    try XCTSkipUnless(canonicalBundlePath != nil, "PERF_BUNDLE_PATH not set")
    app.terminate()

    let launchMetric = XCTApplicationLaunchMetric(waitUntilResponsive: true)
    let options = XCTMeasureOptions()
    options.iterationCount = 5

    measure(metrics: [launchMetric], options: options) {
      app.launchArguments = ["--ui-testing"]
      app.launchEnvironment["XCODE_VALIDATION_GALLERY_UI_TEST_BUNDLE_PATH"] = canonicalBundlePath
      app.launchEnvironment["XCODE_VALIDATION_GALLERY_UI_TEST_DEFAULTS_SUITE"] =
        "dev.atjsh.symphony.validation-gallery.perf-launch.\(name)"
      app.launchEnvironment["XCODE_VALIDATION_GALLERY_UI_TEST_CAPTURE_IMPORT_REQUESTS"] = "0"
      app.launch()
      navigateToValidationTab()
      let browser = element("validation-gallery-browser")
      XCTAssertTrue(browser.waitForExistence(timeout: 15))
      app.terminate()
    }
  }

  func testScrollingHitches() throws {
    try XCTSkipUnless(canonicalBundlePath != nil, "PERF_BUNDLE_PATH not set")
    launchWithCanonicalBundle()

    let metrics: [any XCTMetric] = [
      XCTHitchMetric(application: app),
      XCTClockMetric(),
    ]

    measure(metrics: metrics) {
      scrollBrowserFull()
    }
  }

  func testDisplayModeSwitchHitches() throws {
    try XCTSkipUnless(canonicalBundlePath != nil, "PERF_BUNDLE_PATH not set")
    launchWithCanonicalBundle()

    let metrics: [any XCTMetric] = [
      XCTHitchMetric(application: app),
      XCTClockMetric(),
    ]

    measure(metrics: metrics) {
      switchDisplayModes()
    }
  }

  func testGalleryItemSelectionResponsiveness() throws {
    launchWithBundledFixture()

    let metrics: [any XCTMetric] = [
      XCTHitchMetric(application: app),
      XCTClockMetric(),
      XCTCPUMetric(),
    ]
    let options = XCTMeasureOptions()
    options.iterationCount = 5

    measure(metrics: metrics, options: options) {
      cycleArtifactSelection(slugs: bundledFixtureSelectionSlugs)
    }
  }

  func testCanonicalBundleSelectionCycleResponsiveness() throws {
    try XCTSkipUnless(canonicalBundlePath != nil, "PERF_BUNDLE_PATH not set")
    launchWithCanonicalBundle()

    let metrics: [any XCTMetric] = [
      XCTHitchMetric(application: app),
      XCTClockMetric(),
      XCTCPUMetric(),
    ]
    let options = XCTMeasureOptions()
    options.iterationCount = 3

    measure(metrics: metrics, options: options) {
      cycleCanonicalArtifactSelection()
    }
  }

  #endif

  // MARK: - Launch

  private func navigateToValidationTab() {
    #if !os(macOS)
      let validationTab = app.staticTexts["Validation"].firstMatch
      guard validationTab.waitForExistence(timeout: 5) else { return }
      validationTab.tap()
      Thread.sleep(forTimeInterval: 1)
    #endif
  }

  private func launchWithCanonicalBundle() {
    #if os(macOS)
      let existing = XCUIApplication(bundleIdentifier: "dev.atjsh.symphony")
      if existing.state != .notRunning {
        existing.terminate()
        waitForTermination(of: existing)
      }
    #endif

    let suiteName = "dev.atjsh.symphony.validation-gallery.perf-tests.\(name)"
    if let defaults = UserDefaults(suiteName: suiteName) {
      defaults.removePersistentDomain(forName: suiteName)
    }

    app.launchArguments = ["--ui-testing"]
    app.launchEnvironment["SYMPHONY_UI_TESTING_INITIAL_TAB"] = "validation"
    app.launchEnvironment["XCODE_VALIDATION_GALLERY_UI_TEST_BUNDLE_PATH"] = canonicalBundlePath ?? ""
    app.launchEnvironment["XCODE_VALIDATION_GALLERY_UI_TEST_DEFAULTS_SUITE"] = suiteName
    app.launchEnvironment["XCODE_VALIDATION_GALLERY_UI_TEST_CAPTURE_IMPORT_REQUESTS"] = "0"
    app.launch()
    app.activate()
    #if os(macOS)
      _ = app.wait(for: .runningForeground, timeout: 10)
    #endif
    navigateToValidationTab()

    let browser = element("validation-gallery-browser")
    var ready = browser.waitForExistence(timeout: 15)
    #if os(macOS)
      if !ready {
        app.typeKey("n", modifierFlags: .command)
        navigateToValidationTab()
        ready = browser.waitForExistence(timeout: 10)
      }
    #endif
    XCTAssertTrue(ready, "Bundle failed to load: browser not visible after 15s.\n\(app.debugDescription)")

    #if os(macOS)
      ensureMainWindow()
    #endif
  }

  private func launchWithBundledFixture() {
    #if os(macOS)
      let existing = XCUIApplication(bundleIdentifier: "dev.atjsh.symphony")
      if existing.state != .notRunning {
        existing.terminate()
        waitForTermination(of: existing)
      }
    #endif

    let suiteName = "dev.atjsh.symphony.validation-gallery.perf-tests.fixture.\(name)"
    if let defaults = UserDefaults(suiteName: suiteName) {
      defaults.removePersistentDomain(forName: suiteName)
    }

    app.launchArguments = ["--ui-testing"]
    app.launchEnvironment.removeValue(forKey: "XCODE_VALIDATION_GALLERY_UI_TEST_BUNDLE_PATH")
    app.launchEnvironment.removeValue(forKey: "XCODE_VALIDATION_GALLERY_UI_TEST_MANIFEST_PATH")
    app.launchEnvironment["SYMPHONY_UI_TESTING_INITIAL_TAB"] = "validation"
    app.launchEnvironment["XCODE_VALIDATION_GALLERY_UI_TEST_USE_BUNDLED_FIXTURE"] = "1"
    app.launchEnvironment["XCODE_VALIDATION_GALLERY_UI_TEST_DEFAULTS_SUITE"] = suiteName
    app.launchEnvironment["XCODE_VALIDATION_GALLERY_UI_TEST_CAPTURE_IMPORT_REQUESTS"] = "0"
    app.launch()
    app.activate()
    #if os(macOS)
      _ = app.wait(for: .runningForeground, timeout: 10)
      dismissReopenDialogIfPresent()
    #endif
    navigateToValidationTab()

    let browser = element("validation-gallery-browser")
    var ready = browser.waitForExistence(timeout: 15)
    #if os(macOS)
      if !ready {
        app.typeKey("n", modifierFlags: .command)
        navigateToValidationTab()
        ready = browser.waitForExistence(timeout: 10)
      }
    #endif
    XCTAssertTrue(ready, "Fixture bundle failed to load: browser not visible after 15s.\n\(app.debugDescription)")

    #if os(macOS)
      ensureMainWindow()
    #endif
  }

  // MARK: - Interaction Scenarios

  private func scrollBrowserFull() {
    let browser = element("validation-gallery-browser")
    guard browser.exists else { return }

    for _ in 0..<2 {
      browser.swipeUp()
    }
    for _ in 0..<2 {
      browser.swipeDown()
    }
  }

  private func switchDisplayModes() {
    let gridButton = element("workspace-display-mode-grid-button")
    let listButton = element("workspace-display-mode-list-button")

    if gridButton.waitForExistence(timeout: 2) {
      gridButton.click()
    }
    if listButton.waitForExistence(timeout: 2) {
      listButton.click()
    }
  }

  private func cycleArtifactSelection(slugs: [String]) {
    let listButton = element("workspace-display-mode-list-button")
    if listButton.waitForExistence(timeout: 2) {
      listButton.click()
    }

    for slug in slugs {
      let artifact = element("artifact-card-\(slug)")
      XCTAssertTrue(artifact.waitForExistence(timeout: 5), "Missing artifact \(slug).\n\(app.debugDescription)")
      artifact.click()

      let preview = element("artifact-preview-\(slug)")
      XCTAssertTrue(preview.waitForExistence(timeout: 5), "Missing preview for \(slug).\n\(app.debugDescription)")
    }
  }

  private func cycleCanonicalArtifactSelection() {
    let listButton = element("workspace-display-mode-list-button")
    if listButton.waitForExistence(timeout: 2) {
      listButton.click()
    }

    let browser = element("validation-gallery-browser")
    guard browser.waitForExistence(timeout: 5) else { return }

    let rows = browser.buttons.allElementsBoundByIndex
    guard rows.count >= 2 else { return }

    let artifactA = rows[0]
    let artifactB = rows[1]

    artifactA.click()
    _ = app.windows.firstMatch.waitForExistence(timeout: 2)

    artifactB.click()
    _ = app.windows.firstMatch.waitForExistence(timeout: 2)

    artifactA.click()
    _ = app.windows.firstMatch.waitForExistence(timeout: 2)
  }

  // MARK: - Helpers

  private func element(_ identifier: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  private func waitForTermination(of application: XCUIApplication) {
    let deadline = Date().addingTimeInterval(5)
    while application.state != .notRunning, Date() < deadline {
      Thread.sleep(forTimeInterval: 0.1)
    }
  }

  #if os(macOS)
    private func ensureMainWindow() {
      let window = app.windows.firstMatch
      if window.waitForExistence(timeout: 5) {
        if window.frame.width < 100 || window.frame.height < 100 {
          app.typeKey("n", modifierFlags: .command)
          _ = element("validation-gallery-browser").waitForExistence(timeout: 3)
        }
      }
    }

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
  #endif
}
