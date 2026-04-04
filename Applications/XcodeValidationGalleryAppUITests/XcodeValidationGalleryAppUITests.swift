import XCTest

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

@MainActor
final class XcodeValidationGalleryAppUITests: XCTestCase {
  var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = false
    #if os(macOS)
      NSPasteboard.general.clearContents()
    #endif
    Self.clearDefaultsSuite(named: Self.isolatedDefaultsSuiteName(for: name))
  }

  func testLaunchShowsEmptyState() throws {
    launchApp()

    assertEmptyStateIsVisible()
  }

  func testEmptyStateImportButtonsTriggerImportRequests() throws {
    launchApp(captureImportRequests: true)

    let openBundleButton = element("open-validation-bundle-button")
    XCTAssertTrue(openBundleButton.waitForExistence(timeout: 5), app.debugDescription)
    #if os(macOS)
      openBundleButton.click()
    #else
      openBundleButton.tap()
    #endif
    XCTAssertTrue(importRequestMarker().waitForExistence(timeout: 5), app.debugDescription)
    XCTAssertEqual(accessibilityStringValue(of: importRequestMarker()), "bundle", app.debugDescription)

    let openManifestButton = element("open-manifest-button")
    XCTAssertTrue(openManifestButton.waitForExistence(timeout: 5), app.debugDescription)
    #if os(macOS)
      openManifestButton.click()
    #else
      openManifestButton.tap()
    #endif
    XCTAssertEqual(accessibilityStringValue(of: importRequestMarker()), "manifest", app.debugDescription)
  }

  func testToolbarImportButtonsTriggerImportRequests() throws {
    launchApp(captureImportRequests: true)

    let openBundleButton = element("toolbar-open-validation-bundle-button")
    XCTAssertTrue(openBundleButton.waitForExistence(timeout: 5), app.debugDescription)
    #if os(macOS)
      openBundleButton.click()
    #else
      openBundleButton.tap()
    #endif
    XCTAssertTrue(importRequestMarker().waitForExistence(timeout: 5), app.debugDescription)
    XCTAssertEqual(accessibilityStringValue(of: importRequestMarker()), "bundle", app.debugDescription)

    let openManifestButton = element("toolbar-open-manifest-button")
    XCTAssertTrue(openManifestButton.waitForExistence(timeout: 5), app.debugDescription)
    #if os(macOS)
      openManifestButton.click()
    #else
      openManifestButton.tap()
    #endif
    XCTAssertEqual(accessibilityStringValue(of: importRequestMarker()), "manifest", app.debugDescription)
  }

  func testFixtureBundleLoadsAndShowsScreenshotDetail() throws {
    launchApp(withFixtureBundle: true)

    #if os(macOS)
      let screenshotCard = element("artifact-card-macos-app-tests-progress-report-base-screenshot")
      XCTAssertTrue(screenshotCard.waitForExistence(timeout: 5), app.debugDescription)
      XCTAssertTrue(element("artifact-detail-image").waitForExistence(timeout: 5), app.debugDescription)
      XCTAssertTrue(
        element("artifact-preview-macos-app-tests-progress-report-base-screenshot").waitForExistence(timeout: 5),
        app.debugDescription
      )
      app.activate()
      waitForUIStability()
      screenshotCard.click()
      let previewButton = artifactPreviewButton("macos-app-tests-progress-report-base-screenshot")
      XCTAssertTrue(previewButton.waitForExistence(timeout: 5), app.debugDescription)
      previewButton.click()
      XCTAssertTrue(element("artifact-full-size-preview").waitForExistence(timeout: 5), app.debugDescription)
      app.typeKey(.escape, modifierFlags: [])
      waitForUIStability()
    #else
      let screenshotItem = artifactBrowserElement(slug: "macos-app-tests-progress-report-base-screenshot")
      XCTAssertTrue(screenshotItem.exists, app.debugDescription)
      screenshotItem.tap()
      XCTAssertTrue(element("artifact-detail-image").waitForExistence(timeout: 5), app.debugDescription)
      XCTAssertTrue(app.buttons["Open Full Size"].waitForExistence(timeout: 5), app.debugDescription)
    #endif
  }

  func testFixtureBundleLoadsAndShowsVideoDetail() throws {
    launchApp(withFixtureBundle: true)

    #if os(macOS)
      let searchField = app.searchFields["Filter artifacts"]
      XCTAssertTrue(searchField.waitForExistence(timeout: 5), app.debugDescription)
      app.activate()
      waitForUIStability()
      searchField.click()
      replaceText(in: searchField, with: "walkthrough")

      let videoCard = artifactBrowserElement(
        slug: "ios-ui-tests-overview-walkthrough-video",
        maxSwipes: 4
      )
      XCTAssertTrue(videoCard.waitForExistence(timeout: 5), app.debugDescription)
      app.activate()
      waitForUIStability()
      videoCard.click()
      XCTAssertTrue(element("artifact-video-player").waitForExistence(timeout: 5), app.debugDescription)
    #else
      openVideoCheckpoint()
      XCTAssertTrue(element("artifact-video-player").waitForExistence(timeout: 5), app.debugDescription)
    #endif
  }

  func testScreenshotDetailShowsCommentControls() throws {
    launchApp(withFixtureBundle: true)

    #if os(macOS)
      let screenshotCard = element("artifact-card-macos-app-tests-progress-report-base-screenshot")
      XCTAssertTrue(screenshotCard.waitForExistence(timeout: 5), app.debugDescription)
      app.activate()
      waitForUIStability()
      screenshotCard.click()

      XCTAssertTrue(element("add-point-comment-button").waitForExistence(timeout: 5), app.debugDescription)
      XCTAssertTrue(element("add-area-comment-button").exists, app.debugDescription)
      XCTAssertTrue(element("export-screenshot-comments-button").waitForExistence(timeout: 5), app.debugDescription)
    #else
      let screenshotItem = artifactBrowserElement(slug: "macos-app-tests-progress-report-base-screenshot")
      XCTAssertTrue(screenshotItem.exists, app.debugDescription)
      screenshotItem.tap()

      XCTAssertTrue(element("artifact-detail-image").waitForExistence(timeout: 5), app.debugDescription)
      XCTAssertTrue(element("add-comment-menu").waitForExistence(timeout: 5), app.debugDescription)
      XCTAssertTrue(element("export-screenshot-comments-button").waitForExistence(timeout: 5), app.debugDescription)
    #endif
  }

  #if os(macOS)
    func testMacWorkspaceControlsExistAndPreferWiderInspectorByDefault() throws {
      launchApp(withFixtureBundle: true)

      let displayModePicker = element("workspace-display-mode-picker")
      XCTAssertTrue(displayModePicker.waitForExistence(timeout: 5), app.debugDescription)

      let previewEmphasisPicker = element("workspace-preview-emphasis-picker")
      XCTAssertTrue(previewEmphasisPicker.waitForExistence(timeout: 5), app.debugDescription)

      let browser = element("validation-gallery-browser")
      XCTAssertTrue(browser.waitForExistence(timeout: 5), app.debugDescription)

      let inspector = element("validation-gallery-inspector")
      XCTAssertTrue(inspector.waitForExistence(timeout: 5), app.debugDescription)
      XCTAssertGreaterThan(inspector.frame.width, browser.frame.width, app.debugDescription)
    }

    func testInspectorUsesGroupedArtifactNavigationControls() throws {
      launchApp(withFixtureBundle: true)
      openScreenshotDetail()

      let navigationControls = element("artifact-navigation-controls")
      XCTAssertFalse(
        navigationControls.waitForExistence(timeout: 2),
        "Navigation controls should be hidden; only keyboard shortcuts remain."
      )

      let initialPreview = artifactPreviewButton("macos-app-tests-progress-report-base-screenshot")
      XCTAssertTrue(initialPreview.waitForExistence(timeout: 5), app.debugDescription)

      app.activate()
      waitForUIStability()
      app.typeKey("]", modifierFlags: .command)
      waitForUIStability()
      XCTAssertFalse(
        initialPreview.exists,
        "Cmd+] should navigate away from the initial artifact."
      )

      app.activate()
      waitForUIStability()
      app.typeKey("[", modifierFlags: .command)
      waitForUIStability()
      XCTAssertTrue(
        initialPreview.waitForExistence(timeout: 5),
        "Cmd+[ should navigate back to the initial artifact."
      )
    }
  #endif

  #if !os(macOS)
    func testArtifactSelectionPushesDedicatedDetailPageOnPad() throws {
      guard UIDevice.current.userInterfaceIdiom == .pad else {
        throw XCTSkip("iPad-only drill-in navigation.")
      }

      launchApp(withFixtureBundle: true)

      // Regular-width iPad uses NavigationSplitView; drill-in is compact-only.
      if element("validation-gallery-sidebar").waitForExistence(timeout: 3) {
        throw XCTSkip("Regular-width iPad uses NavigationSplitView; drill-in is compact-only.")
      }

      let screenshotItem = artifactBrowserElement(slug: "macos-app-tests-progress-report-base-screenshot")
      XCTAssertTrue(screenshotItem.waitForExistence(timeout: 5), app.debugDescription)
      screenshotItem.tap()

      XCTAssertTrue(element("artifact-detail-view").waitForExistence(timeout: 5), app.debugDescription)
      XCTAssertTrue(app.navigationBars["Progress Report"].waitForExistence(timeout: 5), app.debugDescription)
      XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
    }
  #endif

  func testCanOpenExportSheetWithoutCommentsAndKeepsFinalExportDisabled() throws {
    launchApp(withFixtureBundle: true)
    openScreenshotCheckpoint()

    openExportSheet()

    let confirmExportButton = element("confirm-export-comments-button")
    XCTAssertTrue(confirmExportButton.waitForExistence(timeout: 5), app.debugDescription)
    XCTAssertFalse(confirmExportButton.isEnabled, app.debugDescription)
  }

  func testMacWorkspaceControlsPersistAcrossLaunches() throws {
    #if os(macOS)
      launchApp(withFixtureBundle: true)

      let displayModePicker = element("workspace-display-mode-picker")
      XCTAssertTrue(displayModePicker.waitForExistence(timeout: 5), app.debugDescription)

      let previewEmphasisPicker = element("workspace-preview-emphasis-picker")
      XCTAssertTrue(previewEmphasisPicker.waitForExistence(timeout: 5), app.debugDescription)

      let listButton = element("workspace-display-mode-list-button")
      XCTAssertTrue(listButton.waitForExistence(timeout: 5), app.debugDescription)
      XCTAssertEqual(accessibilityValueString(of: listButton), "Current", app.debugDescription)

      let expandedPreviewButton = element("workspace-preview-emphasis-expanded-button")
      XCTAssertTrue(expandedPreviewButton.waitForExistence(timeout: 5), app.debugDescription)
      XCTAssertEqual(accessibilityValueString(of: expandedPreviewButton), "Current", app.debugDescription)

      let gridButton = element("workspace-display-mode-grid-button")
      XCTAssertTrue(gridButton.waitForExistence(timeout: 5), app.debugDescription)
      activate(gridButton)
      XCTAssertTrue(element("validation-gallery-browser-grid-mode").waitForExistence(timeout: 5), app.debugDescription)
      XCTAssertEqual(accessibilityValueString(of: gridButton), "Current", app.debugDescription)

      let standardPreviewButton = element("workspace-preview-emphasis-standard-button")
      XCTAssertTrue(standardPreviewButton.waitForExistence(timeout: 5), app.debugDescription)
      activate(standardPreviewButton)
      XCTAssertEqual(accessibilityValueString(of: standardPreviewButton), "Current", app.debugDescription)

      launchApp(withFixtureBundle: true)

      XCTAssertTrue(element("validation-gallery-browser-grid-mode").waitForExistence(timeout: 5), app.debugDescription)
      XCTAssertEqual(
        accessibilityValueString(of: element("workspace-display-mode-grid-button")),
        "Current",
        app.debugDescription
      )
      XCTAssertEqual(
        accessibilityValueString(of: element("workspace-preview-emphasis-standard-button")),
        "Current",
        app.debugDescription
      )
    #else
      throw XCTSkip("Workspace preferences persistence relaunch test runs on macOS only.")
    #endif
  }

  func testVideoDetailDoesNotShowCommentControls() throws {
    launchApp(withFixtureBundle: true)

    #if os(macOS)
      let searchField = app.searchFields["Filter artifacts"]
      XCTAssertTrue(searchField.waitForExistence(timeout: 5), app.debugDescription)
      app.activate()
      waitForUIStability()
      searchField.click()
      replaceText(in: searchField, with: "walkthrough")

      let videoCard = artifactBrowserElement(
        slug: "ios-ui-tests-overview-walkthrough-video",
        maxSwipes: 4
      )
      XCTAssertTrue(videoCard.waitForExistence(timeout: 5), app.debugDescription)
      app.activate()
      waitForUIStability()
      videoCard.click()

      XCTAssertFalse(element("add-comment-menu").exists, app.debugDescription)
      XCTAssertFalse(element("export-screenshot-comments-button").exists, app.debugDescription)
    #else
      openVideoCheckpoint()

      XCTAssertFalse(element("add-comment-menu").exists, app.debugDescription)
      XCTAssertFalse(element("export-screenshot-comments-button").exists, app.debugDescription)
    #endif
  }

}
