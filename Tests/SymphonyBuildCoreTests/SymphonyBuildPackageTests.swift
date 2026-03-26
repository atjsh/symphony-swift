import Foundation
import Testing

@Test func symphonyBuildSubpackageExcludesRuntimeOnlyRemoteDependencies() throws {
  let repoRoot = currentRepositoryRoot()
  let packageRoot = repoRoot.appendingPathComponent("Tools/SymphonyBuildPackage", isDirectory: true)
  let manifestURL = packageRoot.appendingPathComponent("Package.swift", isDirectory: false)
  let manifest = try String(contentsOf: manifestURL, encoding: .utf8)

  #expect(manifest.contains("swift-argument-parser"))
  #expect(!manifest.contains("hummingbird"))
  #expect(!manifest.contains("hummingbird-websocket"))
  #expect(!manifest.contains("Yams"))
}

@Test func symphonyBuildSubpackageUsesRepoOwnedSourcesAndTests() throws {
  let repoRoot = currentRepositoryRoot()
  let fileManager = FileManager.default
  let packageRoot = repoRoot.appendingPathComponent("Tools/SymphonyBuildPackage", isDirectory: true)

  let links = [
    (
      packageRoot.appendingPathComponent("Sources/SymphonyShared"),
      repoRoot.appendingPathComponent("Sources/SymphonyShared").path
    ),
    (
      packageRoot.appendingPathComponent("Sources/SymphonyBuildCore"),
      repoRoot.appendingPathComponent("Sources/SymphonyBuildCore").path
    ),
    (
      packageRoot.appendingPathComponent("Sources/SymphonyBuildCLI"),
      repoRoot.appendingPathComponent("Sources/SymphonyBuildCLI").path
    ),
    (
      packageRoot.appendingPathComponent("Sources/symphony-build"),
      repoRoot.appendingPathComponent("Sources/symphony-build").path
    ),
    (
      packageRoot.appendingPathComponent("Tests/SymphonyBuildCoreTests"),
      repoRoot.appendingPathComponent("Tests/SymphonyBuildCoreTests").path
    ),
    (
      packageRoot.appendingPathComponent("Tests/SymphonyBuildCLITests"),
      repoRoot.appendingPathComponent("Tests/SymphonyBuildCLITests").path
    ),
  ]

  for (linkURL, expectedDestination) in links {
    #expect(fileManager.fileExists(atPath: linkURL.path))
    #expect(linkURL.resolvingSymlinksInPath().path == expectedDestination)
  }
}
