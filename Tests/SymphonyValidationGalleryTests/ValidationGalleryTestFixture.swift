import Foundation
import Testing
import SymphonyValidationGallery
import SymphonyXcodeValidation

enum ValidationGalleryTestFixture {
  static var bundleRoot: URL {
    guard let url = ValidationGalleryFixtureLocator.bundledFixtureURL else {
      fatalError("Missing bundled validation gallery fixture")
    }
    return url
  }

  static func makeTemporaryDirectory(named name: String = UUID().uuidString) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("xcode-validation-gallery-tests", isDirectory: true)
      .appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  static func copyFixtureBundle(named name: String = UUID().uuidString) throws -> URL {
    let destination = try makeTemporaryDirectory(named: name)
      .appendingPathComponent("bundle", isDirectory: true)
    if FileManager.default.fileExists(atPath: destination.path) {
      try FileManager.default.removeItem(at: destination)
    }
    try FileManager.default.copyItem(at: bundleRoot, to: destination)
    return destination
  }

  @discardableResult
  static func appendDuplicateManifestArtifact(
    in bundleRoot: URL,
    platform: String,
    plan: String,
    checkpoint: String,
    artifactType: MediaArtifactType,
    sourceResultBundle: String
  ) throws -> MediaArtifact {
    let manifestURL = bundleRoot.appendingPathComponent("manifest.json")
    let manifestData = try Data(contentsOf: manifestURL)
    var artifacts = try JSONDecoder().decode([MediaArtifact].self, from: manifestData)
    let matchingArtifact = artifacts.first(where: {
      $0.platform == platform
        && $0.plan == plan
        && $0.checkpoint == checkpoint
        && $0.artifactType == artifactType
    })
    let originalArtifact = try #require(matchingArtifact)

    artifacts.append(
      MediaArtifact(
        platform: originalArtifact.platform,
        plan: originalArtifact.plan,
        test: originalArtifact.test,
        checkpoint: originalArtifact.checkpoint,
        surface: originalArtifact.surface,
        orientation: originalArtifact.orientation,
        variant: originalArtifact.variant,
        artifactType: originalArtifact.artifactType,
        file: originalArtifact.file,
        sourceResultBundle: sourceResultBundle
      )
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(artifacts).write(to: manifestURL)
    return originalArtifact
  }
}
