import Foundation
import Testing

@testable import SymphonyValidationGallery

@Suite("ValidationBundleLoader")
struct ValidationBundleLoaderTests {
  @Test func bundleLoaderDecodesFixtureSummaryAndMediaHierarchy() async throws {
    let loader = ValidationBundleLoader()

    let snapshot = try await loader.load(from: .folder(ValidationGalleryTestFixture.bundleRoot))

    #expect(snapshot.summary.status == .passed)
    #expect(snapshot.summary.runRecords.count == 5)
    #expect(snapshot.artifacts.count == 6)
    #expect(snapshot.auditIssues.count == 2)
    #expect(snapshot.warnings.isEmpty)
    #expect(snapshot.platformSections.map(\.platform) == ["macos", "ios", "ipados"])
    #expect(snapshot.platformSections[0].plans.map(\.plan) == ["app-tests", "ui-tests"])
    #expect(snapshot.platformSections[0].plans[1].checkpoints.map(\.checkpoint) == ["logs", "root"])
  }

  @Test func bundleLoaderResolvesManifestRelativePathsAgainstBundleRoot() async throws {
    let loader = ValidationBundleLoader()
    let manifestURL = ValidationGalleryTestFixture.bundleRoot.appendingPathComponent("manifest.json")

    let snapshot = try await loader.load(from: .manifestFile(manifestURL))
    let videoArtifact = try #require(
      snapshot.artifacts.first(where: { $0.record.artifactType == .video })
    )

    #expect(
      videoArtifact.fileURL
        == ValidationGalleryTestFixture.bundleRoot
        .appendingPathComponent("ios/media/videos/ios-rich-media.mov")
    )
  }

  @Test func bundleLoaderKeepsMissingMediaAsWarningsInsteadOfFailing() async throws {
    let loader = ValidationBundleLoader()
    let copiedBundle = try ValidationGalleryTestFixture.copyFixtureBundle(named: "missing-media")
    let deletedFile = copiedBundle
      .appendingPathComponent("macos/media/screenshots/macos-ui-tests-logs.png")
    try FileManager.default.removeItem(at: deletedFile)

    let snapshot = try await loader.load(from: .folder(copiedBundle))

    #expect(snapshot.warnings.count == 1)
    let logsArtifact = try #require(
      snapshot.artifacts.first(where: { $0.record.checkpoint == "logs" })
    )
    #expect(logsArtifact.isAvailable == false)
  }

  @Test func bundleLoaderRejectsMalformedSummaryJSON() async throws {
    let loader = ValidationBundleLoader()
    let copiedBundle = try ValidationGalleryTestFixture.copyFixtureBundle(named: "malformed-summary")
    try "{".write(
      to: copiedBundle.appendingPathComponent("summary.json"),
      atomically: true,
      encoding: .utf8
    )

    do {
      _ = try await loader.load(from: .folder(copiedBundle))
      Issue.record("Expected malformed summary.json to throw.")
    } catch let error as ValidationGalleryError {
      switch error {
      case .malformedJSON(let fileName, _):
        #expect(fileName == "summary.json")
      default:
        Issue.record("Expected malformedJSON for summary.json, got \(error).")
      }
    }
  }

  @Test func bundleLoaderRejectsMissingManifest() async throws {
    let loader = ValidationBundleLoader()
    let copiedBundle = try ValidationGalleryTestFixture.copyFixtureBundle(named: "missing-manifest")
    try FileManager.default.removeItem(at: copiedBundle.appendingPathComponent("manifest.json"))

    do {
      _ = try await loader.load(from: .folder(copiedBundle))
      Issue.record("Expected missing manifest.json to throw.")
    } catch let error as ValidationGalleryError {
      #expect(error == .missingRequiredFile("manifest.json"))
    }
  }

  @Test func bundleLoaderDeduplicatesLegacyCanonicalManifestRowsKeepingLastSourceResultBundle() async throws {
    let loader = ValidationBundleLoader()
    let copiedBundle = try ValidationGalleryTestFixture.copyFixtureBundle(named: "duplicate-canonical-media")
    try ValidationGalleryTestFixture.appendDuplicateManifestArtifact(
      in: copiedBundle,
      platform: "macos",
      plan: "app-tests",
      checkpoint: "progress-report",
      artifactType: .screenshot,
      sourceResultBundle: "/tmp/final-result.xcresult"
    )

    let snapshot = try await loader.load(from: .folder(copiedBundle))

    #expect(snapshot.artifacts.count == 6)
    guard snapshot.artifacts.count == 6 else {
      return
    }

    let progressArtifact = snapshot.artifacts.first(where: {
      $0.record.platform == "macos"
        && $0.record.plan == "app-tests"
        && $0.record.checkpoint == "progress-report"
        && $0.record.artifactType == .screenshot
    })
    let requiredProgressArtifact = try #require(progressArtifact)
    #expect(requiredProgressArtifact.record.sourceResultBundle == "/tmp/final-result.xcresult")
  }
}
