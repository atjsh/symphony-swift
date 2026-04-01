import XCTest

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

extension XcodeValidationGalleryAppUITests {

  func testCanCreatePointCommentAndExportScreenshotComments() throws {
    let exportDirectory = try makeExportDirectory()
    let existingHomeExportRoots = homeExportRootNames()
    launchApp(withFixtureBundle: true, exportDirectory: exportDirectory)
    openScreenshotCheckpoint()

    triggerCommentAction(named: "Add Point Comment")

    let preview = element("artifact-full-size-preview")
    XCTAssertTrue(preview.waitForExistence(timeout: 5), app.debugDescription)
    #if os(macOS)
      preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).click()
    #else
      preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
    #endif

    let draftEditor = element("comment-draft-editor")
    XCTAssertTrue(draftEditor.waitForExistence(timeout: 5), app.debugDescription)
    enterEditorText(draftEditor, text: "This title should be bold.")

    let saveCommentButton = element("save-comment-button")
    XCTAssertTrue(saveCommentButton.waitForExistence(timeout: 5), app.debugDescription)
    activate(saveCommentButton)
    waitForUIStability()

    let exportButton = element("artifact-sheet-export-comments-button")
    XCTAssertTrue(exportButton.waitForExistence(timeout: 5), app.debugDescription)
    activate(exportButton)

    XCTAssertTrue(exportSheetIsVisible(timeout: 5), app.debugDescription)
    #if os(macOS)
      XCTAssertTrue(app.colorWells.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
    #else
      XCTAssertTrue(element("export-annotation-color-picker").waitForExistence(timeout: 5), app.debugDescription)
    #endif
    XCTAssertFalse(element("export-annotation-color-blue").exists, app.debugDescription)
    activate(element("confirm-export-comments-button"))

    let exportRoot = try waitForCompletedExportRoot(
      in: exportDirectory,
      existingHomeExportRoots: existingHomeExportRoots
    )
    addTeardownBlock {
      try? FileManager.default.removeItem(at: exportRoot)
    }
    let manifestURL = exportRoot.appendingPathComponent("comments.json")
    let commentEntry = try XCTUnwrap(exportCommentEntries(at: manifestURL).first)
    XCTAssertEqual(commentEntry["comment"] as? String, "This title should be bold.")
    XCTAssertEqual(commentEntry["annotation_color"] as? String, "red")
    XCTAssertEqual(commentEntry["render_applied"] as? Bool, true)
    XCTAssertTrue(FileManager.default.fileExists(atPath: exportRoot.appendingPathComponent("media/001-macos-app-tests-progress-report-base-screenshot.png").path))
  }

  func testCanCreateAreaCommentAndExportBundleCommentsWithRawMedia() throws {
    let exportDirectory = try makeExportDirectory()
    let existingHomeExportRoots = homeExportRootNames()
    launchApp(withFixtureBundle: true, exportDirectory: exportDirectory)
    openScreenshotCheckpoint()

    triggerCommentAction(named: "Add Area Comment")

    let preview = element("artifact-full-size-preview")
    XCTAssertTrue(preview.waitForExistence(timeout: 5), app.debugDescription)
    let start = preview.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.2))
    let end = preview.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5))
    start.press(forDuration: 0.1, thenDragTo: end)

    let draftEditor = element("comment-draft-editor")
    XCTAssertTrue(draftEditor.waitForExistence(timeout: 5), app.debugDescription)
    enterEditorText(draftEditor, text: "This panel should be fixed.")

    let saveCommentButton = element("save-comment-button")
    XCTAssertTrue(saveCommentButton.waitForExistence(timeout: 5), app.debugDescription)
    activate(saveCommentButton)
    waitForUIStability()

    activate(app.buttons["Close"].firstMatch)
    waitForUIStability()

    let exportBundleButton = element("export-bundle-comments-button")
    XCTAssertTrue(exportBundleButton.waitForExistence(timeout: 5), app.debugDescription)
    activate(exportBundleButton)

    XCTAssertTrue(exportSheetIsVisible(timeout: 5), app.debugDescription)
    let applyDiagramToggle = element("export-apply-area-diagram-toggle")
    XCTAssertTrue(applyDiagramToggle.waitForExistence(timeout: 5), app.debugDescription)
    activate(applyDiagramToggle)
    activate(element("confirm-export-comments-button"))

    let exportRoot = try waitForCompletedExportRoot(
      in: exportDirectory,
      existingHomeExportRoots: existingHomeExportRoots
    )
    addTeardownBlock {
      try? FileManager.default.removeItem(at: exportRoot)
    }
    let manifestURL = exportRoot.appendingPathComponent("comments.json")
    let commentEntry = try XCTUnwrap(exportCommentEntries(at: manifestURL).first)
    XCTAssertEqual(commentEntry["comment"] as? String, "This panel should be fixed.")
    XCTAssertEqual(commentEntry["render_applied"] as? Bool, false)
    let anchor = try XCTUnwrap(commentEntry["anchor"] as? [String: Any])
    XCTAssertNotNil(anchor["pixel_rect"])
    XCTAssertEqual(
      commentEntry["exported_media_filename"] as? String,
      "artifact-macos-app-tests-progress-report-base-screenshot.png"
    )
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: exportRoot.appendingPathComponent("media/artifact-macos-app-tests-progress-report-base-screenshot.png").path
      )
    )
  }

  func testDeletingCommentRequiresConfirmationAndRestoresEmptyCommentState() throws {
    launchApp(withFixtureBundle: true)
    openScreenshotCheckpoint()

    createPointComment(
      body: "Delete me",
      annotationID: 1,
      normalizedOffset: CGVector(dx: 0.50, dy: 0.30)
    )

    let deleteCommentButton = element("delete-comment-button")
    XCTAssertTrue(deleteCommentButton.waitForExistence(timeout: 5), app.debugDescription)
    activate(deleteCommentButton)

    let confirmDeleteButton = element("confirm-delete-comment-button")
    XCTAssertTrue(confirmDeleteButton.waitForExistence(timeout: 5), app.debugDescription)
    activate(confirmDeleteButton)

    XCTAssertTrue(element("comment-list-empty-state").waitForExistence(timeout: 5), app.debugDescription)
    XCTAssertFalse(element("comment-row-1").exists, app.debugDescription)
  }

  func testClosingDraftCommentRequiresDiscardConfirmation() throws {
    launchApp(withFixtureBundle: true)
    openScreenshotCheckpoint()

    triggerCommentAction(named: "Add Point Comment")

    let preview = element("artifact-full-size-preview")
    XCTAssertTrue(preview.waitForExistence(timeout: 5), app.debugDescription)
    #if os(macOS)
      preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).click()
    #else
      preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
    #endif

    let draftEditor = element("comment-draft-editor")
    XCTAssertTrue(draftEditor.waitForExistence(timeout: 5), app.debugDescription)

    activate(element("artifact-sheet-close-button"))

    let keepEditingButton = element("keep-editing-comment-button")
    XCTAssertTrue(keepEditingButton.waitForExistence(timeout: 5), app.debugDescription)
    activate(keepEditingButton)
    XCTAssertTrue(draftEditor.waitForExistence(timeout: 5), app.debugDescription)

    activate(element("artifact-sheet-close-button"))

    let discardButton = element("confirm-discard-comment-button")
    XCTAssertTrue(discardButton.waitForExistence(timeout: 5), app.debugDescription)
    activate(discardButton)

    XCTAssertFalse(draftEditor.waitForExistence(timeout: 1), app.debugDescription)
    XCTAssertFalse(element("artifact-full-size-preview").exists, app.debugDescription)
  }

  func testCommentSheetUsesCompactHeaderActionsOnPhone() throws {
    #if os(iOS)
      launchApp(withFixtureBundle: true)
      openScreenshotCheckpoint()

      triggerCommentAction(named: "Add Point Comment")

      XCTAssertTrue(element("artifact-sheet-compact-actions").waitForExistence(timeout: 5), app.debugDescription)
      XCTAssertTrue(element("artifact-sheet-export-comments-button").waitForExistence(timeout: 5), app.debugDescription)
      XCTAssertTrue(element("artifact-sheet-close-button").waitForExistence(timeout: 5), app.debugDescription)
    #else
      throw XCTSkip("iPhone compact action layout is iOS-only.")
    #endif
  }

  func testCompactArtifactSelectionPushesToDetailPage() throws {
    #if !os(macOS)
      launchApp(withFixtureBundle: true)

      let screenshotItem = artifactBrowserElement(slug: "macos-app-tests-progress-report-base-screenshot")
      XCTAssertTrue(screenshotItem.waitForExistence(timeout: 5), app.debugDescription)
      activate(screenshotItem)

      XCTAssertTrue(element("artifact-detail-view").waitForExistence(timeout: 5), app.debugDescription)
      XCTAssertTrue(app.navigationBars["Progress Report"].waitForExistence(timeout: 5), app.debugDescription)
      XCTAssertTrue(app.buttons["BackButton"].waitForExistence(timeout: 5), app.debugDescription)
    #else
      throw XCTSkip("Dedicated compact detail navigation is not used on macOS.")
    #endif
  }

  func testFixtureBundleShowsNoResultsStateAndClearsFilter() throws {
    launchApp(withFixtureBundle: true)

    let searchField = app.searchFields["Filter artifacts"]
    XCTAssertTrue(searchField.waitForExistence(timeout: 5), app.debugDescription)
    app.activate()
    waitForUIStability()
    #if os(macOS)
      searchField.click()
    #else
      searchField.tap()
    #endif
    #if os(macOS)
      replaceText(in: searchField, with: "definitely-no-match")
    #else
      searchField.typeText("definitely-no-match")
    #endif

    assertNoResultsStateIsVisible()
    let clearFiltersButton = element("clear-filters-button")

    #if os(macOS)
      clearFiltersButton.click()
      XCTAssertTrue(
        element("artifact-card-macos-app-tests-progress-report-base-screenshot").waitForExistence(timeout: 5),
        app.debugDescription
      )
    #else
      clearFiltersButton.tap()
      XCTAssertTrue(
        artifactBrowserElement(slug: "macos-app-tests-progress-report-base-screenshot").exists,
        app.debugDescription
      )
    #endif
  }

  func testSidebarRowsAreDirectlyClickable() throws {
    launchApp(withFixtureBundle: true)

    let iosPlan = element("sidebar-plan-ios-ui-tests")
    XCTAssertTrue(iosPlan.waitForExistence(timeout: 5), app.debugDescription)
    #if os(macOS)
      iosPlan.click()
    #else
      iosPlan.tap()
    #endif
    waitForUIStability()
    let visibleScopeTitle = element("validation-gallery-visible-scope-title")
    XCTAssertTrue(visibleScopeTitle.waitForExistence(timeout: 5), app.debugDescription)
    XCTAssertEqual(accessibilityStringValue(of: visibleScopeTitle), "iPhone · UI Tests", app.debugDescription)
    XCTAssertTrue(
      artifactBrowserElement(slug: "ios-ui-tests-overview-top-screenshot", maxSwipes: 2).waitForExistence(timeout: 5),
      app.debugDescription
    )

    let macosPlatform = element("sidebar-platform-macos")
    XCTAssertTrue(macosPlatform.waitForExistence(timeout: 5), app.debugDescription)
    #if os(macOS)
      macosPlatform.click()
    #else
      macosPlatform.tap()
    #endif
    waitForUIStability()
    XCTAssertEqual(accessibilityStringValue(of: visibleScopeTitle), "macOS", app.debugDescription)
    XCTAssertTrue(
      artifactBrowserElement(slug: "macos-app-tests-progress-report-base-screenshot", maxSwipes: 2).waitForExistence(timeout: 5),
      app.debugDescription
    )
  }

  #if os(macOS)
    func testInspectorPreviewSurfaceOpensFullSizeSheet() throws {
      launchApp(withFixtureBundle: true)
      openScreenshotDetail()

      let preview = element("artifact-detail-image")
      XCTAssertTrue(preview.waitForExistence(timeout: 5), app.debugDescription)
      preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()

      XCTAssertTrue(element("artifact-full-size-preview").waitForExistence(timeout: 5), app.debugDescription)
    }
  #endif

  func testRichMediaWalkthroughCapturesValidationGallerySurfaces() throws {
    launchApp()
    assertEmptyStateIsVisible()
    captureCheckpoint(named: "empty-state-root")

    launchApp(withFixtureBundle: true)

    captureCheckpoint(named: "root")
    openScreenshotCheckpoint()
    captureCheckpoint(named: "screenshot-detail")

    #if os(macOS)
      artifactPreviewButton("macos-app-tests-progress-report-base-screenshot").click()
      XCTAssertTrue(element("artifact-full-size-preview").waitForExistence(timeout: 5), app.debugDescription)
      captureCheckpoint(named: "full-size-preview")
      dismissArtifactSheetIfNeeded()
    #endif

    captureCommentAuthoringWalkthrough()
    openExportSheet()
    captureCheckpoint(surface: "export-sheet", variant: "with-comments")
    dismissExportSheet()
    dismissArtifactSheetIfNeeded()

    returnToBrowserIfNeeded()
    openVideoCheckpoint()
    captureCheckpoint(named: "video-detail")

    returnToBrowserIfNeeded()
    applyNoResultsFilter()
    assertNoResultsStateIsVisible()
    captureCheckpoint(named: "no-results")
  }

  func testAccessibilityAuditCoversRequiredCheckpoints() throws {
    launchApp()
    assertEmptyStateIsVisible()
    try assertAccessibilityAuditPasses(named: "empty-state-root")

    launchApp(withFixtureBundle: true)

    try assertAccessibilityAuditPasses(named: "root")
    resetFixtureStateAfterAccessibilityAuditIfNeeded()
    openScreenshotCheckpoint()
    try assertAccessibilityAuditPasses(named: "screenshot-detail")
    openExportSheet()
    try assertAccessibilityAuditPasses(named: "export-sheet")

    resetFixtureStateAfterAccessibilityAuditIfNeeded()
    applyNoResultsFilter()
    assertNoResultsStateIsVisible()
    try assertAccessibilityAuditPasses(named: "no-results")
  }
}
