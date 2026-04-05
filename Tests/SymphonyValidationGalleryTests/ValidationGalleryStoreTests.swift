import Foundation
import Testing

@testable import SymphonyValidationGallery

@Suite("ValidationGalleryStore")
@MainActor
struct ValidationGalleryStoreTests {
  @Test func storeDefaultsWorkspacePreferencesWhenNothingHasBeenSaved() {
    let store = ValidationGalleryStore(
      loader: StubValidationBundleLoader(snapshot: nil),
      recentBundleStore: InMemoryRecentBundleStore(),
      workspacePreferencesStore: InMemoryWorkspacePreferencesStore()
    )

    #expect(store.workspacePreferences == .defaults)
  }

  @Test func storeRestoresSavedWorkspacePreferencesDuringInitialization() {
    let savedPreferences = ValidationGalleryWorkspacePreferences(
      browserDisplayMode: .grid,
      macPreviewEmphasis: .standard
    )
    let store = ValidationGalleryStore(
      loader: StubValidationBundleLoader(snapshot: nil),
      recentBundleStore: InMemoryRecentBundleStore(),
      workspacePreferencesStore: InMemoryWorkspacePreferencesStore(
        workspacePreferences: savedPreferences
      )
    )

    #expect(store.workspacePreferences == savedPreferences)
  }

  @Test func storePersistsWorkspacePreferenceMutations() throws {
    let workspacePreferencesStore = InMemoryWorkspacePreferencesStore()
    let store = ValidationGalleryStore(
      loader: StubValidationBundleLoader(snapshot: nil),
      recentBundleStore: InMemoryRecentBundleStore(),
      workspacePreferencesStore: workspacePreferencesStore
    )

    store.setBrowserDisplayMode(.grid)
    store.setMacPreviewEmphasis(.standard)

    #expect(
      workspacePreferencesStore.workspacePreferences
        == ValidationGalleryWorkspacePreferences(
          browserDisplayMode: .grid,
          macPreviewEmphasis: .standard
        )
    )
    #expect(store.workspacePreferences.browserDisplayMode == .grid)
    #expect(store.workspacePreferences.macPreviewEmphasis == .standard)
  }

  @Test func storeOpenPersistsRecentBundleAndSelectsFirstVisibleArtifact() async throws {
    let snapshot = try await ValidationBundleLoader().load(from: .folder(ValidationGalleryTestFixture.bundleRoot))
    let loader = StubValidationBundleLoader(snapshot: snapshot)
    let recents = InMemoryRecentBundleStore()
    let store = ValidationGalleryStore(
      loader: loader,
      recentBundleStore: recents,
      makeBookmark: { _ in Data("bookmark".utf8) },
      resolveBookmark: { _ in
        ValidationResolvedBookmark(url: ValidationGalleryTestFixture.bundleRoot, isStale: false)
      }
    )

    await store.open(.folder(ValidationGalleryTestFixture.bundleRoot))

    #expect(store.snapshot?.summary.status == .passed)
    #expect(store.selectedArtifact?.record.checkpoint == "progress-report")
    let storedRecents = try await recents.loadRecentBundles()
    #expect(storedRecents.count == 1)
    #expect(storedRecents[0].fallbackPath == ValidationGalleryTestFixture.bundleRoot.path)
  }

  @Test func storeAppliesSidebarAndSearchFilters() async throws {
    let snapshot = try await ValidationBundleLoader().load(from: .folder(ValidationGalleryTestFixture.bundleRoot))
    let store = ValidationGalleryStore(
      loader: StubValidationBundleLoader(snapshot: snapshot),
      recentBundleStore: InMemoryRecentBundleStore(),
      searchDebounceInterval: .zero
    )

    await store.open(.folder(ValidationGalleryTestFixture.bundleRoot), rememberRecent: false)
    store.sidebarSelection = .plan(platform: "ios", plan: "ui-tests")
    store.searchText = "video"

    #expect(store.filteredArtifacts.count == 1)
    #expect(store.filteredArtifacts[0].record.artifactType == .video)
    #expect(store.selectedArtifact?.record.artifactType == .video)
  }

  @Test func storeExposesNoResultsStateAndClearFiltersRecovery() async throws {
    let snapshot = try await ValidationBundleLoader().load(from: .folder(ValidationGalleryTestFixture.bundleRoot))
    let store = ValidationGalleryStore(
      loader: StubValidationBundleLoader(snapshot: snapshot),
      recentBundleStore: InMemoryRecentBundleStore(),
      searchDebounceInterval: .zero
    )

    await store.open(.folder(ValidationGalleryTestFixture.bundleRoot), rememberRecent: false)
    store.searchText = "definitely-no-match"

    #expect(store.filteredArtifacts.isEmpty)
    #expect(store.selectedArtifact == nil)
    #expect(store.hasNoVisibleArtifacts)
    #expect(store.resultCountSummary == "No results")
    #expect(store.visibleScopeTitle == "All Artifacts")

    store.clearFilters()

    #expect(store.hasNoVisibleArtifacts == false)
    #expect(store.searchText.isEmpty)
    #expect(store.selectedArtifact != nil)
  }

  @Test func storeSurfacesSelectionFeedbackWhenFilteringChangesSelection() async throws {
    let snapshot = try await ValidationBundleLoader().load(from: .folder(ValidationGalleryTestFixture.bundleRoot))
    let store = ValidationGalleryStore(
      loader: StubValidationBundleLoader(snapshot: snapshot),
      recentBundleStore: InMemoryRecentBundleStore(),
      searchDebounceInterval: .zero
    )

    await store.open(.folder(ValidationGalleryTestFixture.bundleRoot), rememberRecent: false)
    let originalSelectionID = try #require(store.selectedArtifact?.id)

    store.searchText = "walkthrough"

    #expect(store.selectedArtifact?.id != originalSelectionID)
    #expect(store.selectionFeedback?.kind == .autoSelected)
    #expect(store.selectionFeedback?.title == "Showing the first match")
    #expect(
      store.selectionFeedback?.message
        == "The previous selection is hidden by the current filters, so Overview is now selected."
    )
  }

  @Test func storeSupportsSteppingThroughVisibleArtifacts() async throws {
    let snapshot = try await ValidationBundleLoader().load(from: .folder(ValidationGalleryTestFixture.bundleRoot))
    let store = ValidationGalleryStore(
      loader: StubValidationBundleLoader(snapshot: snapshot),
      recentBundleStore: InMemoryRecentBundleStore()
    )

    await store.open(.folder(ValidationGalleryTestFixture.bundleRoot), rememberRecent: false)
    let firstID = try #require(store.selectedArtifact?.id)

    #expect(store.selectedArtifactPositionText == "1 of \(store.filteredArtifacts.count) visible")
    #expect(store.canSelectPreviousArtifact == false)
    #expect(store.canSelectNextArtifact)

    store.selectNextArtifact()

    let nextID = try #require(store.selectedArtifact?.id)
    #expect(nextID != firstID)
    #expect(store.selectedArtifactPositionText == "2 of \(store.filteredArtifacts.count) visible")
    #expect(store.canSelectPreviousArtifact)

    store.selectPreviousArtifact()

    #expect(store.selectedArtifact?.id == firstID)
  }

  @Test func storeSurfacesStaleBookmarkRecoveryWhenRestoringRecents() async throws {
    let recents = InMemoryRecentBundleStore(
      recentBundles: [
        ValidationRecentBundle(
          kind: .folder,
          displayName: "Fixture Bundle",
          bookmarkData: Data("bookmark".utf8),
          fallbackPath: ValidationGalleryTestFixture.bundleRoot.path,
          lastOpenedAt: Date(timeIntervalSince1970: 10)
        )
      ]
    )
    let store = ValidationGalleryStore(
      loader: StubValidationBundleLoader(snapshot: nil),
      recentBundleStore: recents,
      resolveBookmark: { _ in
        ValidationResolvedBookmark(url: ValidationGalleryTestFixture.bundleRoot, isStale: true)
      }
    )

    await store.restoreLastOpenedBundle()

    #expect(store.error == .bookmarkStale("Fixture Bundle"))
  }

  @Test func storeSavesEditsDeletesAndSelectsScreenshotComments() async throws {
    let snapshot = try await ValidationBundleLoader().load(from: .folder(ValidationGalleryTestFixture.bundleRoot))
    let store = ValidationGalleryStore(
      loader: StubValidationBundleLoader(snapshot: snapshot),
      recentBundleStore: InMemoryRecentBundleStore(),
      now: { Date(timeIntervalSince1970: 10) }
    )
    let screenshot = try #require(screenshotArtifact(in: snapshot, checkpoint: "progress-report"))

    await store.open(.folder(ValidationGalleryTestFixture.bundleRoot), rememberRecent: false)
    let draft = store.makePointCommentDraft(
      at: ValidationGalleryNormalizedPoint(x: 0.5, y: 0.25),
      for: screenshot
    )

    store.saveCommentDraft(
      ValidationGalleryCommentDraft(
        artifactID: draft.artifactID,
        anchor: draft.anchor,
        body: "This title should be bold."
      ),
      for: screenshot
    )

    let savedComment = try #require(store.comments(for: screenshot).first)
    #expect(store.selectedArtifactComments.count == 1)
    #expect(store.selectedCommentID == savedComment.id)
    #expect(store.selectedArtifactComments.first?.annotationID == 1)
    #expect(savedComment.body == "This title should be bold.")

    store.updateCommentBody(savedComment.id, body: "Use a stronger title weight.", in: screenshot)
    #expect(store.comments(for: screenshot).first?.body == "Use a stronger title weight.")

    store.selectComment(savedComment.id)
    #expect(store.selectedCommentID == savedComment.id)

    store.deleteComment(savedComment.id, from: screenshot)
    #expect(store.comments(for: screenshot).isEmpty)
    #expect(store.selectedCommentID == nil)
  }

  @Test func storeReselectsVisibleCommentWhenFilteringChangesArtifactSelection() async throws {
    let snapshot = try await ValidationBundleLoader().load(from: .folder(ValidationGalleryTestFixture.bundleRoot))
    let store = ValidationGalleryStore(
      loader: StubValidationBundleLoader(snapshot: snapshot),
      recentBundleStore: InMemoryRecentBundleStore(),
      now: { Date(timeIntervalSince1970: 15) },
      searchDebounceInterval: .zero
    )
    let progressReport = try #require(screenshotArtifact(in: snapshot, checkpoint: "progress-report"))
    let logs = try #require(screenshotArtifact(in: snapshot, checkpoint: "logs"))

    await store.open(.folder(ValidationGalleryTestFixture.bundleRoot), rememberRecent: false)

    store.saveCommentDraft(
      ValidationGalleryCommentDraft(
        artifactID: progressReport.id,
        anchor: .point(.init(x: 0.5, y: 0.25)),
        body: "Keep the title comment selected."
      ),
      for: progressReport
    )
    let progressComment = try #require(store.comments(for: progressReport).first)

    store.saveCommentDraft(
      ValidationGalleryCommentDraft(
        artifactID: logs.id,
        anchor: .point(.init(x: 0.3, y: 0.45)),
        body: "Keep the logs comment selected."
      ),
      for: logs
    )
    let logsComment = try #require(store.comments(for: logs).first)

    store.selectArtifact(progressReport.id)
    store.selectComment(progressComment.id)
    #expect(store.selectedArtifact?.id == progressReport.id)
    #expect(store.selectedCommentID == progressComment.id)

    store.searchText = "logs"
    #expect(store.selectedArtifact?.id == logs.id)
    #expect(store.selectedCommentID == logsComment.id)

    store.searchText = "progress"
    #expect(store.selectedArtifact?.id == progressReport.id)
    #expect(store.selectedCommentID == progressComment.id)
  }

  @Test func storeExportsSelectedScreenshotCommentsWithIDsAndRenderedMediaDetails() async throws {
    let snapshot = try await ValidationBundleLoader().load(from: .folder(ValidationGalleryTestFixture.bundleRoot))
    let store = ValidationGalleryStore(
      loader: StubValidationBundleLoader(snapshot: snapshot),
      recentBundleStore: InMemoryRecentBundleStore(),
      now: { Date(timeIntervalSince1970: 20) }
    )
    let screenshot = try #require(screenshotArtifact(in: snapshot, checkpoint: "progress-report"))

    await store.open(.folder(ValidationGalleryTestFixture.bundleRoot), rememberRecent: false)
    store.saveCommentDraft(
      ValidationGalleryCommentDraft(
        artifactID: screenshot.id,
        anchor: .point(.init(x: 0.5, y: 0.25)),
        body: "Use a stronger title weight."
      ),
      for: screenshot
    )
    store.saveCommentDraft(
      ValidationGalleryCommentDraft(
        artifactID: screenshot.id,
        anchor: .area(.init(x: 0.1, y: 0.2, width: 0.3, height: 0.4)),
        body: "Tighten this panel spacing."
      ),
      for: screenshot
    )

    let payload = try store.exportCommentsPayload(
      options: ValidationGalleryCommentExportOptions(
        scope: .selectedArtifact,
        applyAreaDiagram: true,
        annotationColor: .green
      )
    )

    #expect(payload.bundleRootPath == snapshot.bundleRootURL.path)
    #expect(payload.manifestPath == snapshot.manifestURL.path)
    #expect(payload.exportedAt == Date(timeIntervalSince1970: 20))
    #expect(payload.comments.count == 2)

    let pointEntry = try #require(payload.comments.first(where: { $0.anchor.kind == "point" }))
    #expect(pointEntry.annotationID == 1)
    #expect(pointEntry.artifactID == screenshot.id)
    #expect(pointEntry.imagePath == screenshot.fileURL.path)
    #expect(pointEntry.imageURL == screenshot.fileURL.absoluteURL.absoluteString)
    #expect(pointEntry.exportedMediaFilename == "001-macos-app-tests-progress-report-base-screenshot.png")
    #expect(pointEntry.renderApplied)
    #expect(pointEntry.annotationColor == "green")
    #expect(pointEntry.anchor.normalizedPoint == .init(x: 0.5, y: 0.25))
    #expect(pointEntry.anchor.pixelPoint == .init(x: 480, y: 207.75))
    #expect(pointEntry.anchor.normalizedRect == nil)
    #expect(pointEntry.anchor.pixelRect == nil)

    let areaEntry = try #require(payload.comments.first(where: { $0.anchor.kind == "area" }))
    #expect(areaEntry.annotationID == 2)
    #expect(areaEntry.exportedMediaFilename == "002-macos-app-tests-progress-report-base-screenshot.png")
    #expect(areaEntry.anchor.normalizedRect == .init(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
    #expect(areaEntry.anchor.pixelRect == .init(x: 96, y: 166.2, width: 288, height: 332.4))
    #expect(areaEntry.anchor.normalizedPoint == nil)
    #expect(areaEntry.anchor.pixelPoint == nil)

    let json = try store.exportCommentsJSONString(
      options: ValidationGalleryCommentExportOptions(
        scope: .selectedArtifact,
        applyAreaDiagram: true,
        annotationColor: .green
      )
    )
    #expect(json.contains("\"bundle_root_path\""))
    #expect(json.contains("\"manifest_path\""))
    #expect(json.contains("\"comment_id\""))
    #expect(json.contains("\"annotation_id\""))
    #expect(json.contains("\"exported_media_filename\""))
    #expect(json.contains("\"annotation_color\""))
    #expect(json.contains("\"normalized_point\""))
    #expect(json.contains("\"pixel_rect\""))
  }

  @Test func storeExportsBundleCommentsSortedAndCachesThemAcrossReopen() async throws {
    let snapshot = try await ValidationBundleLoader().load(from: .folder(ValidationGalleryTestFixture.bundleRoot))
    let store = ValidationGalleryStore(
      loader: StubValidationBundleLoader(snapshot: snapshot),
      recentBundleStore: InMemoryRecentBundleStore(),
      now: { Date(timeIntervalSince1970: 30) }
    )
    let macOSScreenshot = try #require(screenshotArtifact(in: snapshot, checkpoint: "logs"))
    let iOSScreenshot = try #require(screenshotArtifact(in: snapshot, checkpoint: "overview"))

    await store.open(.folder(ValidationGalleryTestFixture.bundleRoot), rememberRecent: false)
    store.saveCommentDraft(
      ValidationGalleryCommentDraft(
        artifactID: iOSScreenshot.id,
        anchor: .point(.init(x: 0.25, y: 0.25)),
        body: "Header spacing feels off."
      ),
      for: iOSScreenshot
    )
    store.saveCommentDraft(
      ValidationGalleryCommentDraft(
        artifactID: macOSScreenshot.id,
        anchor: .point(.init(x: 0.4, y: 0.6)),
        body: "This row should align to the title."
      ),
      for: macOSScreenshot
    )

    let initialPayload = try store.exportCommentsPayload(scope: .currentBundle)
    #expect(initialPayload.comments.map(\.platform) == ["ios", "macos"])
    #expect(initialPayload.comments.map(\.annotationID) == [1, 2])
    #expect(store.hasCommentsInCurrentBundle)

    await store.open(.folder(ValidationGalleryTestFixture.bundleRoot), rememberRecent: false)

    #expect(store.comments(for: macOSScreenshot).count == 1)
    #expect(store.comments(for: iOSScreenshot).count == 1)
    #expect(store.hasCommentsInCurrentBundle)
  }

  @Test func storeOnlyEnablesCommentingForScreenshots() async throws {
    let snapshot = try await ValidationBundleLoader().load(from: .folder(ValidationGalleryTestFixture.bundleRoot))
    let store = ValidationGalleryStore(
      loader: StubValidationBundleLoader(snapshot: snapshot),
      recentBundleStore: InMemoryRecentBundleStore()
    )
    let video = try #require(snapshot.artifacts.first(where: { $0.record.artifactType == .video }))

    await store.open(.folder(ValidationGalleryTestFixture.bundleRoot), rememberRecent: false)
    store.selectArtifact(video.id)

    #expect(store.canCommentSelectedArtifact == false)
    #expect(store.selectedArtifact?.record.artifactType == .video)
    #expect(store.selectedArtifactComments.isEmpty)
  }

  @Test func storeExportsBundleCommentsFromLegacyCanonicalManifestWithoutDuplicateArtifactCrashes() async throws {
    let copiedBundle = try ValidationGalleryTestFixture.copyFixtureBundle(named: "legacy-duplicate-canonical-export")
    try ValidationGalleryTestFixture.appendDuplicateManifestArtifact(
      in: copiedBundle,
      platform: "macos",
      plan: "app-tests",
      checkpoint: "progress-report",
      artifactType: .screenshot,
      sourceResultBundle: "/tmp/final-result.xcresult"
    )

    let snapshot = try await ValidationBundleLoader().load(from: .folder(copiedBundle))
    #expect(snapshot.artifacts.count == 6)
    guard snapshot.artifacts.count == 6 else {
      return
    }

    let store = ValidationGalleryStore(
      loader: StubValidationBundleLoader(snapshot: snapshot),
      recentBundleStore: InMemoryRecentBundleStore(),
      now: { Date(timeIntervalSince1970: 40) }
    )
    let screenshot = snapshot.artifacts.first(where: {
      $0.record.platform == "macos"
        && $0.record.plan == "app-tests"
        && $0.record.checkpoint == "progress-report"
        && $0.record.artifactType == .screenshot
    })
    let requiredScreenshot = try #require(screenshot)

    await store.open(.folder(copiedBundle), rememberRecent: false)
    store.saveCommentDraft(
      ValidationGalleryCommentDraft(
        artifactID: requiredScreenshot.id,
        anchor: .point(.init(x: 0.5, y: 0.5)),
        body: "Copied comment"
      ),
      for: requiredScreenshot
    )

    let payload = try store.exportCommentsPayload(scope: .currentBundle)
    #expect(payload.comments.count == 1)
    #expect(payload.comments.first?.artifactID == requiredScreenshot.id)
    #expect(payload.comments.first?.comment == "Copied comment")
    #expect(payload.comments.first?.annotationID == 1)
  }

  @Test func storeUsesSharedRawMediaFilenamesWhenRenderedExportIsDisabled() async throws {
    let snapshot = try await ValidationBundleLoader().load(from: .folder(ValidationGalleryTestFixture.bundleRoot))
    let store = ValidationGalleryStore(
      loader: StubValidationBundleLoader(snapshot: snapshot),
      recentBundleStore: InMemoryRecentBundleStore(),
      now: { Date(timeIntervalSince1970: 50) }
    )
    let screenshot = try #require(screenshotArtifact(in: snapshot, checkpoint: "progress-report"))

    await store.open(.folder(ValidationGalleryTestFixture.bundleRoot), rememberRecent: false)
    store.saveCommentDraft(
      ValidationGalleryCommentDraft(
        artifactID: screenshot.id,
        anchor: .point(.init(x: 0.25, y: 0.25)),
        body: "Strengthen the card title."
      ),
      for: screenshot
    )
    store.saveCommentDraft(
      ValidationGalleryCommentDraft(
        artifactID: screenshot.id,
        anchor: .area(.init(x: 0.4, y: 0.2, width: 0.2, height: 0.2)),
        body: "Reduce this empty space."
      ),
      for: screenshot
    )

    let payload = try store.exportCommentsPayload(
      options: ValidationGalleryCommentExportOptions(
        scope: .selectedArtifact,
        applyAreaDiagram: false,
        annotationColor: .red
      )
    )

    #expect(payload.comments.count == 2)
    #expect(payload.comments.allSatisfy { $0.renderApplied == false })
    #expect(Set(payload.comments.map(\.exportedMediaFilename)).count == 1)
    #expect(payload.comments.first?.exportedMediaFilename == "artifact-macos-app-tests-progress-report-base-screenshot.png")
  }
}
