import XCTest

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

extension ValidationGalleryBrowserUITests {

  func forwardedValidationLaunchEnvironment() -> [String: String] {
    ProcessInfo.processInfo.environment.filter { key, _ in
      key.hasPrefix("XCODE_VALIDATION_GALLERY_UI_TEST_")
    }
  }

  func applyNoResultsFilter() {
    waitForFixtureBrowser()
    returnToBrowserIfNeeded()
    enterSearchQuery("definitely-no-match")
  }

  func openVideoCheckpoint() {
    waitForFixtureBrowser()
    returnToBrowserIfNeeded()
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
      enterSearchQuery("walkthrough")
      let videoItem = artifactBrowserElement(slug: "ios-ui-tests-overview-walkthrough-video", maxSwipes: 2)
      XCTAssertTrue(videoItem.exists, app.debugDescription)
      videoItem.tap()
      XCTAssertTrue(element("artifact-video-player").waitForExistence(timeout: 5), app.debugDescription)
    #endif
  }

  func openScreenshotCheckpoint() {
    if !fixtureBrowserIsReady(timeout: 2) {
      waitForFixtureBrowser()
    }
    #if os(macOS)
      openScreenshotDetail()
      XCTAssertTrue(element("artifact-detail-image").waitForExistence(timeout: 5), app.debugDescription)
    #else
      let screenshotItem = artifactBrowserElement(slug: "macos-app-tests-progress-report-base-screenshot")
      XCTAssertTrue(screenshotItem.exists, app.debugDescription)
      screenshotItem.tap()
      XCTAssertTrue(element("artifact-detail-image").waitForExistence(timeout: 5), app.debugDescription)
    #endif
  }

  func openExportSheet() {
    let previewExportButton = element("artifact-sheet-export-comments-button")
    if previewExportButton.exists || previewExportButton.waitForExistence(timeout: 1) {
      revealArtifactSheetElementIfNeeded(previewExportButton)
      activate(previewExportButton)
      XCTAssertTrue(exportSheetIsVisible(timeout: 5), app.debugDescription)
      return
    }

    let detailExportButton = element("export-screenshot-comments-button")
    XCTAssertTrue(detailExportButton.waitForExistence(timeout: 5), app.debugDescription)
    activate(detailExportButton)
    XCTAssertTrue(exportSheetIsVisible(timeout: 5), app.debugDescription)
  }

  func dismissExportSheet() {
    let cancelButton = app.buttons["Cancel"].firstMatch
    guard cancelButton.exists || cancelButton.waitForExistence(timeout: 2) else {
      return
    }
    activate(cancelButton)
    waitForUIStability()
  }

  func waitForFixtureBrowser(timeout: TimeInterval = 10) {
    #if os(macOS)
      app.activate()
      waitForUIStability()

      if fixtureBrowserIsReady(timeout: timeout) {
        return
      }

      launchApp(withFixtureBundle: true)
      XCTAssertTrue(fixtureBrowserIsReady(timeout: timeout), app.debugDescription)
    #else
      app.activate()
      waitForUIStability()

      if fixtureBrowserIsReady(timeout: timeout) {
        return
      }

      launchApp(withFixtureBundle: true)
      XCTAssertTrue(fixtureBrowserIsReady(timeout: timeout), app.debugDescription)
    #endif
  }

  func fixtureBrowserIsReady(timeout: TimeInterval) -> Bool {
    guard browserView().waitForExistence(timeout: timeout) else {
      return false
    }

    return app.searchFields["Filter artifacts"].waitForExistence(timeout: timeout)
  }

  func exportSheetIsVisible(timeout: TimeInterval) -> Bool {
    element("confirm-export-comments-button").waitForExistence(timeout: timeout)
      && element("export-apply-area-diagram-toggle").waitForExistence(timeout: timeout)
  }

  func enterSearchQuery(_ query: String) {
    clearActiveFiltersIfNeeded()

    let searchField = app.searchFields["Filter artifacts"]
    XCTAssertTrue(searchField.waitForExistence(timeout: 5), app.debugDescription)
    app.activate()
    waitForUIStability()
    #if os(macOS)
      searchField.click()
      replaceText(in: searchField, with: query)
    #else
      searchField.tap()
      searchField.typeText(query)
    #endif
  }

  func clearActiveFiltersIfNeeded() {
    let clearFiltersButton = element("clear-filters-button")
    guard clearFiltersButton.exists || clearFiltersButton.waitForExistence(timeout: 0.5) else {
      return
    }

    #if os(macOS)
      clearFiltersButton.click()
    #else
      clearFiltersButton.tap()
    #endif
    waitForUIStability()
  }

  func artifactBrowserElement(
    slug: String,
    maxSwipes: Int = 8
  ) -> XCUIElement {
    let identifiers = [
      "artifact-card-\(slug)",
      "artifact-row-\(slug)",
    ]
    let browser = browserView()

    for swipe in 0...maxSwipes {
      for identifier in identifiers {
        let candidate = element(identifier)
        let waitTimeout = swipe == 0 ? 1.0 : 0.2
        if candidate.exists || candidate.waitForExistence(timeout: waitTimeout) {
          return candidate
        }
      }

      if swipe < maxSwipes {
        browser.swipeUp()
        waitForUIStability()
      }
    }

    return element(identifiers[0])
  }

  func makeExportDirectory() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  func waitForExportRoot(in exportDirectory: URL, timeout: TimeInterval = 5) -> URL? {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if
        let child = try? FileManager.default.contentsOfDirectory(
          at: exportDirectory,
          includingPropertiesForKeys: [.isDirectoryKey],
          options: [.skipsHiddenFiles]
        ).first
      {
        return child
      }

      Thread.sleep(forTimeInterval: 0.1)
    }

    return nil
  }

  func waitForCompletedExportRoot(
    in exportDirectory: URL,
    existingHomeExportRoots: Set<String>,
    timeout: TimeInterval = 5
  ) throws -> URL {
    let deadline = Date().addingTimeInterval(timeout)
    #if os(macOS)
      var savePanelHandled = false
    #endif

    while Date() < deadline {
      #if os(macOS)
        if savePanelHandled == false, confirmNativeSavePanelIfPresentNow() {
          savePanelHandled = true
        }

        if let homeExportRoot = newHomeExportRoot(excluding: existingHomeExportRoots) {
          return homeExportRoot
        }
      #endif

      if let exportRoot = currentExportRoot(in: exportDirectory) {
        return exportRoot
      }

      Thread.sleep(forTimeInterval: 0.1)
    }

    return try XCTUnwrap(
      nil as URL?,
      "Expected an exported comments directory to be created. \(app.debugDescription)"
    )
  }

  func homeExportRootNames() -> Set<String> {
    #if os(macOS)
    let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
    let urls =
      (try? FileManager.default.contentsOfDirectory(
        at: homeDirectory,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      )) ?? []

    return Set(
      urls
        .filter { $0.lastPathComponent.hasPrefix("validation-comments-") }
        .map(\.lastPathComponent)
    )
    #else
      []
    #endif
  }

  func newHomeExportRoot(excluding existingRootNames: Set<String>) -> URL? {
    #if os(macOS)
    let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
    let urls =
      (try? FileManager.default.contentsOfDirectory(
        at: homeDirectory,
        includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
        options: [.skipsHiddenFiles]
      )) ?? []

    let candidates = urls.filter { url in
      url.lastPathComponent.hasPrefix("validation-comments-")
        && existingRootNames.contains(url.lastPathComponent) == false
    }

    return candidates.max(by: { lhs, rhs in
      let lhsDate =
        (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        ?? .distantPast
      let rhsDate =
        (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        ?? .distantPast
      return lhsDate < rhsDate
    })
    #else
      nil
    #endif
  }

  #if os(macOS)
    func confirmNativeSavePanelIfPresentNow() -> Bool {
      var savePanel = app.dialogs.matching(identifier: "save-panel").firstMatch
      if !savePanel.exists {
        savePanel = app.windows.matching(identifier: "save-panel").firstMatch
      }
      guard savePanel.exists else {
        return false
      }

      let exportButtonCandidates = [
        savePanel.buttons["Export"],
        savePanel.buttons["OKButton"],
        app.buttons["Export"],
        app.buttons["OKButton"],
      ]

      for candidate in exportButtonCandidates where candidate.exists || candidate.waitForExistence(timeout: 1) {
        candidate.click()
        waitForUIStability()
        return true
      }

      XCTFail("Expected a confirm button in the save panel. \(app.debugDescription)")
      return true
    }
  #endif

  func currentExportRoot(in exportDirectory: URL) -> URL? {
    try? FileManager.default.contentsOfDirectory(
      at: exportDirectory,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    ).first
  }

  func exportCommentEntries(at manifestURL: URL) throws -> [[String: Any]] {
    let manifestData = try Data(contentsOf: manifestURL)
    let manifestObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
      "Expected comments manifest dictionary."
    )
    return try XCTUnwrap(manifestObject["comments"] as? [[String: Any]], "Expected comments array in manifest.")
  }

  func activate(_ element: XCUIElement) {
    XCTAssertTrue(element.waitForExistence(timeout: 5), app.debugDescription)
    #if os(macOS)
      element.click()
    #else
      element.tap()
    #endif
  }

  func activateCoordinate(
    in element: XCUIElement,
    normalizedOffset: CGVector
  ) {
    let coordinate = element.coordinate(withNormalizedOffset: normalizedOffset)
    #if os(macOS)
      coordinate.click()
    #else
      coordinate.tap()
    #endif
  }

  func enterEditorText(_ element: XCUIElement, text: String) {
    #if os(macOS)
      replaceText(in: element, with: text)
    #else
      activate(element)
      element.typeText(text)
    #endif
  }

  func returnToBrowserIfNeeded() {
    dismissArtifactSheetIfNeeded()

    #if os(iOS)
      if browserView().exists {
        return
      }

      let backButton = app.navigationBars.buttons.firstMatch
      if backButton.exists || backButton.waitForExistence(timeout: 1) {
        backButton.tap()
        waitForUIStability()
      }
    #endif
  }

}
