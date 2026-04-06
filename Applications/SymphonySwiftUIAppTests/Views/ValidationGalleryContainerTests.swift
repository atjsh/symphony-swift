// swiftlint:disable force_try
import Foundation
import Testing

import SymphonyValidationGallery
@testable import SymphonySwiftUIApp

@Suite("ValidationGalleryContainer")
struct ValidationGalleryContainerTests {
  @Test func bundledFixtureBootstrapActionUsesBundledFixtureSource() {
    let fixtureURL = URL(fileURLWithPath: "/tmp/XcodeValidationGalleryFixture", isDirectory: true)
    let action = ValidationGalleryBootstrapResolver.resolve(
      arguments: ["--ui-testing"],
      environment: ["XCODE_VALIDATION_GALLERY_UI_TEST_USE_BUNDLED_FIXTURE": "1"],
      bundledFixtureSource: .folder(fixtureURL)
    )

    #expect(action == .open(.folder(fixtureURL), rememberRecent: false))
  }

  @Test func explicitBundlePathOverridesBundledFixtureFlag() {
    let bundleURL = URL(fileURLWithPath: "/tmp/custom-bundle", isDirectory: true)
    let action = ValidationGalleryBootstrapResolver.resolve(
      arguments: ["--ui-testing"],
      environment: [
        "XCODE_VALIDATION_GALLERY_UI_TEST_BUNDLE_PATH": bundleURL.path,
        "XCODE_VALIDATION_GALLERY_UI_TEST_USE_BUNDLED_FIXTURE": "1",
      ],
      bundledFixtureSource: .folder(URL(fileURLWithPath: "/tmp/fixture", isDirectory: true))
    )

    switch action {
    case .open(.folder(let resolvedURL), let rememberRecent):
      #expect(resolvedURL.path == bundleURL.path)
      #expect(rememberRecent == false)
    default:
      Issue.record("Expected the explicit bundle path to override the bundled fixture flag.")
    }
  }

  @Test func uiTestingWithoutSeedSkipsRestoreFlow() {
    let action = ValidationGalleryBootstrapResolver.resolve(
      arguments: ["--ui-testing"],
      environment: [:],
      bundledFixtureSource: nil
    )

    #expect(action == .none)
  }

  @Test func regularLaunchRestoresLastOpenedBundleWhenNoExplicitSeedIsProvided() {
    let action = ValidationGalleryBootstrapResolver.resolve(
      arguments: [],
      environment: [:],
      bundledFixtureSource: nil
    )

    #expect(action == .restoreLastOpenedBundle)
  }

  @MainActor
  @Test func importControllerCapturesRequestsWithoutPresentingImporterDuringUiTesting() {
    let controller = ValidationGalleryImportController(
      environment: ["XCODE_VALIDATION_GALLERY_UI_TEST_CAPTURE_IMPORT_REQUESTS": "1"]
    )

    controller.request(.bundle)
    #expect(controller.capturesRequests)
    #expect(controller.requestedImportKind == .bundle)
    #expect(controller.isBundleImporterPresented == false)
    #expect(controller.isManifestImporterPresented == false)

    controller.request(.manifest)
    #expect(controller.requestedImportKind == .manifest)
    #expect(controller.isBundleImporterPresented == false)
    #expect(controller.isManifestImporterPresented == false)
  }

  @MainActor
  @Test func importControllerPresentsAndClearsRequestedImporterInRegularMode() {
    let controller = ValidationGalleryImportController(environment: [:])

    controller.request(.bundle)
    #expect(controller.requestedImportKind == .bundle)
    #expect(controller.isBundleImporterPresented)
    #expect(controller.isManifestImporterPresented == false)

    controller.complete(.bundle)
    #expect(controller.isBundleImporterPresented == false)

    controller.request(.manifest)
    #expect(controller.requestedImportKind == .manifest)
    #expect(controller.isManifestImporterPresented)
    #expect(controller.isBundleImporterPresented == false)

    controller.complete(.manifest)
    #expect(controller.isManifestImporterPresented == false)
  }

  @MainActor
  @Test func exportControllerRequestsDefaultSelectedArtifactOptions() {
    let controller: ValidationGalleryExportController
    #if os(macOS)
      controller = ValidationGalleryExportController(
        environment: [:],
        exportCoordinator: StubExportCoordinator(),
        folderSaver: StubExportSaver(resultURL: URL(fileURLWithPath: "/tmp/exported-comments", isDirectory: true))
      )
    #else
      controller = ValidationGalleryExportController(
        environment: [:],
        exportCoordinator: StubExportCoordinator()
      )
    #endif

    controller.requestExport(scope: .selectedArtifact)

    #expect(controller.request?.options.scope == .selectedArtifact)
    #expect(controller.request?.options.applyAreaDiagram == true)
    #expect(controller.request?.options.annotationColor == .red)
  }

  @MainActor
  @Test func exportControllerRoutesToUiTestingSaverWhenDirectoryIsProvided() async throws {
    let exportDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let controller: ValidationGalleryExportController
    #if os(macOS)
      controller = ValidationGalleryExportController(
        environment: ["XCODE_VALIDATION_GALLERY_UI_TEST_EXPORT_DIRECTORY": exportDirectory.path],
        exportCoordinator: StubExportCoordinator(),
        folderSaver: StubExportSaver(resultURL: URL(fileURLWithPath: "/tmp/ignored-folder", isDirectory: true))
      )
    #else
      controller = ValidationGalleryExportController(
        environment: ["XCODE_VALIDATION_GALLERY_UI_TEST_EXPORT_DIRECTORY": exportDirectory.path],
        exportCoordinator: StubExportCoordinator()
      )
    #endif
    let store = ValidationGalleryStore(
      loader: StubValidationBundleLoader(snapshot: nil),
      recentBundleStore: InMemoryRecentBundleStore()
    )

    controller.requestExport(scope: .currentBundle)
    await controller.performExport(using: store)

    #expect(controller.lastRoute == .uiTestingFolder)
    #expect(controller.lastExportURL?.lastPathComponent == "validation-comments-19700101-000100")
    #expect(controller.request == nil)
  }

  #if os(macOS)
    @MainActor
    @Test func exportControllerRoutesToMacSavePanelSaver() async {
      let savedURL = URL(fileURLWithPath: "/tmp/exported-comments", isDirectory: true)
      let controller = ValidationGalleryExportController(
        environment: [:],
        exportCoordinator: StubExportCoordinator(),
        folderSaver: StubExportSaver(resultURL: savedURL)
      )
      let store = ValidationGalleryStore(
        loader: StubValidationBundleLoader(snapshot: nil),
        recentBundleStore: InMemoryRecentBundleStore()
      )

      controller.requestExport(scope: .selectedArtifact)
      await controller.performExport(using: store)

      #expect(controller.lastRoute == .macOSFolder)
      #expect(controller.lastExportURL == savedURL)
      #expect(controller.request == nil)
    }
  #else
    @MainActor
    @Test func exportControllerRoutesToPackageExporterOnMobile() async {
      let controller = ValidationGalleryExportController(
        environment: [:],
        exportCoordinator: StubExportCoordinator()
      )
      let store = ValidationGalleryStore(
        loader: StubValidationBundleLoader(snapshot: nil),
        recentBundleStore: InMemoryRecentBundleStore()
      )

      controller.requestExport(scope: .selectedArtifact)
      await controller.performExport(using: store)

      #expect(controller.lastRoute == .packageDocument)
      #expect(controller.isPackageExporterPresented)
      #expect(controller.packageDocument != nil)
      #expect(controller.packageDefaultFilename == "validation-comments-19700101-000100")
    }
  #endif

  @MainActor
  @Test func exportControllerSurfacesExportFailuresWithoutUsingBundleLoadErrors() async {
    let controller: ValidationGalleryExportController
    #if os(macOS)
      controller = ValidationGalleryExportController(
        environment: [:],
        exportCoordinator: FailingExportCoordinator(error: ValidationGalleryError.loadFailed("Disk full.")),
        folderSaver: StubExportSaver(resultURL: URL(fileURLWithPath: "/tmp/ignored", isDirectory: true))
      )
    #else
      controller = ValidationGalleryExportController(
        environment: [:],
        exportCoordinator: FailingExportCoordinator(error: ValidationGalleryError.loadFailed("Disk full."))
      )
    #endif
    let store = ValidationGalleryStore(
      loader: StubValidationBundleLoader(snapshot: nil),
      recentBundleStore: InMemoryRecentBundleStore()
    )

    controller.requestExport(scope: .selectedArtifact)
    await controller.performExport(using: store)

    #expect(controller.request == nil)
    #expect(controller.error == .exportFailed("Disk full."))
    #expect(store.error == nil)
  }

  @MainActor
  @Test func exportControllerIgnoresUserCancelledPackageExports() {
    let controller: ValidationGalleryExportController
    #if os(macOS)
      controller = ValidationGalleryExportController(
        environment: [:],
        exportCoordinator: StubExportCoordinator(),
        folderSaver: StubExportSaver(resultURL: URL(fileURLWithPath: "/tmp/exported-comments", isDirectory: true))
      )
    #else
      controller = ValidationGalleryExportController(
        environment: [:],
        exportCoordinator: StubExportCoordinator()
      )
    #endif
    let store = ValidationGalleryStore(
      loader: StubValidationBundleLoader(snapshot: nil),
      recentBundleStore: InMemoryRecentBundleStore()
    )

    controller.packageDocument = ValidationGalleryCommentExportPackageDocument(
      preparedExport: try! StubExportCoordinator().prepareExport(
        from: store,
        options: ValidationGalleryCommentExportOptions(scope: .selectedArtifact)
      )
    )
    controller.isPackageExporterPresented = true

    controller.completePackageExport(result: .failure(CocoaError(.userCancelled)), store: store)

    #expect(controller.error == nil)
    #expect(store.error == nil)
    #expect(controller.isPackageExporterPresented == false)
  }
}

@MainActor
private final class StubExportCoordinator: ValidationGalleryCommentExportPreparing {
  func prepareExport(
    from store: ValidationGalleryStore,
    options: ValidationGalleryCommentExportOptions
  ) throws -> ValidationGalleryPreparedCommentExport {
    let payload = ValidationGalleryCommentExportPayload(
      bundleRootPath: "/tmp/bundle",
      manifestPath: "/tmp/bundle/manifest.json",
      exportedAt: Date(timeIntervalSince1970: 60),
      comments: [
        ValidationGalleryCommentExportPayload.CommentEntry(
          commentID: "comment-1",
          annotationID: 1,
          artifactID: "artifact-1",
          artifactTitle: "Artifact 1",
          platform: "macos",
          plan: "app-tests",
          checkpoint: "progress-report",
          surface: "base",
          variant: "base",
          imagePath: "/tmp/source.png",
          imageURL: "file:///tmp/source.png",
          exportedMediaFilename: options.applyAreaDiagram ? "001-artifact-1.png" : "artifact-artifact-1.png",
          renderApplied: options.applyAreaDiagram,
          annotationColor: options.annotationColor.rawValue,
          comment: "Stub comment",
          anchor: .init(
            kind: "point",
            normalizedPoint: .init(x: 0.5, y: 0.5),
            normalizedRect: nil,
            pixelPoint: .init(x: 100, y: 120),
            pixelRect: nil
          ),
          createdAt: Date(timeIntervalSince1970: 50)
        )
      ]
    )

    return ValidationGalleryPreparedCommentExport(
      rootDirectoryName: "validation-comments-19700101-000100",
      payload: payload,
      files: [
        ValidationGalleryCommentExportFile(relativePath: "comments.json", data: Data("{}".utf8))
      ]
    )
  }
}

@MainActor
private final class FailingExportCoordinator: ValidationGalleryCommentExportPreparing {
  let error: Error

  init(error: Error) {
    self.error = error
  }

  func prepareExport(
    from store: ValidationGalleryStore,
    options: ValidationGalleryCommentExportOptions
  ) throws -> ValidationGalleryPreparedCommentExport {
    throw error
  }
}

@MainActor
private struct StubExportSaver: ValidationGalleryCommentExportSaving {
  let resultURL: URL

  func save(_ preparedExport: ValidationGalleryPreparedCommentExport) throws -> URL? {
    resultURL
  }
}

private actor InMemoryRecentBundleStore: ValidationRecentBundlePersisting {
  func loadRecentBundles() async throws -> [ValidationRecentBundle] {
    []
  }

  func saveRecentBundles(_ recentBundles: [ValidationRecentBundle]) async throws {}
}

private actor StubValidationBundleLoader: ValidationBundleLoading {
  let snapshot: ValidationBundleSnapshot?

  init(snapshot: ValidationBundleSnapshot?) {
    self.snapshot = snapshot
  }

  func load(from source: ValidationBundleSource) async throws -> ValidationBundleSnapshot {
    throw ValidationGalleryError.loadFailed("Not needed in export-controller tests.")
  }
}

// swiftlint:enable force_try
