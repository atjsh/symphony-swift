import Foundation
import Testing

@testable import SymphonyValidationGallery

@Suite("ValidationGalleryCommentExportCoordinator")
@MainActor
struct ValidationGalleryCommentExportCoordinatorTests {
  @Test func coordinatorStagesRenderedManifestAndPerCommentMedia() async throws {
    let snapshot = try await ValidationBundleLoader().load(from: .folder(ValidationGalleryTestFixture.bundleRoot))
    let store = ValidationGalleryStore(
      loader: StubValidationBundleLoader(snapshot: snapshot),
      recentBundleStore: InMemoryRecentBundleStore(),
      now: { Date(timeIntervalSince1970: 60) }
    )
    let screenshot = try #require(screenshotArtifact(in: snapshot, checkpoint: "progress-report"))

    await store.open(ValidationBundleSource.folder(ValidationGalleryTestFixture.bundleRoot), rememberRecent: false)
    store.saveCommentDraft(
      ValidationGalleryCommentDraft(
        artifactID: screenshot.id,
        anchor: .point(.init(x: 0.5, y: 0.3)),
        body: "Increase the heading weight."
      ),
      for: screenshot
    )
    store.saveCommentDraft(
      ValidationGalleryCommentDraft(
        artifactID: screenshot.id,
        anchor: .area(.init(x: 0.15, y: 0.2, width: 0.25, height: 0.3)),
        body: "Tighten this block."
      ),
      for: screenshot
    )

    let coordinator = ValidationGalleryCommentExportCoordinator()
    let preparedExport = try coordinator.prepareExport(
      from: store,
      options: ValidationGalleryCommentExportOptions(
        scope: .selectedArtifact,
        applyAreaDiagram: true,
        annotationColor: .blue
      )
    )

    #expect(preparedExport.rootDirectoryName == "validation-comments-19700101-000100")
    #expect(
      preparedExport.files.map { $0.relativePath } == [
        "comments.json",
        "media/001-macos-app-tests-progress-report-base-screenshot.png",
        "media/002-macos-app-tests-progress-report-base-screenshot.png",
      ]
    )
    #expect(preparedExport.payload.comments.map { $0.annotationID } == [1, 2])
    #expect(preparedExport.payload.comments.allSatisfy { $0.annotationColor == "blue" })

    let renderedMedia = preparedExport.files.filter { $0.relativePath.hasPrefix("media/") }
    #expect(renderedMedia.count == 2)
    #expect(renderedMedia.allSatisfy { $0.data.starts(with: [0x89, 0x50, 0x4E, 0x47]) })
  }

  @Test func coordinatorStagesSharedRawMediaWhenRenderIsDisabled() async throws {
    let snapshot = try await ValidationBundleLoader().load(from: .folder(ValidationGalleryTestFixture.bundleRoot))
    let store = ValidationGalleryStore(
      loader: StubValidationBundleLoader(snapshot: snapshot),
      recentBundleStore: InMemoryRecentBundleStore(),
      now: { Date(timeIntervalSince1970: 75) }
    )
    let screenshot = try #require(screenshotArtifact(in: snapshot, checkpoint: "progress-report"))

    await store.open(ValidationBundleSource.folder(ValidationGalleryTestFixture.bundleRoot), rememberRecent: false)
    store.saveCommentDraft(
      ValidationGalleryCommentDraft(
        artifactID: screenshot.id,
        anchor: .point(.init(x: 0.35, y: 0.22)),
        body: "Increase the top margin."
      ),
      for: screenshot
    )
    store.saveCommentDraft(
      ValidationGalleryCommentDraft(
        artifactID: screenshot.id,
        anchor: .area(.init(x: 0.4, y: 0.4, width: 0.2, height: 0.2)),
        body: "Reduce this panel width."
      ),
      for: screenshot
    )

    let coordinator = ValidationGalleryCommentExportCoordinator()
    let preparedExport = try coordinator.prepareExport(
      from: store,
      options: ValidationGalleryCommentExportOptions(
        scope: .selectedArtifact,
        applyAreaDiagram: false,
        annotationColor: .red
      )
    )

    #expect(
      preparedExport.files.map { $0.relativePath } == [
        "comments.json",
        "media/artifact-macos-app-tests-progress-report-base-screenshot.png",
      ]
    )

    let rawMediaFile = try #require(preparedExport.files.first(where: { $0.relativePath.hasPrefix("media/") }))
    let sourceData = try Data(contentsOf: screenshot.fileURL)
    #expect(rawMediaFile.data == sourceData)
    #expect(preparedExport.payload.comments.allSatisfy { $0.exportedMediaFilename == rawMediaFile.relativePath.replacingOccurrences(of: "media/", with: "") })
  }
}
