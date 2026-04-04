import Foundation
import Testing

@testable import SymphonyHarness

@Test func buildToolCoversBuildTestAndCoverageSuccessAndFailurePaths() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
      xcodeProjectPath: nil
    )
    let coveragePath = repoRoot.appendingPathComponent(".build/server-coverage.json")
    try FileManager.default.createDirectory(
      at: coveragePath.deletingLastPathComponent(), withIntermediateDirectories: true)
    let coverageJSON = #"""
    {
      "data": [
        {
          "files": [
            {
              "filename": "__REPO__/Sources/SymphonyServerCore/Orchestrator.swift",
              "summary": { "lines": { "count": 4, "covered": 4 } }
            },
            {
              "filename": "__REPO__/Sources/SymphonyServerCLI/main.swift",
              "summary": { "lines": { "count": 2, "covered": 2 } }
            },
            {
              "filename": "__REPO__/Tests/SymphonyServerTests/BootstrapServerRunnerTests.swift",
              "summary": { "lines": { "count": 20, "covered": 20 } }
            }
          ]
        }
      ]
    }
    """#.replacingOccurrences(of: "__REPO__", with: repoRoot.path)
    try coverageJSON.write(to: coveragePath, atomically: true, encoding: .utf8)

    let signals = SignalBox()
    let runner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "swift", arguments == ["build", "--scratch-path", ".build/swiftpm-cache", "--product", "symphony-server"] {
        return StubProcessRunner.success("swift build ok")
      }
      if command == "swift", arguments == ["test", "--scratch-path", ".build/swiftpm-cache", "--filter", "SymphonyServerTests"] {
        return StubProcessRunner.success("swift test ok")
      }
      if command == "swift",
        arguments == ["test", "--scratch-path", ".build/swiftpm-cache", "--enable-code-coverage", "--filter", "SymphonyServerTests"]
      {
        return StubProcessRunner.success("swift coverage ok")
      }
      if command == "swift", arguments == ["test", "--scratch-path", ".build/swiftpm-cache", "--show-code-coverage-path"] {
        return StubProcessRunner.success(coveragePath.path + "\n")
      }
      return StubProcessRunner.success()
    }
    let tool = makeCoverageTool(
      workspace: workspace, runner: runner, statusSink: { signals.append($0) })

    let buildOutput = try tool.build(
      BuildCommandRequest(
        product: .server,
        scheme: nil,
        platform: nil,
        simulator: nil,
        workerID: 0,
        dryRun: false,
        buildForTesting: true,
        outputMode: .full,
        currentDirectory: repoRoot
      )
    )
    #expect(buildOutput.hasSuffix("summary.txt"))

    let testOutput = try tool.test(
      TestCommandRequest(
        product: .server,
        scheme: nil,
        platform: nil,
        simulator: nil,
        workerID: 0,
        dryRun: false,
        onlyTesting: ["Suite/test"],
        skipTesting: ["Suite/skip"],
        outputMode: .filtered,
        currentDirectory: repoRoot
      )
    )
    #expect(FileManager.default.fileExists(atPath: testOutput))
    #expect(runner.startedDetachedExecutions.isEmpty)
    #expect(signals.values.isEmpty)

    let failingRunner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "swift", arguments == ["build", "--scratch-path", ".build/swiftpm-cache", "--product", "symphony-server"] {
        return StubProcessRunner.failure("build failed")
      }
      if command == "swift",
        arguments == ["test", "--scratch-path", ".build/swiftpm-cache", "--enable-code-coverage", "--filter", "SymphonyServerTests"]
      {
        return StubProcessRunner.failure("test failed")
      }
      return StubProcessRunner.success()
    }
    let failingTool = makeCoverageTool(
      workspace: workspace, runner: failingRunner, statusSink: { _ in })

    do {
      _ = try failingTool.build(
        BuildCommandRequest(
          product: .server, scheme: nil, platform: nil, simulator: nil, workerID: 0, dryRun: false,
          buildForTesting: false, outputMode: .filtered, currentDirectory: repoRoot)
      )
      Issue.record("Expected failing builds to surface.")
    } catch let error as SymphonyHarnessCommandFailure {
      #expect(error.message.contains("swift build failed"))
    }

    do {
      _ = try failingTool.test(
        TestCommandRequest(
          product: .server, scheme: nil, platform: nil, simulator: nil, workerID: 0, dryRun: false,
          onlyTesting: [], skipTesting: [], outputMode: .filtered, currentDirectory: repoRoot)
      )
      Issue.record("Expected failing tests to surface.")
    } catch let error as SymphonyHarnessCommandFailure {
      #expect(error.message.contains("swift test failed"))
    }

    let exportFailRunner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "swift",
        arguments == ["test", "--scratch-path", ".build/swiftpm-cache", "--enable-code-coverage", "--filter", "SymphonyServerTests"]
      {
        return StubProcessRunner.success("ok")
      }
      if command == "swift", arguments == ["test", "--scratch-path", ".build/swiftpm-cache", "--show-code-coverage-path"] {
        return StubProcessRunner.success(
          repoRoot.appendingPathComponent("missing-coverage.json").path + "\n")
      }
      return StubProcessRunner.success()
    }
    let exportFailTool = makeCoverageTool(
      workspace: workspace, runner: exportFailRunner, statusSink: { _ in })
    let exportFailOutput = try exportFailTool.test(
      TestCommandRequest(
        product: .server, scheme: nil, platform: nil, simulator: nil, workerID: 0, dryRun: false,
        onlyTesting: [], skipTesting: [], outputMode: .filtered, currentDirectory: repoRoot)
    )
    #expect(FileManager.default.fileExists(atPath: exportFailOutput))
  }
}

@Test func subjectExecutionBridgeBuildsCanonicalSwiftPMAndAppSubjects() throws {
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
    let runner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "swift", arguments == ["build", "--scratch-path", ".build/swiftpm-cache", "--product", "SymphonyShared"] {
        return StubProcessRunner.success("shared built")
      }
      if command == "swift", arguments == ["build", "--scratch-path", ".build/swiftpm-cache", "--product", "harness"] {
        return StubProcessRunner.success("harness built")
      }
      if command == "xcodebuild", arguments.last == "build" {
        #expect(arguments.contains("SymphonySwiftUIApp"))
        return StubProcessRunner.success("app built")
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
      toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(
        capabilities: .fullyAvailableForTests),
      productLocator: ProductLocator(processRunner: runner),
      commitHarness: CommitHarness(processRunner: runner),
      gitHookInstaller: GitHookInstaller(processRunner: runner),
      statusSink: { _ in }
    )

    let sharedOutput = try tool.build(
      ExecutionRequest(command: .build, subjects: ["SymphonyShared"], outputMode: .filtered)
    )
    let harnessCLIOutput = try tool.build(
      ExecutionRequest(command: .build, subjects: ["SymphonyHarnessCLI"], outputMode: .filtered)
    )
    let appOutput = try tool.build(
      ExecutionRequest(command: .build, subjects: ["SymphonySwiftUIApp"], outputMode: .filtered)
    )

    #expect(FileManager.default.fileExists(atPath: sharedOutput))
    #expect(FileManager.default.fileExists(atPath: harnessCLIOutput))
    #expect(FileManager.default.fileExists(atPath: appOutput))
    let sharedSubjectRoot = URL(fileURLWithPath: sharedOutput)
      .deletingLastPathComponent()
      .appendingPathComponent("subjects/SymphonyShared", isDirectory: true)
    let sharedSubjectSummary = try String(
      contentsOf: sharedSubjectRoot.appendingPathComponent("summary.txt"),
      encoding: .utf8
    )
    #expect(sharedSubjectSummary.contains("subject: SymphonyShared"))
    #expect(!sharedSubjectSummary.contains("product:"))
    let sharedSubjectIndex = try String(
      contentsOf: sharedSubjectRoot.appendingPathComponent("index.json"),
      encoding: .utf8
    )
    #expect(!sharedSubjectIndex.contains("server runs"))
    let appSummary = try String(contentsOf: URL(fileURLWithPath: appOutput), encoding: .utf8)
    #expect(appSummary.contains("shared_run_root:"))
    #expect(appSummary.contains("subject_artifact_root SymphonySwiftUIApp"))
    let appSubjectSummary = try String(
      contentsOf: URL(fileURLWithPath: appOutput)
        .deletingLastPathComponent()
        .appendingPathComponent("subjects/SymphonySwiftUIApp/summary.txt"),
      encoding: .utf8
    )
    #expect(appSubjectSummary.contains("subject: SymphonySwiftUIApp"))
    #expect(!appSubjectSummary.contains("product:"))
    #expect(
      FileManager.default.fileExists(
        atPath: URL(fileURLWithPath: appOutput)
          .deletingLastPathComponent()
          .appendingPathComponent("subjects/SymphonySwiftUIApp/summary.txt").path))
  }
}

