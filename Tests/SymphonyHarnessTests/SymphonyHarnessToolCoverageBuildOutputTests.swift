import Foundation
import Testing

@testable import SymphonyHarness

@Test func buildToolHarnessSkipsPackageInspectionWhenLLVMCovIsUnavailable() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources"), withIntermediateDirectories: true)

    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: nil,
      xcodeProjectPath: nil
    )
    let coveragePath = repoRoot.appendingPathComponent(
      ".build/arm64-apple-macosx/debug/codecov/symphony-swift.json")
    let debugRoot = repoRoot.appendingPathComponent(
      ".build/arm64-apple-macosx/debug", isDirectory: true)
    let profdataPath = coveragePath.deletingLastPathComponent().appendingPathComponent(
      "default.profdata")
    let testBinaryPath = debugRoot.appendingPathComponent("symphony-swiftPackageTests")
    try FileManager.default.createDirectory(
      at: coveragePath.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: debugRoot, withIntermediateDirectories: true)
    try #"""
    {
      "data": [
        {
          "files": [
            { "filename": "__REPO__/Sources/SymphonyServerCore/Orchestrator.swift", "summary": { "lines": { "count": 4, "covered": 2 } } }
          ]
        }
      ]
    }
    """#
    .replacingOccurrences(of: "__REPO__", with: repoRoot.path)
    .write(to: coveragePath, atomically: true, encoding: .utf8)
    try Data().write(to: profdataPath)
    try Data().write(to: testBinaryPath)

    let perfectCoverage = CoverageReport(
      coveredLines: 4,
      executableLines: 4,
      lineCoverage: 1,
      includeTestTargets: false,
      excludedTargets: [],
      targets: []
    )
    let noLLVMCovCapabilities = StubToolchainCapabilitiesResolver(
      capabilities: ToolchainCapabilities(
        swiftAvailable: true,
        xcodebuildAvailable: false,
        xcrunAvailable: false,
        simctlAvailable: false,
        xcresulttoolAvailable: false,
        llvmCovCommand: nil
      ))
    let harnessRunner = StubProcessRunner(results: [
      "swift test --scratch-path .build/swiftpm-cache --enable-code-coverage": StubProcessRunner.success(),
      "swift test --scratch-path .build/swiftpm-cache --show-code-coverage-path": StubProcessRunner.success(coveragePath.path + "\n"),
    ])
    let missingLLVMCovRunner = StubProcessRunner(results: [
      "which xcrun": StubProcessRunner.failure(""),
      "which llvm-cov": StubProcessRunner.failure(""),
    ])
    let tool = SymphonyHarnessTool(
      workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
      processRunner: missingLLVMCovRunner,
      artifactManager: ArtifactManager(processRunner: missingLLVMCovRunner),
      toolchainCapabilitiesResolver: noLLVMCovCapabilities,
      commitHarness: CommitHarness(
        processRunner: harnessRunner,
        statusSink: { _ in },
        clientCoverageLoader: { _ in perfectCoverage },
        serverCoverageLoader: { _ in perfectCoverage },
        toolchainCapabilitiesResolver: noLLVMCovCapabilities
      )
    )

    _ = try tool.harness(
      HarnessCommandRequest(minimumCoveragePercent: 50, json: false, currentDirectory: repoRoot)
    )

    let artifactRoot = workspace.buildStateRoot.appendingPathComponent("artifacts/harness/latest")
      .resolvingSymlinksInPath()
    let packageInspection = try JSONDecoder().decode(
      HarnessCoverageInspectionArtifact.self,
      from: Data(contentsOf: artifactRoot.appendingPathComponent("package-inspection.json"))
    )
    #expect(packageInspection.files.isEmpty)
  }
}

@Test func buildToolHarnessWritesSkippedClientArtifactsAndSupportsJSONOutput() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources"), withIntermediateDirectories: true)

    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: nil,
      xcodeProjectPath: nil
    )
    let coveragePath = repoRoot.appendingPathComponent(
      ".build/arm64-apple-macosx/debug/codecov/symphony-swift.json")
    try FileManager.default.createDirectory(
      at: coveragePath.deletingLastPathComponent(), withIntermediateDirectories: true)
    try #"""
    {
      "data": [
        {
          "files": [
            { "filename": "__REPO__/Sources/Foo.swift", "summary": { "lines": { "count": 4, "covered": 4 } } }
          ]
        }
      ]
    }
    """#
    .replacingOccurrences(of: "__REPO__", with: repoRoot.path)
    .write(to: coveragePath, atomically: true, encoding: .utf8)

    let perfectCoverage = CoverageReport(
      coveredLines: 4,
      executableLines: 4,
      lineCoverage: 1,
      includeTestTargets: false,
      excludedTargets: [],
      targets: []
    )
    let noXcodeCapabilities = StubToolchainCapabilitiesResolver(capabilities: .noXcodeForTests)
    let harnessRunner = StubProcessRunner(results: [
      "swift test --scratch-path .build/swiftpm-cache --enable-code-coverage": StubProcessRunner.success(),
      "swift test --scratch-path .build/swiftpm-cache --show-code-coverage-path": StubProcessRunner.success(coveragePath.path + "\n"),
    ])
    let tool = SymphonyHarnessTool(
      workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
      processRunner: StubProcessRunner(),
      artifactManager: ArtifactManager(processRunner: StubProcessRunner()),
      toolchainCapabilitiesResolver: noXcodeCapabilities,
      commitHarness: CommitHarness(
        processRunner: harnessRunner,
        statusSink: { _ in },
        serverCoverageLoader: { _ in perfectCoverage },
        toolchainCapabilitiesResolver: noXcodeCapabilities
      )
    )

    let output = try tool.harness(
      HarnessCommandRequest(minimumCoveragePercent: 100, json: true, currentDirectory: repoRoot)
    )
    #expect(output.contains("\"clientCoverageSkipReason\""))
    #expect(
      output.contains(
        "not supported because the current environment has no Xcode available; Editing those sources is not encouraged"
      ))

    let artifactRoot = workspace.buildStateRoot.appendingPathComponent("artifacts/harness/latest")
      .resolvingSymlinksInPath()
    let clientInspection = try JSONDecoder().decode(
      HarnessCoverageInspectionArtifact.self,
      from: Data(contentsOf: artifactRoot.appendingPathComponent("client-inspection.json"))
    )
    let serverInspection = try JSONDecoder().decode(
      HarnessCoverageInspectionArtifact.self,
      from: Data(contentsOf: artifactRoot.appendingPathComponent("server-inspection.json"))
    )
    let clientInspectionHuman = try String(
      contentsOf: artifactRoot.appendingPathComponent("client-inspection.txt"),
      encoding: .utf8
    )
    let summary = try String(
      contentsOf: artifactRoot.appendingPathComponent("summary.txt"), encoding: .utf8)

    #expect(clientInspection.files.isEmpty)
    #expect(
      clientInspection.skippedReason
        == "not supported because the current environment has no Xcode available; Editing those sources is not encouraged"
    )
    #expect(serverInspection.suite == "server")
    #expect(
      clientInspectionHuman.contains(
        "skipped not supported because the current environment has no Xcode available; Editing those sources is not encouraged"
      ))
    #expect(summary.contains("invocation: harness harness --minimum-coverage 100.00 --json"))
  }
}

@Test func buildToolHarnessRendersExplicitOutputModeInSummaryInvocation() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources"), withIntermediateDirectories: true)

    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: nil,
      xcodeProjectPath: nil
    )
    let coveragePath = repoRoot.appendingPathComponent(
      ".build/arm64-apple-macosx/debug/codecov/symphony-swift.json")
    try FileManager.default.createDirectory(
      at: coveragePath.deletingLastPathComponent(), withIntermediateDirectories: true)
    try #"""
    {
      "data": [
        {
          "files": [
            { "filename": "__REPO__/Sources/Foo.swift", "summary": { "lines": { "count": 4, "covered": 4 } } }
          ]
        }
      ]
    }
    """#
    .replacingOccurrences(of: "__REPO__", with: repoRoot.path)
    .write(to: coveragePath, atomically: true, encoding: .utf8)

    let perfectCoverage = CoverageReport(
      coveredLines: 4,
      executableLines: 4,
      lineCoverage: 1,
      includeTestTargets: false,
      excludedTargets: [],
      targets: []
    )
    let harnessRunner = StubProcessRunner(results: [
      "swift test --scratch-path .build/swiftpm-cache --enable-code-coverage": StubProcessRunner.success(),
      "swift test --scratch-path .build/swiftpm-cache --show-code-coverage-path": StubProcessRunner.success(coveragePath.path + "\n"),
    ])
    let tool = SymphonyHarnessTool(
      workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
      processRunner: StubProcessRunner(),
      artifactManager: ArtifactManager(processRunner: StubProcessRunner()),
      commitHarness: CommitHarness(
        processRunner: harnessRunner,
        statusSink: { _ in },
        clientCoverageLoader: { _ in perfectCoverage },
        serverCoverageLoader: { _ in perfectCoverage }
      )
    )

    _ = try tool.harness(
      HarnessCommandRequest(
        minimumCoveragePercent: 50, json: false, outputMode: .quiet, currentDirectory: repoRoot)
    )

    let artifactRoot = workspace.buildStateRoot.appendingPathComponent("artifacts/harness/latest")
      .resolvingSymlinksInPath()
    let summary = try String(
      contentsOf: artifactRoot.appendingPathComponent("summary.txt"), encoding: .utf8)
    #expect(
      summary.contains(
        "invocation: harness harness --minimum-coverage 50.00 --output-mode quiet"))
  }
}

