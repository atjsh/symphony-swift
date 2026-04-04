import Foundation
import Testing

@testable import SymphonyHarness

@Test func buildToolBlocksClientExecutionWithoutXcodeButAllowsDryRun() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
      xcodeProjectPath: nil
    )
    let runner = RoutedProcessRunner { _, _, _, _, _ in
      Issue.record(
        "Unsupported client execution and client dry-run rendering should not invoke subprocesses when Xcode is unavailable."
      )
      return StubProcessRunner.success()
    }
    let tool = SymphonyHarnessTool(
      workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
      executionContextBuilder: ExecutionContextBuilder(),
      simulatorResolver: SimulatorResolver(
        catalog: StubSimulatorCatalog(devices: []), processRunner: runner),
      processRunner: runner,
      artifactManager: ArtifactManager(processRunner: runner),
      endpointOverrideStore: EndpointOverrideStore(),
      doctorService: StubDoctorService(
        report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []),
        rendered: "ok"),
      toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(
        capabilities: .noXcodeForTests),
      productLocator: ProductLocator(processRunner: runner),
      commitHarness: CommitHarness(processRunner: runner),
      gitHookInstaller: GitHookInstaller(processRunner: runner),
      statusSink: { _ in }
    )

    let buildDryRun = try tool.build(
      BuildCommandRequest(
        product: .client, scheme: nil, platform: nil, simulator: nil, workerID: 0, dryRun: true,
        buildForTesting: false, outputMode: .filtered, currentDirectory: repoRoot)
    )
    #expect(buildDryRun.contains("xcodebuild"))
    #expect(buildDryRun.contains("platform=iOS Simulator,name=iPhone 17"))

    let runDryRun = try tool.run(
      RunCommandRequest(
        product: .client, scheme: nil, platform: nil, simulator: nil, workerID: 0, dryRun: true,
        serverURL: nil, host: nil, port: nil, environment: [:], outputMode: .filtered,
        currentDirectory: repoRoot)
    )
    #expect(runDryRun.contains("xcodebuild"))

    for operation in [
      {
        try tool.build(
          BuildCommandRequest(
            product: .client, scheme: nil, platform: nil, simulator: nil, workerID: 0,
            dryRun: false, buildForTesting: false, outputMode: .filtered, currentDirectory: repoRoot
          ))
      },
      {
        try tool.test(
          TestCommandRequest(
            product: .client, scheme: nil, platform: nil, simulator: nil, workerID: 0,
            dryRun: false, onlyTesting: [], skipTesting: [], outputMode: .filtered,
            currentDirectory: repoRoot))
      },
      {
        try tool.run(
          RunCommandRequest(
            product: .client, scheme: nil, platform: nil, simulator: nil, workerID: 0,
            dryRun: false, serverURL: nil, host: nil, port: nil, environment: [:],
            outputMode: .filtered, currentDirectory: repoRoot))
      },
      { try tool.simList(currentDirectory: repoRoot) },
      { try tool.simBoot(SimBootRequest(simulator: "iPhone 17", currentDirectory: repoRoot)) },
    ] {
      do {
        _ = try operation()
        Issue.record("Expected client and simulator commands to fail when Xcode is unavailable.")
      } catch let error as SymphonyHarnessCommandFailure {
        #expect(
          error.message
            == "not supported because the current environment has no Xcode available; Editing those sources is not encouraged"
        )
      }
    }
  }
}

@Test func buildToolCoversClientXcodeBuildTestAndCoveragePaths() throws {
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
    let coverageJSON = #"""
      {
        "targets": [
          {
            "buildProductPath": "/tmp/Symphony.app",
            "coveredLines": 3,
            "executableLines": 4,
            "files": [
              { "coveredLines": 2, "executableLines": 2, "name": "ContentView.swift", "path": "/tmp/ContentView.swift" },
              { "coveredLines": 1, "executableLines": 2, "name": "SymphonyApp.swift", "path": "/tmp/SymphonyApp.swift" }
            ],
            "name": "Symphony"
          }
        ]
      }
      """#

    let runner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "xcodebuild", arguments.last == "build-for-testing" {
        return StubProcessRunner.success("build-for-testing ok")
      }
      if command == "xcodebuild", arguments.last == "test" {
        return StubProcessRunner.success("test ok")
      }
      if command == "xcrun", arguments.prefix(4) == ["xccov", "view", "--report", "--json"] {
        return StubProcessRunner.success(coverageJSON)
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

    let dryRunBuild = try tool.build(
      BuildCommandRequest(
        product: .client,
        scheme: nil,
        platform: nil,
        simulator: "iPhone 17",
        workerID: 0,
        dryRun: true,
        buildForTesting: false,
        outputMode: .filtered,
        currentDirectory: repoRoot
      )
    )
    #expect(dryRunBuild.contains("xcodebuild"))
    #expect(dryRunBuild.contains("-scheme SymphonySwiftUIApp"))
    #expect(dryRunBuild.contains("platform=iOS Simulator,id=AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"))

    let dryRunTest = try tool.test(
      TestCommandRequest(
        product: .client,
        scheme: nil,
        platform: nil,
        simulator: "iPhone 17",
        workerID: 0,
        dryRun: true,
        onlyTesting: ["SymphonySwiftUIAppTests/BootstrapSupportTests"],
        skipTesting: ["SymphonySwiftUIAppTests/OtherTests"],
        outputMode: .filtered,
        currentDirectory: repoRoot
      )
    )
    #expect(dryRunTest.contains("-only-testing:SymphonySwiftUIAppTests/BootstrapSupportTests"))
    #expect(dryRunTest.contains("-skip-testing:SymphonySwiftUIAppTests/OtherTests"))
    #expect(dryRunTest.contains("-enableCodeCoverage"))
    #expect(dryRunTest.contains("xcrun xccov view --report --json"))

    let macOSDryRun = try tool.run(
      RunCommandRequest(
        product: .client,
        scheme: nil,
        platform: .macos,
        simulator: nil,
        workerID: 0,
        dryRun: true,
        serverURL: nil,
        host: nil,
        port: nil,
        environment: [:],
        outputMode: .filtered,
        currentDirectory: repoRoot
      )
    )
    #expect(macOSDryRun.split(separator: "\n").count == 1)
    #expect(macOSDryRun.contains("platform=macOS"))

    let buildOutput = try tool.build(
      BuildCommandRequest(
        product: .client,
        scheme: nil,
        platform: nil,
        simulator: "iPhone 17",
        workerID: 0,
        dryRun: false,
        buildForTesting: true,
        outputMode: .quiet,
        currentDirectory: repoRoot
      )
    )
    #expect(buildOutput.hasSuffix("summary.txt"))

    let testOutput = try tool.test(
      TestCommandRequest(
        product: .client,
        scheme: nil,
        platform: nil,
        simulator: "iPhone 17",
        workerID: 0,
        dryRun: false,
        onlyTesting: [],
        skipTesting: [],
        outputMode: .quiet,
        currentDirectory: repoRoot
      )
    )
    #expect(FileManager.default.fileExists(atPath: testOutput))

    let failingRunner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "xcodebuild", arguments.last == "build" {
        return StubProcessRunner.failure("client build failed")
      }
      if command == "xcodebuild", arguments.last == "test" {
        return StubProcessRunner.failure("client test failed")
      }
      return StubProcessRunner.success()
    }
    let failingTool = SymphonyHarnessTool(
      workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
      executionContextBuilder: ExecutionContextBuilder(),
      simulatorResolver: SimulatorResolver(
        catalog: StubSimulatorCatalog(devices: devices), processRunner: failingRunner),
      processRunner: failingRunner,
      artifactManager: ArtifactManager(processRunner: failingRunner),
      endpointOverrideStore: EndpointOverrideStore(),
      doctorService: StubDoctorService(
        report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []),
        rendered: "ok"),
      productLocator: ProductLocator(processRunner: failingRunner),
      commitHarness: CommitHarness(processRunner: failingRunner),
      gitHookInstaller: GitHookInstaller(processRunner: failingRunner),
      statusSink: { _ in }
    )

    do {
      _ = try failingTool.build(
        BuildCommandRequest(
          product: .client, scheme: nil, platform: nil, simulator: "iPhone 17", workerID: 0,
          dryRun: false, buildForTesting: false, outputMode: .filtered, currentDirectory: repoRoot)
      )
      Issue.record("Expected client xcodebuild failures to surface.")
    } catch let error as SymphonyHarnessCommandFailure {
      #expect(error.message == "xcodebuild build failed.")
    }

    do {
      _ = try failingTool.test(
        TestCommandRequest(
          product: .client, scheme: nil, platform: nil, simulator: "iPhone 17", workerID: 0,
          dryRun: false, onlyTesting: [], skipTesting: [], outputMode: .filtered,
          currentDirectory: repoRoot)
      )
      Issue.record("Expected client xcodebuild test failures to surface.")
    } catch let error as SymphonyHarnessCommandFailure {
      #expect(error.message == "xcodebuild test failed.")
    }
  }
}
