import Foundation
import Testing

@testable import SymphonyHarness

@Test func buildToolCoverageSupportsInspectionOutputsAndArtifactsForSwiftPM() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
      xcodeProjectPath: nil
    )

    let coveragePath = repoRoot.appendingPathComponent(
      ".build/arm64-apple-macosx/debug/codecov/symphony-swift.json")
    let profdataPath = coveragePath.deletingLastPathComponent().appendingPathComponent(
      "default.profdata")
    let testBinaryPath =
      repoRoot
      .appendingPathComponent(
        ".build/arm64-apple-macosx/debug/symphony-swiftPackageTests.xctest/Contents/MacOS/symphony-swiftPackageTests"
      )
    let sourcePath = repoRoot.appendingPathComponent(
      "Sources/SymphonyServerCore/Orchestrator.swift")
    try FileManager.default.createDirectory(
      at: sourcePath.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: coveragePath.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: testBinaryPath.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data().write(to: profdataPath)
    try Data().write(to: testBinaryPath)
    try #"""
    {
      "data": [
        {
          "files": [
            {
              "filename": "__REPO__/Sources/SymphonyServerCore/Orchestrator.swift",
              "summary": { "lines": { "count": 4, "covered": 2 } }
            }
          ]
        }
      ]
    }
    """#
    .replacingOccurrences(of: "__REPO__", with: repoRoot.path)
    .write(to: coveragePath, atomically: true, encoding: .utf8)

    let showCommand =
      "xcrun llvm-cov show -instr-profile \(profdataPath.path) \(testBinaryPath.path) \(sourcePath.path)"
    let functionsCommand =
      "xcrun llvm-cov report --show-functions -instr-profile \(profdataPath.path) \(testBinaryPath.path) \(sourcePath.path)"
    let runner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "swift",
        arguments == ["test", "--scratch-path", ".build/swiftpm-cache", "--enable-code-coverage", "--filter", "SymphonyServerTests"]
      {
        return StubProcessRunner.success("swift coverage ok")
      }
      if command == "swift", arguments == ["test", "--scratch-path", ".build/swiftpm-cache", "--show-code-coverage-path"] {
        return StubProcessRunner.success(coveragePath.path + "\n")
      }
      let rendered = ([command] + arguments).joined(separator: " ")
      if rendered == showCommand {
        return StubProcessRunner.success(
          """
              1|       |import Foundation
              2|      1|func bootstrap() {
              3|      0|    start()
              4|      0|    finish()
              5|      1|}
          """
        )
      }
      if rendered == functionsCommand {
        return StubProcessRunner.success(
          """
          File '\(sourcePath.path)':
          Name                                     Regions    Miss   Cover     Lines    Miss   Cover  Branches    Miss   Cover
          --------------------------------------------------------------------------------------------------------------------------------
          bootstrap()                                   2       1  50.00%         4       2  50.00%         0       0   0.00%
          --------------------------------------------------------------------------------------------------------------------------------
          TOTAL                                         2       1  50.00%         4       2  50.00%         0       0   0.00%
          """
        )
      }
      return StubProcessRunner.success()
    }
    let tool = makeCoverageTool(workspace: workspace, runner: runner, statusSink: { _ in })

    let testOutput = try tool.test(
      TestCommandRequest(
        product: .server,
        scheme: nil,
        platform: nil,
        simulator: nil,
        workerID: 0,
        dryRun: false,
        onlyTesting: [],
        skipTesting: [],
        outputMode: .filtered,
        currentDirectory: repoRoot
      )
    )
    #expect(FileManager.default.fileExists(atPath: testOutput))

    let testArtifacts = try tool.artifacts(
      ArtifactsCommandRequest(command: .test, latest: true, runID: nil, currentDirectory: repoRoot)
    )
    #expect(testArtifacts.contains("coverage-inspection.json"))
    #expect(testArtifacts.contains("coverage-inspection.txt"))
    #expect(testArtifacts.contains("coverage-inspection-raw.json"))
    #expect(testArtifacts.contains("coverage-inspection-raw.txt"))
  }
}

@Test func buildToolCoverageSupportsInspectionOutputsAndArtifactsForXcode() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
      xcodeProjectPath: nil
    )
    let devices = [
      SimulatorDevice(
        name: "iPhone 17", udid: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", state: "Shutdown",
        runtime: "iOS 18")
    ]
    let sourcePath = "/tmp/ContentView.swift"
    let coverageJSON = #"""
      {
        "targets": [
          {
            "buildProductPath": "/tmp/Symphony.app",
            "coveredLines": 2,
            "executableLines": 4,
            "files": [
              { "coveredLines": 2, "executableLines": 4, "name": "ContentView.swift", "path": "/tmp/ContentView.swift" }
            ],
            "name": "Symphony"
          }
        ]
      }
      """#

    let runner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "xcodebuild", arguments.last == "test",
        arguments.contains("-enableCodeCoverage"), arguments.contains("YES")
      {
        return StubProcessRunner.success("coverage ok")
      }
      if command == "xcrun",
        arguments == [
          "xccov", "view", "--report", "--json",
          workspace.buildStateRoot.appendingPathComponent(
            "results/coverage/\(DateFormatting.runTimestamp(for: Date()))-symphony.xcresult"
          ).path,
        ]
      {
        return StubProcessRunner.success(coverageJSON)
      }
      if command == "xcrun", arguments.prefix(4) == ["xccov", "view", "--report", "--json"] {
        return StubProcessRunner.success(coverageJSON)
      }
      if command == "xcrun",
        arguments == [
          "xccov", "view", "--archive", "--file", sourcePath,
          workspace.buildStateRoot.appendingPathComponent(
            "results/coverage/\(DateFormatting.runTimestamp(for: Date()))-symphony.xcresult"
          ).path,
        ]
      {
        return StubProcessRunner.success(
          """
           1: *
           2: 2
           3: 0
           4: 0
           5: 2
          """
        )
      }
      if command == "xcrun", arguments.prefix(4) == ["xccov", "view", "--archive", "--file"] {
        return StubProcessRunner.success(
          """
           1: *
           2: 2
           3: 0
           4: 0
           5: 2
          """
        )
      }
      if command == "xcrun",
        arguments == [
          "xccov", "view", "--report", "--functions-for-file", sourcePath,
          workspace.buildStateRoot.appendingPathComponent(
            "results/coverage/\(DateFormatting.runTimestamp(for: Date()))-symphony.xcresult"
          ).path,
        ]
      {
        return StubProcessRunner.success(
          """
          \(sourcePath):
          ID Name                                  Range   Coverage
          -- ------------------------------------- ------- ---------------
          0  ContentView.body.getter               {7, 19} 50.00% (2/4)
          """
        )
      }
      if command == "xcrun",
        arguments.prefix(4) == ["xccov", "view", "--report", "--functions-for-file"]
      {
        return StubProcessRunner.success(
          """
          \(sourcePath):
          ID Name                                  Range   Coverage
          -- ------------------------------------- ------- ---------------
          0  ContentView.body.getter               {7, 19} 50.00% (2/4)
          """
        )
      }
      return StubProcessRunner.success()
    }
    let tool = SymphonyHarnessTool(
      workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
      executionContextBuilder: ExecutionContextBuilder(),
      simulatorResolver: SimulatorResolver(
        catalog: StubSimulatorCatalog(devices: devices), processRunner: runner),
      processRunner: runner,
      artifactManager: ArtifactManager(processRunner: runner),
      endpointOverrideStore: EndpointOverrideStore(),
      doctorService: StubDoctorService(
        report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []),
        rendered: "ok"),
      productLocator: ProductLocator(processRunner: runner),
      commitHarness: CommitHarness(processRunner: runner),
      gitHookInstaller: GitHookInstaller(processRunner: runner),
      statusSink: { _ in }
    )

    let output = try tool.test(
      TestCommandRequest(
        product: .client,
        scheme: nil,
        platform: nil,
        simulator: "iPhone 17",
        workerID: 0,
        dryRun: false,
        onlyTesting: [],
        skipTesting: [],
        outputMode: .filtered,
        currentDirectory: repoRoot
      )
    )

    #expect(FileManager.default.fileExists(atPath: output))

    let testArtifacts = try tool.artifacts(
      ArtifactsCommandRequest(command: .test, latest: true, runID: nil, currentDirectory: repoRoot)
    )
    #expect(testArtifacts.contains("coverage-inspection.json"))
    #expect(testArtifacts.contains("coverage-inspection.txt"))
  }
}

@Test func buildToolHarnessSkipsCoveredPackageFilesAndFallsBackWhenSwiftPMBinaryIsMissing() throws {
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
    let profdataPath = coveragePath.deletingLastPathComponent().appendingPathComponent(
      "default.profdata")
    try FileManager.default.createDirectory(
      at: coveragePath.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data().write(to: profdataPath)
    try #"""
    {
      "data": [
        {
          "files": [
            { "filename": "__REPO__/Sources/SymphonyServerCore/Orchestrator.swift", "summary": { "lines": { "count": 4, "covered": 2 } } },
            { "filename": "__REPO__/Sources/Covered.swift", "summary": { "lines": { "count": 4, "covered": 4 } } }
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

    let output = try tool.harness(
      HarnessCommandRequest(minimumCoveragePercent: 50, json: false, currentDirectory: repoRoot)
    )
    #expect(output.contains("package coverage 75.00% (6/8)"))

    let artifactRoot = workspace.buildStateRoot.appendingPathComponent("artifacts/harness/latest")
      .resolvingSymlinksInPath()
    let packageInspection = try JSONDecoder().decode(
      HarnessCoverageInspectionArtifact.self,
      from: Data(contentsOf: artifactRoot.appendingPathComponent("package-inspection.json"))
    )
    #expect(packageInspection.files.isEmpty)
  }
}

