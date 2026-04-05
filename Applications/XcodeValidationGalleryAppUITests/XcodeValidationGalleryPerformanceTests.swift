import XCTest

/// Deterministic performance tests for XcodeValidationGalleryApp.
///
/// Each test loads the canonical smoke bundle via
/// `XCODE_VALIDATION_GALLERY_UI_TEST_BUNDLE_PATH`, performs a scripted
/// interaction sequence, and records metrics using `measure(metrics:)`.
///
/// Run with:
/// ```
/// xcodebuild test \
///   -project SymphonyApps.xcodeproj \
///   -scheme XcodeValidationGalleryApp \
///   -destination 'platform=macOS' \
///   -derivedDataPath .build/ui-test-derived-data \
///   -only-testing:XcodeValidationGalleryAppUITests/XcodeValidationGalleryPerformanceTests \
///   -skipPackagePluginValidation
/// ```
@MainActor
final class XcodeValidationGalleryPerformanceTests: XCTestCase {

  // MARK: - Properties

  private let app = XCUIApplication()

  /// Project root derived from this source file's compile-time path.
  private static let projectRoot: String = {
    // File: Applications/XcodeValidationGalleryAppUITests/XcodeValidationGalleryPerformanceTests.swift
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // XcodeValidationGalleryAppUITests
      .deletingLastPathComponent()  // Applications
      .deletingLastPathComponent()  // project root
      .path
  }()

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
        "dev.atjsh.xcode-validation-gallery.perf-launch.\(name)"
      app.launchEnvironment["XCODE_VALIDATION_GALLERY_UI_TEST_CAPTURE_IMPORT_REQUESTS"] = "0"
      app.launch()
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

  /// Measures select-A → select-B → select-A responsiveness with the
  /// canonical 48-artifact bundle. This reproduces the user-reported
  /// slow re-selection pattern where revisiting an already-seen artifact
  /// should be as fast as the first visit.
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

  private func launchWithCanonicalBundle() {
    #if os(macOS)
      let existing = XCUIApplication(bundleIdentifier: "dev.atjsh.xcode-validation-gallery")
      if existing.state != .notRunning {
        existing.terminate()
        waitForTermination(of: existing)
      }
    #endif

    let suiteName = "dev.atjsh.xcode-validation-gallery.perf-tests.\(name)"
    if let defaults = UserDefaults(suiteName: suiteName) {
      defaults.removePersistentDomain(forName: suiteName)
    }

    app.launchArguments = ["--ui-testing"]
    app.launchEnvironment["XCODE_VALIDATION_GALLERY_UI_TEST_BUNDLE_PATH"] = canonicalBundlePath ?? ""
    app.launchEnvironment["XCODE_VALIDATION_GALLERY_UI_TEST_DEFAULTS_SUITE"] = suiteName
    app.launchEnvironment["XCODE_VALIDATION_GALLERY_UI_TEST_CAPTURE_IMPORT_REQUESTS"] = "0"
    app.launch()
    app.activate()

    let browser = element("validation-gallery-browser")
    let ready = browser.waitForExistence(timeout: 15)
    XCTAssertTrue(ready, "Bundle failed to load: browser not visible after 15s.\n\(app.debugDescription)")

    #if os(macOS)
      ensureMainWindow()
    #endif
  }

  private func launchWithBundledFixture() {
    #if os(macOS)
      let existing = XCUIApplication(bundleIdentifier: "dev.atjsh.xcode-validation-gallery")
      if existing.state != .notRunning {
        existing.terminate()
        waitForTermination(of: existing)
      }
    #endif

    let suiteName = "dev.atjsh.xcode-validation-gallery.perf-tests.fixture.\(name)"
    if let defaults = UserDefaults(suiteName: suiteName) {
      defaults.removePersistentDomain(forName: suiteName)
    }

    app.launchArguments = ["--ui-testing"]
    app.launchEnvironment.removeValue(forKey: "XCODE_VALIDATION_GALLERY_UI_TEST_BUNDLE_PATH")
    app.launchEnvironment.removeValue(forKey: "XCODE_VALIDATION_GALLERY_UI_TEST_MANIFEST_PATH")
    app.launchEnvironment["XCODE_VALIDATION_GALLERY_UI_TEST_USE_BUNDLED_FIXTURE"] = "1"
    app.launchEnvironment["XCODE_VALIDATION_GALLERY_UI_TEST_DEFAULTS_SUITE"] = suiteName
    app.launchEnvironment["XCODE_VALIDATION_GALLERY_UI_TEST_CAPTURE_IMPORT_REQUESTS"] = "0"
    app.launch()
    app.activate()

    let browser = element("validation-gallery-browser")
    let ready = browser.waitForExistence(timeout: 15)
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

  /// Select A → B → A in the canonical bundle to exercise the re-selection
  /// path that was historically slow due to cascading view re-evaluations.
  private func cycleCanonicalArtifactSelection() {
    let listButton = element("workspace-display-mode-list-button")
    if listButton.waitForExistence(timeout: 2) {
      listButton.click()
    }

    let browser = element("validation-gallery-browser")
    guard browser.waitForExistence(timeout: 5) else { return }

    // Pick the first two visible artifact rows/cards.
    let rows = browser.buttons.allElementsBoundByIndex
    guard rows.count >= 2 else { return }

    let artifactA = rows[0]
    let artifactB = rows[1]

    // A → B → A cycle
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
  #endif
}
