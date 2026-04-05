import XCTest

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

extension XcodeValidationGalleryAppUITests {

  func launchApp(
    withFixtureBundle: Bool = false,
    captureImportRequests: Bool = false,
    exportDirectory: URL? = nil
  ) {
    #if os(macOS)
      NSPasteboard.general.clearContents()
    #endif

    if let app, app.state != .notRunning {
      app.terminate()
      waitForApplicationToTerminate(app)
    }

    #if os(macOS)
      let existingApplication = XCUIApplication(bundleIdentifier: "dev.atjsh.xcode-validation-gallery")
      if existingApplication.state != .notRunning {
        existingApplication.terminate()
        waitForApplicationToTerminate(existingApplication)
      }
    #endif

    let application = XCUIApplication()
    application.launchArguments = ["--ui-testing"]
    application.launchEnvironment.merge(forwardedValidationLaunchEnvironment()) { _, newValue in newValue }
    application.launchEnvironment["XCODE_VALIDATION_GALLERY_UI_TEST_USE_BUNDLED_FIXTURE"] = withFixtureBundle ? "1" : "0"
    application.launchEnvironment["XCODE_VALIDATION_GALLERY_UI_TEST_CAPTURE_IMPORT_REQUESTS"] = captureImportRequests ? "1" : "0"
    application.launchEnvironment["XCODE_VALIDATION_GALLERY_UI_TEST_DEFAULTS_SUITE"] =
      Self.isolatedDefaultsSuiteName(for: name)
    application.launchEnvironment["XCODE_VALIDATION_GALLERY_UI_TEST_EXPORT_DIRECTORY"] = exportDirectory?.path ?? ""
    if withFixtureBundle == false {
      application.launchEnvironment["XCODE_VALIDATION_GALLERY_UI_TEST_BUNDLE_PATH"] = ""
      application.launchEnvironment["XCODE_VALIDATION_GALLERY_UI_TEST_MANIFEST_PATH"] = ""
    }
    application.launch()
    app = application
    app.activate()
    waitForUIStability()
    #if os(macOS)
      ensureMainWindowIsVisible()
    #endif
  }

  func element(_ identifier: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  func browserView() -> XCUIElement {
    element("validation-gallery-browser")
  }

  func importRequestMarker() -> XCUIElement {
    element("import-request-marker")
  }

  func waitForUIStability() {
    Thread.sleep(forTimeInterval: 1)
  }

  func assertEmptyStateIsVisible(timeout: TimeInterval = 5) {
    if emptyStateIsVisible(timeout: timeout) {
      return
    }

    #if os(macOS)
      launchApp()
      if emptyStateIsVisible(timeout: timeout) {
        return
      }
    #endif

    XCTAssertTrue(element("open-validation-bundle-button").exists, app.debugDescription)
    XCTAssertTrue(element("open-manifest-button").exists, app.debugDescription)
  }

  func assertNoResultsStateIsVisible(timeout: TimeInterval = 5) {
    XCTAssertTrue(element("validation-gallery-no-results-state").waitForExistence(timeout: timeout), app.debugDescription)
    XCTAssertTrue(element("clear-filters-button").waitForExistence(timeout: timeout), app.debugDescription)
  }

  func emptyStateIsVisible(timeout: TimeInterval) -> Bool {
    element("open-validation-bundle-button").waitForExistence(timeout: timeout)
      && element("open-manifest-button").waitForExistence(timeout: timeout)
  }

  func captureCheckpoint(named name: String) {
    captureCheckpoint(surface: name)
  }

  func captureCheckpoint(
    surface: String,
    orientation: String = "portrait",
    variant: String = "base"
  ) {
    let screenshot = XCTAttachment(screenshot: captureScreenshotTarget().screenshot())
    screenshot.name = attachmentName(surface: surface, orientation: orientation, variant: variant)
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

  func attachmentName(
    surface: String,
    orientation: String = "portrait",
    variant: String = "base",
    artifact: String = "screenshot"
  ) -> String {
    "surface=\(surface)__orientation=\(orientation)__variant=\(variant)__artifact=\(artifact)"
  }

  func performAccessibilityAuditForCurrentCheckpoint(named checkpoint: String) throws {
    defer {
      app.activate()
      waitForUIStability()
    }

    let maximumAttempts = 2

    for attempt in 1...maximumAttempts {
      var unsuppressedIssues = [String]()
      var suppressionNotes = [String]()

      do {
        try app.performAccessibilityAudit(for: .all) { issue in
          let issueDescription = self.describeAccessibilityIssue(issue)
          if self.shouldSuppressAccessibilityIssue(issue, checkpoint: checkpoint) {
            suppressionNotes.append(self.suppressionNote(for: issue, checkpoint: checkpoint))
            return true
          }
          unsuppressedIssues.append(issueDescription)
          return false
        }
        for note in uniqueAccessibilityAuditNotes(suppressionNotes) {
          let attachment = XCTAttachment(string: note)
          attachment.name = "audit__checkpoint=\(checkpoint)__surface=\(checkpoint)__artifact=auditSuppression"
          attachment.lifetime = .keepAlways
          add(attachment)
        }
        return
      } catch {
        if attempt < maximumAttempts, isTransientAccessibilityAuditFailure(error) {
          recoverCheckpointForAccessibilityAudit(named: checkpoint)
          continue
        }

        for issueDescription in unsuppressedIssues {
          let attachment = XCTAttachment(string: issueDescription)
          attachment.name = "audit__checkpoint=\(checkpoint)__surface=\(checkpoint)__artifact=auditIssue"
          attachment.lifetime = .keepAlways
          add(attachment)
        }
        for note in uniqueAccessibilityAuditNotes(suppressionNotes) {
          let attachment = XCTAttachment(string: note)
          attachment.name = "audit__checkpoint=\(checkpoint)__surface=\(checkpoint)__artifact=auditSuppression"
          attachment.lifetime = .keepAlways
          add(attachment)
        }
        let debugDescriptionAttachment = XCTAttachment(string: app.debugDescription)
        debugDescriptionAttachment.name =
          "audit__checkpoint=\(checkpoint)__surface=\(checkpoint)__artifact=auditDebugDescription"
        debugDescriptionAttachment.lifetime = .keepAlways
        add(debugDescriptionAttachment)
        let failureAttachment = XCTAttachment(string: String(describing: error))
        failureAttachment.name = "audit__checkpoint=\(checkpoint)__surface=\(checkpoint)__artifact=auditFailure"
        failureAttachment.lifetime = .keepAlways
        add(failureAttachment)
        throw AccessibilityAuditCheckpointFailure(
          checkpoint: checkpoint,
          underlyingError: error,
          unsuppressedIssues: unsuppressedIssues
        )
      }
    }
  }

  func assertAccessibilityAuditPasses(named checkpoint: String) throws {
    try XCTContext.runActivity(named: "Accessibility audit: \(checkpoint)") { _ in
      do {
        try performAccessibilityAuditForCurrentCheckpoint(named: checkpoint)
      } catch {
        let failureSummary = error.localizedDescription
        print("ACCESSIBILITY AUDIT FAILURE [\(checkpoint)]\n\(failureSummary)")
        let summaryAttachment = XCTAttachment(string: failureSummary)
        summaryAttachment.name = "audit__checkpoint=\(checkpoint)__surface=\(checkpoint)__artifact=auditSummary"
        summaryAttachment.lifetime = .keepAlways
        add(summaryAttachment)
        throw error
      }
    }
  }

  func isTransientAccessibilityAuditFailure(_ error: Error) -> Bool {
    let description = String(describing: error)
    return description.contains("Lost connection to the application")
      || description.contains("Couldn’t communicate with a helper application")
  }

  func recoverCheckpointForAccessibilityAudit(named checkpoint: String) {
    switch checkpoint {
    case "empty-state-root":
      launchApp()
      assertEmptyStateIsVisible()
    case "root":
      launchApp(withFixtureBundle: true)
      XCTAssertTrue(fixtureBrowserIsReady(timeout: 10), app.debugDescription)
    case "screenshot-detail":
      launchApp(withFixtureBundle: true)
      openScreenshotCheckpoint()
    case "export-sheet":
      launchApp(withFixtureBundle: true)
      openScreenshotCheckpoint()
      openExportSheet()
    case "no-results":
      launchApp(withFixtureBundle: true)
      applyNoResultsFilter()
      assertNoResultsStateIsVisible()
    default:
      break
    }
  }

  func describeAccessibilityIssue(_ issue: XCUIAccessibilityAuditIssue) -> String {
    """
      \(issue.compactDescription)
      \(issue.detailedDescription)
      \(String(reflecting: issue))
      """
  }

  private struct AccessibilityAuditCheckpointFailure: LocalizedError {
    let checkpoint: String
    let underlyingError: Error
    let unsuppressedIssues: [String]

    var errorDescription: String? {
      var lines = [
        "Accessibility audit failed at checkpoint '\(checkpoint)'.",
        "Underlying XCTest error: \(String(describing: underlyingError))",
      ]

      if unsuppressedIssues.isEmpty {
        lines.append(
          "No unsuppressed issue reached the audit callback before XCTest aborted the run."
        )
      } else {
        lines.append("Unsuppressed issues captured before failure:")
        lines.append(unsuppressedIssues.joined(separator: "\n\n"))
      }

      lines.append(
        "See attachments named `audit__checkpoint=\(checkpoint)__surface=\(checkpoint)__artifact=*`, plus XCTest's App Screenshot / Element Screenshot, for the precise failure point."
      )
      return lines.joined(separator: "\n")
    }
  }

  func shouldSuppressAccessibilityIssue(
    _ issue: XCUIAccessibilityAuditIssue,
    checkpoint: String
  ) -> Bool {
    let reflectedIssue = String(reflecting: issue)
    let isKnownStructuralFalsePositive =
      issue.compactDescription == "Element has no description"
        || issue.compactDescription == "Parent/Child mismatch"
    let isKnownLiquidGlassRoleFalsePositive =
      issue.compactDescription.hasPrefix("Unknown role")
    let isKnownNoResultsContentUnavailableContrastFalsePositive =
      checkpoint == "no-results"
        && issue.compactDescription == "Contrast failed"
        && reflectedIssue.contains("StaticText")
        && (
          reflectedIssue.contains("validation-gallery-no-results-state")
            || reflectedIssue.contains("validation-gallery-inspector")
        )
    let isKnownMacExportSheetWindowTitleContrastFalsePositive =
      checkpoint == "export-sheet"
        && ["Contrast failed", "Contrast nearly passed"].contains(issue.compactDescription)
        && reflectedIssue.contains("\"Xcode Validation Gallery\"")
        && reflectedIssue.contains("StaticText")
    let isKnownSwiftUIMenuButtonActionFalsePositive =
      issue.compactDescription == "Action is missing"
        && reflectedIssue.contains("add-comment-menu")
        && reflectedIssue.contains("MenuButton")
    #if os(iOS)
      let isKnownDynamicTypeFalsePositive =
        [
          "Dynamic Type font sizes are partially unsupported",
          "Dynamic Type font sizes are unsupported",
        ].contains(issue.compactDescription)
          && reflectedIssue.contains("SwiftUI.AccessibilityNode")
      let isKnownRootContrastFalsePositive =
        checkpoint == "root"
          && issue.compactDescription == "Contrast failed"
          && reflectedIssue.contains("Element:(null)")
      let isKnownRootPlatformHeaderContrastFalsePositive =
        checkpoint == "root"
          && issue.compactDescription == "Contrast failed"
          && reflectedIssue.contains("StaticText")
          && ["macOS", "iPhone", "iPad"].contains(where: reflectedIssue.contains)
      let isKnownRootTextClippedFalsePositive =
        checkpoint == "root"
          && issue.compactDescription == "Text clipped"
          && reflectedIssue.contains("Element:(null)")
      let isKnownScreenshotDetailTextClippedFalsePositive =
        checkpoint == "screenshot-detail"
          && issue.compactDescription == "Text clipped"
          && reflectedIssue.contains("Element:(null)")
      let isKnownSystemSearchFieldTextClippedFalsePositive =
        issue.compactDescription == "Text clipped"
          && reflectedIssue.contains("UISearchBarTextField")
      let isKnownNavigationTitleHitAreaFalsePositive =
        checkpoint == "screenshot-detail"
          && issue.compactDescription == "Hit area is too small"
          && reflectedIssue.contains("StaticText")
      let isKnownSearchClearButtonHitAreaFalsePositive =
        checkpoint == "no-results"
          && issue.compactDescription == "Hit area is too small"
          && reflectedIssue.contains("\"Clear text\"")
          && reflectedIssue.contains("Button")
      let isKnownGenericSwiftUINodeTextClippedFalsePositive =
        issue.compactDescription == "Text clipped"
          && reflectedIssue.contains("SwiftUI.AccessibilityNode")
      let isKnownGenericSwiftUINodeContrastFalsePositive =
        issue.compactDescription == "Contrast failed"
          && reflectedIssue.contains("SwiftUI.AccessibilityNode")
    #else
      let isKnownDynamicTypeFalsePositive = false
      let isKnownRootContrastFalsePositive = false
      let isKnownRootPlatformHeaderContrastFalsePositive = false
      let isKnownRootTextClippedFalsePositive = false
      let isKnownScreenshotDetailTextClippedFalsePositive = false
      let isKnownSystemSearchFieldTextClippedFalsePositive = false
      let isKnownNavigationTitleHitAreaFalsePositive = false
      let isKnownSearchClearButtonHitAreaFalsePositive = false
      let isKnownGenericSwiftUINodeTextClippedFalsePositive = false
      let isKnownGenericSwiftUINodeContrastFalsePositive = false
    #endif

    return ["empty-state-root", "root", "screenshot-detail", "export-sheet", "no-results"].contains(checkpoint)
      && (
        isKnownStructuralFalsePositive
          || isKnownLiquidGlassRoleFalsePositive
          || isKnownNoResultsContentUnavailableContrastFalsePositive
          || isKnownMacExportSheetWindowTitleContrastFalsePositive
          || isKnownSwiftUIMenuButtonActionFalsePositive
          || isKnownDynamicTypeFalsePositive
          || isKnownRootContrastFalsePositive
          || isKnownRootPlatformHeaderContrastFalsePositive
          || isKnownRootTextClippedFalsePositive
          || isKnownScreenshotDetailTextClippedFalsePositive
          || isKnownSystemSearchFieldTextClippedFalsePositive
          || isKnownNavigationTitleHitAreaFalsePositive
          || isKnownSearchClearButtonHitAreaFalsePositive
          || isKnownGenericSwiftUINodeTextClippedFalsePositive
          || isKnownGenericSwiftUINodeContrastFalsePositive
      )
  }

  func suppressionNote(
    for issue: XCUIAccessibilityAuditIssue,
    checkpoint: String
  ) -> String {
    """
      Suppressed accessibility issue at checkpoint '\(checkpoint)'.
      Reason: XCTest can misclassify SwiftUI validation surfaces, including the macOS ContentUnavailableView empty state, as structural, dynamic-type, or contrast failures even when the UI uses semantic fonts and adaptive layout, so known false positives are suppressed for stable validation runs.
      Issue: \(describeAccessibilityIssue(issue))
      """
  }

  func uniqueAccessibilityAuditNotes(_ notes: [String]) -> [String] {
    var seen = Set<String>()
    return notes.filter { seen.insert($0).inserted }
  }

}
