import Foundation
import Testing

@testable import SymphonyHarness

@Test func workspaceDiscoveryUsesHarnessBuildStateRoot() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(at: repoRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)
    try "package".write(
      to: repoRoot.appendingPathComponent("Package.swift"),
      atomically: true,
      encoding: .utf8
    )
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Symphony.xcworkspace"), withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("SymphonyApps.xcodeproj"),
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Applications"), withIntermediateDirectories: true)

    let workspace = try WorkspaceDiscovery(processRunner: StubProcessRunner()).discover(from: repoRoot)

    #expect(workspace.buildStateRoot.path.hasSuffix(".build/harness"))
  }
}

@Test func workspaceDiscoveryRejectsExtraToolsPackageManifest() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(at: repoRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)
    try "package".write(
      to: repoRoot.appendingPathComponent("Package.swift"),
      atomically: true,
      encoding: .utf8
    )
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Symphony.xcworkspace"), withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Tools/SymphonyBuildPackage"),
      withIntermediateDirectories: true
    )
    try "subpackage".write(
      to: repoRoot.appendingPathComponent("Tools/SymphonyBuildPackage/Package.swift"),
      atomically: true,
      encoding: .utf8
    )

    do {
      _ = try WorkspaceDiscovery(processRunner: StubProcessRunner()).discover(from: repoRoot)
      Issue.record("Expected an extra tools package manifest to fail discovery.")
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "extra_package_manifest")
    }
  }
}
