import Foundation
import Testing

@testable import SymphonyHarness

@Test func buildToolHarnessFailureUsesCompactPreviewMessage() throws {
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
            { "filename": "__REPO__/Sources/Foo.swift", "summary": { "lines": { "count": 4, "covered": 2 } } }
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

    do {
      _ = try tool.harness(
        HarnessCommandRequest(minimumCoveragePercent: 100, json: false, currentDirectory: repoRoot)
      )
      Issue.record("Expected harness failures to render the compact preview message.")
    } catch let error as SymphonyHarnessCommandFailure {
      #expect(
        error.message.contains(
          "Commit harness failed because one or more required coverage suites are below the required threshold."
        ))
      #expect(error.message.contains("package file Sources/Foo.swift 50.00% (2/4)"))
      #expect(error.message.contains("Harness artifacts:"))
    }
  }
}

@Test
func buildToolHarnessWritesPackageInspectionFromCommitHarnessExecutionBeforeArtifactsAreRewritten()
  throws
{
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    let codecovRoot = repoRoot.appendingPathComponent(
      ".build/arm64-apple-macosx/debug/codecov", isDirectory: true)
    let testBundleRoot = repoRoot.appendingPathComponent(
      ".build/arm64-apple-macosx/debug/symphony-swiftPackageTests.xctest/Contents/MacOS",
      isDirectory: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources/Foo", isDirectory: true),
      withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: codecovRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: testBundleRoot, withIntermediateDirectories: true)

    let sourceFile = repoRoot.appendingPathComponent("Sources/Foo/Bar.swift")
    try "func bar() {}".write(to: sourceFile, atomically: true, encoding: .utf8)

    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: nil,
      xcodeProjectPath: nil
    )
    let coveragePath = codecovRoot.appendingPathComponent("symphony-swift.json")
    try #"""
    {
      "data": [
        {
          "files": [
            { "filename": "__REPO__/Sources/Foo/Bar.swift", "summary": { "lines": { "count": 4, "covered": 2 } } }
          ]
        }
      ]
    }
    """#
    .replacingOccurrences(of: "__REPO__", with: repoRoot.path)
    .write(to: coveragePath, atomically: true, encoding: .utf8)
    let profdataPath = codecovRoot.appendingPathComponent("default.profdata")
    let testBinaryPath = testBundleRoot.appendingPathComponent("symphony-swiftPackageTests")
    try Data().write(to: profdataPath)
    try Data().write(to: testBinaryPath)

    let runner = HarnessPackageInspectionOverwriteProcessRunner(
      packageCoveragePath: coveragePath.path,
      sourceFilePath: sourceFile.path,
      profdataPath: profdataPath.path,
      testBinaryPath: testBinaryPath.path
    )
    let perfectCoverage = CoverageReport(
      coveredLines: 1,
      executableLines: 1,
      lineCoverage: 1,
      includeTestTargets: false,
      excludedTargets: [],
      targets: []
    )
    let tool = SymphonyHarnessTool(
      workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
      processRunner: runner,
      artifactManager: ArtifactManager(processRunner: runner),
      toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(
        capabilities: .fullyAvailableForTests),
      commitHarness: CommitHarness(
        processRunner: runner,
        statusSink: { _ in },
        clientCoverageLoader: { _ in perfectCoverage },
        serverCoverageLoader: { _ in
          runner.markArtifactsRewritten()
          return perfectCoverage
        },
        toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(
          capabilities: .fullyAvailableForTests)
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
    #expect(
      packageInspection.files == [
        CoverageInspectionFileReport(
          targetName: "Foo",
          path: "Sources/Foo/Bar.swift",
          coveredLines: 2,
          executableLines: 4,
          lineCoverage: 0.5,
          missingLineRanges: [CoverageLineRange(startLine: 2, endLine: 3)],
          functions: [
            CoverageInspectionFunctionReport(
              name: "initial()",
              coveredLines: 2,
              executableLines: 4,
              lineCoverage: 0.5
            )
          ]
        )
      ])
  }
}

@Test func buildToolUsesDryRunFallbackDestinationsWhenSimulatorToolingIsUnavailable() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
      xcodeProjectPath: nil
    )
    let silentRunner = RoutedProcessRunner { _, _, _, _, _ in
      Issue.record(
        "Dry-run fallback and unsupported simulator checks should not invoke subprocesses.")
      return StubProcessRunner.success()
    }

    let noXcodeTool = SymphonyHarnessTool(
      workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
      executionContextBuilder: ExecutionContextBuilder(),
      simulatorResolver: SimulatorResolver(
        catalog: StubSimulatorCatalog(devices: []), processRunner: silentRunner),
      processRunner: silentRunner,
      artifactManager: ArtifactManager(processRunner: silentRunner),
      endpointOverrideStore: EndpointOverrideStore(),
      doctorService: StubDoctorService(
        report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []),
        rendered: "ok"),
      toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(
        capabilities: .noXcodeForTests),
      productLocator: ProductLocator(processRunner: silentRunner),
      commitHarness: CommitHarness(processRunner: silentRunner),
      gitHookInstaller: GitHookInstaller(processRunner: silentRunner),
      statusSink: { _ in }
    )
    let macDryRun = try noXcodeTool.build(
      BuildCommandRequest(
        product: .client, scheme: nil, platform: .macos, simulator: nil, workerID: 0, dryRun: true,
        buildForTesting: false, outputMode: .filtered, currentDirectory: repoRoot)
    )
    #expect(macDryRun.contains(expectedHostMacOSDestination()))

    let partialCapabilities = StubToolchainCapabilitiesResolver(
      capabilities: ToolchainCapabilities(
        swiftAvailable: true,
        xcodebuildAvailable: true,
        xcrunAvailable: true,
        simctlAvailable: false,
        xcresulttoolAvailable: true,
        llvmCovCommand: .xcrun
      ))
    let partialTool = SymphonyHarnessTool(
      workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
      executionContextBuilder: ExecutionContextBuilder(),
      simulatorResolver: SimulatorResolver(
        catalog: StubSimulatorCatalog(devices: []), processRunner: silentRunner),
      processRunner: silentRunner,
      artifactManager: ArtifactManager(processRunner: silentRunner),
      endpointOverrideStore: EndpointOverrideStore(),
      doctorService: StubDoctorService(
        report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []),
        rendered: "ok"),
      toolchainCapabilitiesResolver: partialCapabilities,
      productLocator: ProductLocator(processRunner: silentRunner),
      commitHarness: CommitHarness(processRunner: silentRunner),
      gitHookInstaller: GitHookInstaller(processRunner: silentRunner),
      statusSink: { _ in }
    )

    let namedSimulatorDryRun = try partialTool.build(
      BuildCommandRequest(
        product: .client, scheme: nil, platform: .iosSimulator, simulator: "Custom Sim",
        workerID: 0, dryRun: true, buildForTesting: false, outputMode: .filtered,
        currentDirectory: repoRoot)
    )
    #expect(namedSimulatorDryRun.contains("platform=iOS Simulator,name=Custom Sim"))

    let udidDryRun = try partialTool.build(
      BuildCommandRequest(
        product: .client, scheme: nil, platform: .iosSimulator,
        simulator: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", workerID: 0, dryRun: true,
        buildForTesting: false, outputMode: .filtered, currentDirectory: repoRoot)
    )
    #expect(udidDryRun.contains("platform=iOS Simulator,id=AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"))

    do {
      _ = try partialTool.simList(currentDirectory: repoRoot)
      Issue.record(
        "Expected simulator management to be blocked when only simulator tooling is unavailable.")
    } catch let error as SymphonyHarnessCommandFailure {
      #expect(
        error.message
          == "not supported because the current environment has no Xcode available; Editing those sources is not encouraged"
      )
    }
  }
}

@Test func buildToolDefaultInitializerPathsRemainConstructibleWithStubbedRunner() {
  let runner = StubProcessRunner()
  let tool = SymphonyHarnessTool(
    processRunner: runner,
    artifactManager: ArtifactManager(processRunner: runner)
  )
  _ = tool
}

