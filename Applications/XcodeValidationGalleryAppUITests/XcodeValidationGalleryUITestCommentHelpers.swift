import XCTest

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

extension XcodeValidationGalleryAppUITests {

  func captureCommentAuthoringWalkthrough() {
    createPointComment(
      body: "Point marker",
      annotationID: 1,
      normalizedOffset: CGVector(dx: 0.50, dy: 0.30),
      modeCheckpoint: "comment-point-mode",
      enteredCheckpoint: "comment-point-entered",
      savedCheckpoint: "comment-point-saved"
    )
    #if !os(macOS)
      dismissArtifactSheetIfNeeded()
    #endif

    createAreaComment(
      body: "Area selection",
      annotationID: 2,
      startOffset: CGVector(dx: 0.20, dy: 0.20),
      endOffset: CGVector(dx: 0.55, dy: 0.50),
      modeCheckpoint: "comment-area-mode",
      enteredCheckpoint: "comment-area-entered",
      savedCheckpoint: "comment-area-saved"
    )
    #if !os(macOS)
      dismissArtifactSheetIfNeeded()
    #endif

    createPointComment(
      body: "List coverage",
      annotationID: 3,
      normalizedOffset: CGVector(dx: 0.74, dy: 0.68)
    )

    focusCommentList(on: 1)
    captureCheckpoint(surface: "comment-list", variant: "top")

    focusCommentList(on: 3)
    captureCheckpoint(surface: "comment-list", variant: "bottom")
  }

  func createPointComment(
    body: String,
    annotationID: Int,
    normalizedOffset: CGVector,
    modeCheckpoint: String? = nil,
    enteredCheckpoint: String? = nil,
    savedCheckpoint: String? = nil
  ) {
    triggerCommentAction(named: "Add Point Comment")
    assertCommentAuthoringStateIsVisible()
    if let modeCheckpoint {
      XCTAssertTrue(element("comment-mode-banner").waitForExistence(timeout: 5), app.debugDescription)
      captureCheckpoint(named: modeCheckpoint)
    }

    let preview = element("artifact-full-size-preview")
    XCTAssertTrue(preview.waitForExistence(timeout: 5), app.debugDescription)
    activateCoordinate(in: preview, normalizedOffset: normalizedOffset)

    let draftEditor = element("comment-draft-editor")
    XCTAssertTrue(draftEditor.waitForExistence(timeout: 5), app.debugDescription)
    enterEditorText(draftEditor, text: body)
    if let enteredCheckpoint {
      captureCheckpoint(named: enteredCheckpoint)
    }

    saveDraftComment()
    assertSavedComment(annotationID: annotationID)
    if let savedCheckpoint {
      captureCheckpoint(named: savedCheckpoint)
    }
  }

  func createAreaComment(
    body: String,
    annotationID: Int,
    startOffset: CGVector,
    endOffset: CGVector,
    modeCheckpoint: String? = nil,
    enteredCheckpoint: String? = nil,
    savedCheckpoint: String? = nil
  ) {
    triggerCommentAction(named: "Add Area Comment")
    assertCommentAuthoringStateIsVisible()
    if let modeCheckpoint {
      XCTAssertTrue(element("comment-mode-banner").waitForExistence(timeout: 5), app.debugDescription)
      captureCheckpoint(named: modeCheckpoint)
    }

    let preview = element("artifact-full-size-preview")
    XCTAssertTrue(preview.waitForExistence(timeout: 5), app.debugDescription)
    let start = preview.coordinate(withNormalizedOffset: startOffset)
    let end = preview.coordinate(withNormalizedOffset: endOffset)
    start.press(forDuration: 0.1, thenDragTo: end)

    let draftEditor = element("comment-draft-editor")
    XCTAssertTrue(draftEditor.waitForExistence(timeout: 5), app.debugDescription)
    enterEditorText(draftEditor, text: body)
    if let enteredCheckpoint {
      captureCheckpoint(named: enteredCheckpoint)
    }

    saveDraftComment()
    assertSavedComment(annotationID: annotationID)
    if let savedCheckpoint {
      captureCheckpoint(named: savedCheckpoint)
    }
  }

  func assertCommentAuthoringStateIsVisible() {
    XCTAssertTrue(element("artifact-sheet-scroll-view").waitForExistence(timeout: 5), app.debugDescription)
    XCTAssertTrue(element("comment-list-container").waitForExistence(timeout: 5), app.debugDescription)
  }

  func saveDraftComment() {
    let saveCommentButton = element("save-comment-button")
    XCTAssertTrue(saveCommentButton.waitForExistence(timeout: 5), app.debugDescription)
    activate(saveCommentButton)
    waitForUIStability()
  }

  func assertSavedComment(annotationID: Int) {
    XCTAssertTrue(element("comment-overlay-\(annotationID)").waitForExistence(timeout: 5), app.debugDescription)
    XCTAssertTrue(element("comment-row-\(annotationID)").waitForExistence(timeout: 5), app.debugDescription)
  }

  func focusCommentList(on annotationID: Int) {
    let targetRow = element("comment-row-\(annotationID)")
    XCTAssertTrue(element("artifact-sheet-scroll-view").waitForExistence(timeout: 5), app.debugDescription)
    XCTAssertTrue(element("comment-list-container").waitForExistence(timeout: 5), app.debugDescription)

    for _ in 0..<6 where targetRow.isHittable == false {
      #if os(macOS)
        element("artifact-sheet-scroll-view").swipeUp()
      #else
        element("artifact-sheet-scroll-view").swipeUp()
      #endif
      waitForUIStability()
    }

    XCTAssertTrue(targetRow.waitForExistence(timeout: 5), app.debugDescription)
  }

  func revealArtifactSheetElementIfNeeded(_ targetElement: XCUIElement) {
    #if !os(macOS)
      guard targetElement.isHittable == false else {
        return
      }

      let artifactSheet = element("artifact-sheet-scroll-view")
      guard artifactSheet.exists || artifactSheet.waitForExistence(timeout: 1) else {
        return
      }

      for _ in 0..<6 where targetElement.isHittable == false {
        artifactSheet.swipeDown()
        waitForUIStability()
      }
    #endif
  }

  func dismissArtifactSheetIfNeeded() {
    let closeButton = app.buttons["Close"].firstMatch
    if closeButton.exists || closeButton.waitForExistence(timeout: 1) {
      activate(closeButton)
      waitForUIStability()
      return
    }

    #if os(macOS)
      if element("artifact-sheet-scroll-view").exists || element("artifact-full-size-preview").exists {
        app.typeKey(.escape, modifierFlags: [])
        waitForUIStability()
      }
    #endif
  }

  func waitForApplicationToTerminate(
    _ application: XCUIApplication,
    timeout: TimeInterval = 5
  ) {
    let deadline = Date().addingTimeInterval(timeout)
    while application.state != .notRunning, Date() < deadline {
      Thread.sleep(forTimeInterval: 0.1)
    }
  }

  #if os(macOS)
    func resetFixtureStateAfterAccessibilityAuditIfNeeded() {
      launchApp(withFixtureBundle: true)
    }

    func ensureMainWindowIsVisible() {
      if app.windows.firstMatch.exists || app.windows.firstMatch.waitForExistence(timeout: 1) {
        return
      }

      app.activate()
      waitForUIStability()
      app.typeKey("n", modifierFlags: .command)
      waitForUIStability()

      if app.windows.firstMatch.exists || app.windows.firstMatch.waitForExistence(timeout: 1) {
        return
      }

      let fileMenu = app.menuBars.menuBarItems["File"].firstMatch
      guard fileMenu.exists || fileMenu.waitForExistence(timeout: 2) else {
        return
      }

      fileMenu.click()
      let newWindowItem = app.menuItems["New Window"].firstMatch
      guard newWindowItem.exists || newWindowItem.waitForExistence(timeout: 2) else {
        app.typeKey(.escape, modifierFlags: [])
        return
      }

      newWindowItem.click()
      waitForUIStability()
    }

    func hasCommentActionControls() -> Bool {
      if element("add-point-comment-button").waitForExistence(timeout: 1) {
        return element("add-area-comment-button").exists
      }

      return element("add-comment-menu").waitForExistence(timeout: 1)
    }

    func openScreenshotDetail() {
      waitForFixtureBrowser()

      let screenshotCard = element("artifact-card-macos-app-tests-progress-report-base-screenshot")
      XCTAssertTrue(screenshotCard.waitForExistence(timeout: 10), app.debugDescription)
      app.activate()
      waitForUIStability()
      screenshotCard.click()
      XCTAssertTrue(artifactPreviewButton("macos-app-tests-progress-report-base-screenshot").waitForExistence(timeout: 5), app.debugDescription)
    }

    func artifactPreviewButton(_ slug: String) -> XCUIElement {
      element("artifact-preview-\(slug)")
    }

    func triggerCommentAction(named title: String) {
      let directButtonIdentifier = title == "Add Point Comment"
        ? "add-point-comment-button"
        : "add-area-comment-button"
      let directButton = element(directButtonIdentifier)
      if directButton.waitForExistence(timeout: 1) {
        directButton.click()
        return
      }

      app.activate()
      waitForUIStability()
      app.typeKey(
        ";",
        modifierFlags: title == "Add Point Comment" ? .command : [.command, .shift]
      )
      waitForUIStability()
      if element("artifact-full-size-preview").exists || element("comment-draft-editor").exists {
        return
      }

      let menuButton = element("add-comment-menu")
      XCTAssertTrue(menuButton.waitForExistence(timeout: 5), app.debugDescription)
      menuButton.click()
      let menuItem = app.menuItems[title].firstMatch
      if menuItem.waitForExistence(timeout: 2) {
        menuItem.click()
        return
      }
    }

    func replaceText(in element: XCUIElement, with text: String) {
      XCTAssertTrue(element.waitForExistence(timeout: 5), app.debugDescription)
      element.click()
      app.typeKey("a", modifierFlags: .command)
      app.typeKey(.delete, modifierFlags: [])
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)
      app.typeKey("v", modifierFlags: .command)
      waitForUIStability()
    }
  #endif

  #if !os(macOS)
    func resetFixtureStateAfterAccessibilityAuditIfNeeded() {}

    func triggerCommentAction(named title: String) {
      let menuButton = element("add-comment-menu")
      XCTAssertTrue(menuButton.waitForExistence(timeout: 5), app.debugDescription)
      revealArtifactSheetElementIfNeeded(menuButton)
      activate(menuButton)

      let actionButton = app.buttons[title].firstMatch
      XCTAssertTrue(actionButton.waitForExistence(timeout: 5), app.debugDescription)
      activate(actionButton)
    }
  #endif

  func accessibilityStringValue(of element: XCUIElement) -> String {
    if let value = element.value as? String, value.isEmpty == false {
      return value
    }

    return element.label
  }

  func accessibilityValueString(of element: XCUIElement) -> String? {
    guard let value = element.value as? String, value.isEmpty == false else {
      return nil
    }

    return value
  }

  static func isolatedDefaultsSuiteName(for testName: String) -> String {
    let sanitizedTestName = testName
      .map { $0.isLetter || $0.isNumber ? $0 : "-" }
      .reduce(into: "") { partialResult, character in
        partialResult.append(character)
      }

    return "dev.atjsh.xcode-validation-gallery.ui-tests.\(sanitizedTestName)"
  }

  static func clearDefaultsSuite(named suiteName: String) {
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      return
    }

    defaults.removePersistentDomain(forName: suiteName)
  }
}
