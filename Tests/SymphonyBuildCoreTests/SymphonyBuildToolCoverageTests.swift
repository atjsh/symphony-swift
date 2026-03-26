import Foundation
import Testing

@testable import SymphonyBuildCore

@Test func buildToolCoversBuildTestAndCoverageSuccessAndFailurePaths() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/symphony-build", isDirectory: true),
      xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
      xcodeProjectPath: nil
    )
    let coveragePath = repoRoot.appendingPathComponent(".build/server-coverage.json")
    try FileManager.default.createDirectory(
      at: coveragePath.deletingLastPathComponent(), withIntermediateDirectories: true)
    try #"""
    {
      "data": [
        {
          "files": [
            {
              "filename": "__REPO__/Sources/SymphonyRuntime/BootstrapSupport.swift",
              "summary": { "lines": { "count": 4, "covered": 4 } }
            },
            {
              "filename": "__REPO__/Sources/SymphonyServer/main.swift",
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
    """#
    .replacingOccurrences(of: "__REPO__", with: repoRoot.path)
    .write(to: coveragePath, atomically: true, encoding: .utf8)

    let signals = SignalBox()
    let runner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "swift", arguments == ["build", "--product", "SymphonyServer"] {
        return StubProcessRunner.success("swift build ok")
      }
      if command == "swift", arguments == ["test", "--filter", "SymphonyServerTests"] {
        return StubProcessRunner.success("swift test ok")
      }
      if command == "swift",
        arguments == ["test", "--enable-code-coverage", "--filter", "SymphonyServerTests"]
      {
        return StubProcessRunner.success("swift coverage ok")
      }
      if command == "swift", arguments == ["test", "--show-code-coverage-path"] {
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
      if command == "swift", arguments == ["build", "--product", "SymphonyServer"] {
        return StubProcessRunner.failure("build failed")
      }
      if command == "swift",
        arguments == ["test", "--enable-code-coverage", "--filter", "SymphonyServerTests"]
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
    } catch let error as SymphonyBuildCommandFailure {
      #expect(error.message.contains("swift build failed"))
    }

    do {
      _ = try failingTool.test(
        TestCommandRequest(
          product: .server, scheme: nil, platform: nil, simulator: nil, workerID: 0, dryRun: false,
          onlyTesting: [], skipTesting: [], outputMode: .filtered, currentDirectory: repoRoot)
      )
      Issue.record("Expected failing tests to surface.")
    } catch let error as SymphonyBuildCommandFailure {
      #expect(error.message.contains("swift test failed"))
    }

    let exportFailRunner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "swift",
        arguments == ["test", "--enable-code-coverage", "--filter", "SymphonyServerTests"]
      {
        return StubProcessRunner.success("ok")
      }
      if command == "swift", arguments == ["test", "--show-code-coverage-path"] {
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

@Test func buildToolBlocksClientExecutionWithoutXcodeButAllowsDryRun() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/symphony-build", isDirectory: true),
      xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
      xcodeProjectPath: nil
    )
    let runner = RoutedProcessRunner { _, _, _, _, _ in
      Issue.record(
        "Unsupported client execution and client dry-run rendering should not invoke subprocesses when Xcode is unavailable."
      )
      return StubProcessRunner.success()
    }
    let tool = SymphonyBuildTool(
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
      } catch let error as SymphonyBuildCommandFailure {
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
      buildStateRoot: repoRoot.appendingPathComponent(".build/symphony-build", isDirectory: true),
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

    let tool = SymphonyBuildTool(
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
    #expect(dryRunBuild.contains("-scheme Symphony"))
    #expect(dryRunBuild.contains("platform=iOS Simulator,id=AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"))

    let dryRunTest = try tool.test(
      TestCommandRequest(
        product: .client,
        scheme: nil,
        platform: nil,
        simulator: "iPhone 17",
        workerID: 0,
        dryRun: true,
        onlyTesting: ["SymphonyTests/BootstrapSupportTests"],
        skipTesting: ["SymphonyTests/OtherTests"],
        outputMode: .filtered,
        currentDirectory: repoRoot
      )
    )
    #expect(dryRunTest.contains("-only-testing:SymphonyTests/BootstrapSupportTests"))
    #expect(dryRunTest.contains("-skip-testing:SymphonyTests/OtherTests"))
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
    let failingTool = SymphonyBuildTool(
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
    } catch let error as SymphonyBuildCommandFailure {
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
    } catch let error as SymphonyBuildCommandFailure {
      #expect(error.message == "xcodebuild test failed.")
    }
  }
}

@Test func buildToolCoversRunServerAndClientLaunchPaths() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/symphony-build", isDirectory: true),
      xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
      xcodeProjectPath: nil
    )
    let runner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "swift", arguments == ["build", "--product", "SymphonyServer"] {
        return StubProcessRunner.success("built")
      }
      if command == "swift", arguments == ["build", "--show-bin-path"] {
        return StubProcessRunner.success("/tmp/Build\n")
      }
      return StubProcessRunner.success()
    }
    let tool = SymphonyBuildTool(
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
      productLocator: ProductLocator(processRunner: runner),
      commitHarness: CommitHarness(processRunner: runner),
      gitHookInstaller: GitHookInstaller(processRunner: runner),
      statusSink: { _ in }
    )

    let serverOutput = try tool.run(
      RunCommandRequest(
        product: .server,
        scheme: nil,
        platform: nil,
        simulator: nil,
        workerID: 0,
        dryRun: false,
        serverURL: nil,
        host: nil,
        port: nil,
        environment: ["CUSTOM": "1"],
        outputMode: .filtered,
        currentDirectory: repoRoot
      )
    )
    #expect(serverOutput.hasSuffix("summary.txt"))
    #expect(runner.startedDetachedExecutions.count == 1)
    #expect(runner.startedDetachedExecutions[0].executablePath == "/tmp/Build/SymphonyServer")
    #expect(runner.startedDetachedExecutions[0].environment == ["CUSTOM": "1"])
    let serverSummary = try String(contentsOf: URL(fileURLWithPath: serverOutput), encoding: .utf8)
    #expect(serverSummary.contains("swift build --product SymphonyServer"))
    #expect(serverSummary.contains("swift build --show-bin-path"))

    let clientRunner = RoutedProcessRunner { command, arguments, environment, _, _ in
      let invocation = ([command] + arguments).joined(separator: " ")
      if command == "xcodebuild", arguments.last == "build" {
        return StubProcessRunner.success("built")
      }
      if invocation.contains("-showBuildSettings") {
        return StubProcessRunner.success(
          #"[{"buildSettings":{"TARGET_BUILD_DIR":"/tmp/Build","FULL_PRODUCT_NAME":"Symphony.app","EXECUTABLE_PATH":"Symphony.app/Contents/MacOS/Symphony","PRODUCT_BUNDLE_IDENTIFIER":"com.example.client"}}]"#
        )
      }
      if command == "xcrun",
        arguments == ["simctl", "bootstatus", "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", "-b"]
      {
        return StubProcessRunner.success()
      }
      if command == "xcrun", arguments.prefix(2) == ["simctl", "install"] {
        return StubProcessRunner.success("installed")
      }
      if command == "xcrun", arguments.prefix(2) == ["simctl", "launch"] {
        #expect(environment["SIMCTL_CHILD_FOO"] == "bar")
        #expect(environment["SIMCTL_CHILD_SYMPHONY_SERVER_HOST"] == "localhost")
        return StubProcessRunner.success("launched")
      }
      return StubProcessRunner.success()
    }
    let clientTool = SymphonyBuildTool(
      workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
      executionContextBuilder: ExecutionContextBuilder(),
      simulatorResolver: SimulatorResolver(
        catalog: StubSimulatorCatalog(devices: [
          SimulatorDevice(
            name: "iPhone 17", udid: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", state: "Shutdown",
            runtime: "iOS 18")
        ]),
        processRunner: clientRunner
      ),
      processRunner: clientRunner,
      artifactManager: ArtifactManager(processRunner: clientRunner),
      endpointOverrideStore: EndpointOverrideStore(),
      doctorService: StubDoctorService(
        report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []),
        rendered: "ok"),
      productLocator: ProductLocator(processRunner: clientRunner),
      commitHarness: CommitHarness(processRunner: clientRunner),
      gitHookInstaller: GitHookInstaller(processRunner: clientRunner),
      statusSink: { _ in }
    )
    let clientOutput = try clientTool.run(
      RunCommandRequest(
        product: .client,
        scheme: nil,
        platform: nil,
        simulator: "iPhone 17",
        workerID: 0,
        dryRun: false,
        serverURL: nil,
        host: nil,
        port: nil,
        environment: ["FOO": "bar"],
        outputMode: .filtered,
        currentDirectory: repoRoot
      )
    )
    #expect(clientOutput.hasSuffix("summary.txt"))

    let missingMetadataRunner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "xcodebuild", arguments.last == "build" {
        return StubProcessRunner.success("built")
      }
      if ([command] + arguments).joined(separator: " ").contains("-showBuildSettings") {
        return StubProcessRunner.success(
          #"[{"buildSettings":{"TARGET_BUILD_DIR":"/tmp/Build","FULL_PRODUCT_NAME":"Symphony.app"}}]"#
        )
      }
      return StubProcessRunner.success()
    }
    let missingMetadataTool = SymphonyBuildTool(
      workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
      executionContextBuilder: ExecutionContextBuilder(),
      simulatorResolver: SimulatorResolver(
        catalog: StubSimulatorCatalog(devices: [
          SimulatorDevice(
            name: "iPhone 17", udid: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", state: "Shutdown",
            runtime: "iOS 18")
        ]),
        processRunner: missingMetadataRunner
      ),
      processRunner: missingMetadataRunner,
      artifactManager: ArtifactManager(processRunner: missingMetadataRunner),
      endpointOverrideStore: EndpointOverrideStore(),
      doctorService: StubDoctorService(
        report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []),
        rendered: "ok"),
      productLocator: ProductLocator(processRunner: missingMetadataRunner),
      commitHarness: CommitHarness(processRunner: missingMetadataRunner),
      gitHookInstaller: GitHookInstaller(processRunner: missingMetadataRunner),
      statusSink: { _ in }
    )
    do {
      _ = try missingMetadataTool.run(
        RunCommandRequest(
          product: .client, scheme: nil, platform: nil, simulator: "iPhone 17", workerID: 0,
          dryRun: false, serverURL: nil, host: nil, port: nil, environment: [:],
          outputMode: .filtered, currentDirectory: repoRoot)
      )
      Issue.record("Expected missing launch metadata to fail.")
    } catch let error as SymphonyBuildError {
      #expect(error.code == "missing_launch_metadata")
    }
  }
}

@Test func buildToolCoversRunClientFailureAndSimulatorManagementPaths() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/symphony-build", isDirectory: true),
      xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
      xcodeProjectPath: nil
    )
    let devices = [
      SimulatorDevice(
        name: "iPhone 17", udid: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", state: "Shutdown",
        runtime: "iOS 18")
    ]

    let installFailRunner = RoutedProcessRunner { command, arguments, _, _, _ in
      let invocation = ([command] + arguments).joined(separator: " ")
      if command == "xcodebuild", arguments.last == "build" {
        return StubProcessRunner.success("built")
      }
      if invocation.contains("-showBuildSettings") {
        return StubProcessRunner.success(
          #"[{"buildSettings":{"TARGET_BUILD_DIR":"/tmp/Build","FULL_PRODUCT_NAME":"Symphony.app","PRODUCT_BUNDLE_IDENTIFIER":"com.example.client"}}]"#
        )
      }
      if command == "xcrun",
        arguments == ["simctl", "bootstatus", "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", "-b"]
      {
        return StubProcessRunner.success()
      }
      if command == "xcrun", arguments.prefix(2) == ["simctl", "install"] {
        return StubProcessRunner.failure("install failed")
      }
      return StubProcessRunner.success()
    }
    let installFailTool = SymphonyBuildTool(
      workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
      executionContextBuilder: ExecutionContextBuilder(),
      simulatorResolver: SimulatorResolver(
        catalog: StubSimulatorCatalog(devices: devices), processRunner: installFailRunner),
      processRunner: installFailRunner,
      artifactManager: ArtifactManager(processRunner: installFailRunner),
      endpointOverrideStore: EndpointOverrideStore(),
      doctorService: StubDoctorService(
        report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []),
        rendered: "ok"),
      productLocator: ProductLocator(processRunner: installFailRunner),
      commitHarness: CommitHarness(processRunner: installFailRunner),
      gitHookInstaller: GitHookInstaller(processRunner: installFailRunner),
      statusSink: { _ in }
    )
    do {
      _ = try installFailTool.run(
        RunCommandRequest(
          product: .client, scheme: nil, platform: nil, simulator: "iPhone 17", workerID: 0,
          dryRun: false, serverURL: nil, host: nil, port: nil, environment: [:],
          outputMode: .filtered, currentDirectory: repoRoot)
      )
      Issue.record("Expected install failures to fail the launch step.")
    } catch let error as SymphonyBuildCommandFailure {
      #expect(error.message == "The launch step failed.")
    }

    let launchFailRunner = RoutedProcessRunner { command, arguments, _, _, _ in
      let invocation = ([command] + arguments).joined(separator: " ")
      if command == "xcodebuild", arguments.last == "build" {
        return StubProcessRunner.success("built")
      }
      if invocation.contains("-showBuildSettings") {
        return StubProcessRunner.success(
          #"[{"buildSettings":{"TARGET_BUILD_DIR":"/tmp/Build","FULL_PRODUCT_NAME":"Symphony.app","PRODUCT_BUNDLE_IDENTIFIER":"com.example.client"}}]"#
        )
      }
      if command == "xcrun",
        arguments == ["simctl", "bootstatus", "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", "-b"]
      {
        return StubProcessRunner.success()
      }
      if command == "xcrun", arguments.prefix(2) == ["simctl", "install"] {
        return StubProcessRunner.success("installed")
      }
      if command == "xcrun", arguments.prefix(2) == ["simctl", "launch"] {
        return StubProcessRunner.failure("launch failed")
      }
      return StubProcessRunner.success()
    }
    let launchFailTool = SymphonyBuildTool(
      workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
      executionContextBuilder: ExecutionContextBuilder(),
      simulatorResolver: SimulatorResolver(
        catalog: StubSimulatorCatalog(devices: devices), processRunner: launchFailRunner),
      processRunner: launchFailRunner,
      artifactManager: ArtifactManager(processRunner: launchFailRunner),
      endpointOverrideStore: EndpointOverrideStore(),
      doctorService: StubDoctorService(
        report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []),
        rendered: "ok"),
      productLocator: ProductLocator(processRunner: launchFailRunner),
      commitHarness: CommitHarness(processRunner: launchFailRunner),
      gitHookInstaller: GitHookInstaller(processRunner: launchFailRunner),
      statusSink: { _ in }
    )
    do {
      _ = try launchFailTool.run(
        RunCommandRequest(
          product: .client, scheme: nil, platform: nil, simulator: "iPhone 17", workerID: 0,
          dryRun: false, serverURL: nil, host: nil, port: nil, environment: [:],
          outputMode: .filtered, currentDirectory: repoRoot)
      )
      Issue.record("Expected launch failures to fail the launch step.")
    } catch let error as SymphonyBuildCommandFailure {
      #expect(error.message == "The launch step failed.")
    }

    let listBootRunner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "xcrun", arguments == ["simctl", "list", "devices", "available", "-j"] {
        return StubProcessRunner.success(
          #"{"devices":{"iOS 18":[{"name":"iPhone 17","udid":"AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA","state":"Shutdown"}]}}"#
        )
      }
      if command == "xcrun",
        arguments == ["simctl", "bootstatus", "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", "-b"]
      {
        return StubProcessRunner.success()
      }
      return StubProcessRunner.success()
    }
    let managementTool = SymphonyBuildTool(
      workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
      executionContextBuilder: ExecutionContextBuilder(),
      simulatorResolver: SimulatorResolver(
        catalog: StubSimulatorCatalog(devices: devices), processRunner: listBootRunner),
      processRunner: listBootRunner,
      artifactManager: ArtifactManager(processRunner: listBootRunner),
      endpointOverrideStore: EndpointOverrideStore(),
      doctorService: StubDoctorService(
        report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []),
        rendered: "ok"),
      productLocator: ProductLocator(processRunner: listBootRunner),
      commitHarness: CommitHarness(processRunner: listBootRunner),
      gitHookInstaller: GitHookInstaller(processRunner: listBootRunner),
      statusSink: { _ in }
    )
    #expect(
      try managementTool.simList(currentDirectory: repoRoot).contains(
        "iPhone 17 (AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA)"))
    #expect(
      try managementTool.simBoot(SimBootRequest(simulator: "iPhone 17", currentDirectory: repoRoot))
        == "iPhone 17 (AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA)")
  }
}

@Test func buildToolCoversArtifactsDoctorRunFallbackAndDefaultStatusSink() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/symphony-build", isDirectory: true),
      xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
      xcodeProjectPath: nil
    )
    let devices = [
      SimulatorDevice(
        name: "iPhone 17", udid: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", state: "Shutdown",
        runtime: "iOS 18")
    ]

    let defaultSinkCoverageRunner = RoutedProcessRunner { command, arguments, _, _, observation in
      if command == "xcodebuild", arguments.last == "test",
        arguments.contains("-enableCodeCoverage"), arguments.contains("YES")
      {
        observation?.onLine?(.stdout, "warning: default sink covered")
        return StubProcessRunner.success("coverage ok")
      }
      if command == "xcrun", arguments.prefix(4) == ["xccov", "view", "--report", "--json"] {
        return StubProcessRunner.success("not json")
      }
      return StubProcessRunner.success()
    }
    let defaultSinkTool = SymphonyBuildTool(
      workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
      executionContextBuilder: ExecutionContextBuilder(),
      simulatorResolver: SimulatorResolver(
        catalog: StubSimulatorCatalog(devices: devices), processRunner: defaultSinkCoverageRunner),
      processRunner: defaultSinkCoverageRunner,
      artifactManager: ArtifactManager(processRunner: defaultSinkCoverageRunner),
      endpointOverrideStore: EndpointOverrideStore(),
      doctorService: StubDoctorService(
        report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []),
        rendered: "ok"),
      productLocator: ProductLocator(processRunner: defaultSinkCoverageRunner),
      commitHarness: CommitHarness(processRunner: defaultSinkCoverageRunner),
      gitHookInstaller: GitHookInstaller(processRunner: defaultSinkCoverageRunner)
    )
    do {
      let testOutput = try defaultSinkTool.test(
        TestCommandRequest(
          product: .client, scheme: nil, platform: nil, simulator: "iPhone 17", workerID: 0,
          dryRun: false, onlyTesting: [], skipTesting: [], outputMode: .full,
          currentDirectory: repoRoot)
      )
      #expect(FileManager.default.fileExists(atPath: testOutput))
    }

    let runBuildFailRunner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "swift", arguments == ["build", "--product", "SymphonyServer"] {
        return StubProcessRunner.failure("run build failed")
      }
      return StubProcessRunner.success()
    }
    let runBuildFailTool = SymphonyBuildTool(
      workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
      executionContextBuilder: ExecutionContextBuilder(),
      simulatorResolver: SimulatorResolver(
        catalog: StubSimulatorCatalog(devices: []), processRunner: runBuildFailRunner),
      processRunner: runBuildFailRunner,
      artifactManager: ArtifactManager(processRunner: runBuildFailRunner),
      endpointOverrideStore: EndpointOverrideStore(),
      doctorService: StubDoctorService(
        report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []),
        rendered: "ok"),
      productLocator: ProductLocator(processRunner: runBuildFailRunner),
      commitHarness: CommitHarness(processRunner: runBuildFailRunner),
      gitHookInstaller: GitHookInstaller(processRunner: runBuildFailRunner),
      statusSink: { _ in }
    )
    do {
      _ = try runBuildFailTool.run(
        RunCommandRequest(
          product: .server, scheme: nil, platform: nil, simulator: nil, workerID: 0, dryRun: false,
          serverURL: nil, host: nil, port: nil, environment: [:], outputMode: .filtered,
          currentDirectory: repoRoot)
      )
      Issue.record("Expected run build failures to surface.")
    } catch let error as SymphonyBuildCommandFailure {
      #expect(error.message == "The run build step failed.")
    }

    let clientRunBuildFailRunner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "xcodebuild", arguments.last == "build" {
        return StubProcessRunner.failure("client run build failed")
      }
      return StubProcessRunner.success()
    }
    let clientRunBuildFailTool = SymphonyBuildTool(
      workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
      executionContextBuilder: ExecutionContextBuilder(),
      simulatorResolver: SimulatorResolver(
        catalog: StubSimulatorCatalog(devices: devices), processRunner: clientRunBuildFailRunner),
      processRunner: clientRunBuildFailRunner,
      artifactManager: ArtifactManager(processRunner: clientRunBuildFailRunner),
      endpointOverrideStore: EndpointOverrideStore(),
      doctorService: StubDoctorService(
        report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []),
        rendered: "ok"),
      productLocator: ProductLocator(processRunner: clientRunBuildFailRunner),
      commitHarness: CommitHarness(processRunner: clientRunBuildFailRunner),
      gitHookInstaller: GitHookInstaller(processRunner: clientRunBuildFailRunner),
      statusSink: { _ in }
    )
    do {
      _ = try clientRunBuildFailTool.run(
        RunCommandRequest(
          product: .client, scheme: nil, platform: nil, simulator: "iPhone 17", workerID: 0,
          dryRun: false, serverURL: nil, host: nil, port: nil, environment: [:],
          outputMode: .filtered, currentDirectory: repoRoot)
      )
      Issue.record("Expected client run build failures to surface.")
    } catch let error as SymphonyBuildCommandFailure {
      #expect(error.message == "The run build step failed.")
    }

    let noExecutableRunner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "swift", arguments == ["build", "--product", "SymphonyServer"] {
        return StubProcessRunner.success("built")
      }
      if command == "swift", arguments == ["build", "--show-bin-path"] {
        return StubProcessRunner.success("/tmp/Build\n")
      }
      return StubProcessRunner.success()
    }
    let noExecutableTool = SymphonyBuildTool(
      workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
      executionContextBuilder: ExecutionContextBuilder(),
      simulatorResolver: SimulatorResolver(
        catalog: StubSimulatorCatalog(devices: [
          SimulatorDevice(
            name: "iPhone 17", udid: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", state: "Shutdown",
            runtime: "iOS 18")
        ]),
        processRunner: noExecutableRunner
      ),
      processRunner: noExecutableRunner,
      artifactManager: ArtifactManager(processRunner: noExecutableRunner),
      endpointOverrideStore: EndpointOverrideStore(),
      doctorService: StubDoctorService(
        report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []),
        rendered: "ok"),
      productLocator: ProductLocator(processRunner: noExecutableRunner),
      commitHarness: CommitHarness(processRunner: noExecutableRunner),
      gitHookInstaller: GitHookInstaller(processRunner: noExecutableRunner),
      statusSink: { _ in }
    )
    let serverFallbackOutput = try noExecutableTool.run(
      RunCommandRequest(
        product: .server, scheme: nil, platform: nil, simulator: nil, workerID: 0, dryRun: false,
        serverURL: nil, host: nil, port: nil, environment: [:], outputMode: .filtered,
        currentDirectory: repoRoot)
    )
    #expect(serverFallbackOutput.hasSuffix("summary.txt"))

    let dryRunUDIDOutput = try noExecutableTool.run(
      RunCommandRequest(
        product: .client, scheme: nil, platform: nil,
        simulator: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", workerID: 0, dryRun: true,
        serverURL: nil, host: nil, port: nil, environment: [:], outputMode: .filtered,
        currentDirectory: repoRoot)
    )
    #expect(
      dryRunUDIDOutput.contains("platform=iOS Simulator,id=AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"))

    let manager = ArtifactManager(processRunner: StubProcessRunner())
    let worker = try WorkerScope(id: 0)
    let executionContext = try ExecutionContextBuilder().make(
      workspace: workspace,
      worker: worker,
      command: .build,
      runID: "artifact",
      date: Date(timeIntervalSince1970: 1_700_000_500)
    )
    _ = try manager.recordXcodeExecution(
      workspace: workspace,
      executionContext: executionContext,
      command: .build,
      product: .server,
      scheme: "SymphonyServer",
      destination: ResolvedDestination(
        platform: .macos, displayName: "macOS", simulatorName: nil, simulatorUDID: nil,
        xcodeDestination: expectedHostMacOSDestination()),
      invocation: "xcodebuild build",
      exitStatus: 0,
      combinedOutput: "",
      startedAt: Date(timeIntervalSince1970: 1_700_000_500),
      endedAt: Date(timeIntervalSince1970: 1_700_000_530)
    )
    let artifactsTool = SymphonyBuildTool(
      workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
      executionContextBuilder: ExecutionContextBuilder(),
      simulatorResolver: SimulatorResolver(
        catalog: StubSimulatorCatalog(devices: []), processRunner: StubProcessRunner()),
      processRunner: StubProcessRunner(),
      artifactManager: manager,
      endpointOverrideStore: EndpointOverrideStore(),
      doctorService: StubDoctorService(
        report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []),
        rendered: "ok"),
      productLocator: ProductLocator(processRunner: StubProcessRunner()),
      commitHarness: CommitHarness(processRunner: StubProcessRunner()),
      gitHookInstaller: GitHookInstaller(processRunner: StubProcessRunner()),
      statusSink: { _ in }
    )
    let artifactsOutput = try artifactsTool.artifacts(
      ArtifactsCommandRequest(command: .build, latest: true, runID: nil, currentDirectory: repoRoot)
    )
    #expect(artifactsOutput.contains("summary.txt"))

    let unhealthyDoctorTool = SymphonyBuildTool(
      doctorService: StubDoctorService(
        report: DiagnosticsReport(
          issues: [DiagnosticIssue(severity: .error, code: "bad", message: "bad")],
          checkedPaths: [], checkedExecutables: []),
        rendered: "rendered-bad"
      )
    )
    do {
      _ = try unhealthyDoctorTool.doctor(
        DoctorCommandRequest(strict: false, json: false, quiet: false, currentDirectory: repoRoot)
      )
      Issue.record("Expected unhealthy non-strict doctor runs to fail.")
    } catch let error as SymphonyBuildCommandFailure {
      #expect(error.message == "rendered-bad")
    }
  }
}

@Test func buildToolCoversSwiftPMCoverageAndRunFallbackFailures() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/symphony-build", isDirectory: true),
      xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
      xcodeProjectPath: nil
    )

    let dryRunTool = SymphonyBuildTool(
      workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
      executionContextBuilder: ExecutionContextBuilder(),
      simulatorResolver: SimulatorResolver(
        catalog: StubSimulatorCatalog(devices: []), processRunner: StubProcessRunner()),
      processRunner: StubProcessRunner(),
      artifactManager: ArtifactManager(processRunner: StubProcessRunner()),
      endpointOverrideStore: EndpointOverrideStore(),
      doctorService: StubDoctorService(
        report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []),
        rendered: "ok"),
      productLocator: ProductLocator(processRunner: StubProcessRunner()),
      commitHarness: CommitHarness(processRunner: StubProcessRunner()),
      gitHookInstaller: GitHookInstaller(processRunner: StubProcessRunner()),
      statusSink: { _ in }
    )
    let runDryRun = try dryRunTool.run(
      RunCommandRequest(
        product: .server,
        scheme: nil,
        platform: nil,
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
    #expect(runDryRun.contains("swift build --product SymphonyServer"))
    #expect(runDryRun.contains("swift build --show-bin-path"))
    #expect(runDryRun.contains("<built-product>/SymphonyServer"))

    let pathFailureRunner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "swift",
        arguments == ["test", "--enable-code-coverage", "--filter", "SymphonyServerTests"]
      {
        return StubProcessRunner.success("coverage ok")
      }
      if command == "swift", arguments == ["test", "--show-code-coverage-path"] {
        return StubProcessRunner.failure("no swiftpm coverage path")
      }
      return StubProcessRunner.success()
    }
    let pathFailureTool = makeCoverageTool(
      workspace: workspace, runner: pathFailureRunner, statusSink: { _ in })
    let pathFailureOutput = try pathFailureTool.test(
      TestCommandRequest(
        product: .server, scheme: nil, platform: nil, simulator: nil, workerID: 0, dryRun: false,
        onlyTesting: [], skipTesting: [], outputMode: .filtered, currentDirectory: repoRoot)
    )
    #expect(FileManager.default.fileExists(atPath: pathFailureOutput))

    let emptyFailurePathRunner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "swift",
        arguments == ["test", "--enable-code-coverage", "--filter", "SymphonyServerTests"]
      {
        return StubProcessRunner.success("coverage ok")
      }
      if command == "swift", arguments == ["test", "--show-code-coverage-path"] {
        return CommandResult(exitStatus: 1, stdout: "", stderr: "")
      }
      return StubProcessRunner.success()
    }
    let emptyFailurePathTool = makeCoverageTool(
      workspace: workspace, runner: emptyFailurePathRunner, statusSink: { _ in })
    let emptyFailureOutput = try emptyFailurePathTool.test(
      TestCommandRequest(
        product: .server, scheme: nil, platform: nil, simulator: nil, workerID: 0, dryRun: false,
        onlyTesting: [], skipTesting: [], outputMode: .filtered, currentDirectory: repoRoot)
    )
    #expect(FileManager.default.fileExists(atPath: emptyFailureOutput))

    let emptyPathRunner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "swift",
        arguments == ["test", "--enable-code-coverage", "--filter", "SymphonyServerTests"]
      {
        return StubProcessRunner.success("coverage ok")
      }
      if command == "swift", arguments == ["test", "--show-code-coverage-path"] {
        return StubProcessRunner.success("\n")
      }
      return StubProcessRunner.success()
    }
    let emptyPathTool = makeCoverageTool(
      workspace: workspace, runner: emptyPathRunner, statusSink: { _ in })
    let emptyPathOutput = try emptyPathTool.test(
      TestCommandRequest(
        product: .server, scheme: nil, platform: nil, simulator: nil, workerID: 0, dryRun: false,
        onlyTesting: [], skipTesting: [], outputMode: .filtered, currentDirectory: repoRoot)
    )
    #expect(FileManager.default.fileExists(atPath: emptyPathOutput))

    let throwingCoverageRunner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "swift",
        arguments == ["test", "--enable-code-coverage", "--filter", "SymphonyServerTests"]
      {
        return StubProcessRunner.success("coverage ok")
      }
      if command == "swift", arguments == ["test", "--show-code-coverage-path"] {
        struct GenericFailure: Error {}
        throw GenericFailure()
      }
      return StubProcessRunner.success()
    }
    let throwingCoverageTool = makeCoverageTool(
      workspace: workspace, runner: throwingCoverageRunner, statusSink: { _ in })
    let throwingOutput = try throwingCoverageTool.test(
      TestCommandRequest(
        product: .server, scheme: nil, platform: nil, simulator: nil, workerID: 0, dryRun: false,
        onlyTesting: [], skipTesting: [], outputMode: .filtered, currentDirectory: repoRoot)
    )
    #expect(FileManager.default.fileExists(atPath: throwingOutput))

    let binPathFailureRunner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "swift", arguments == ["build", "--product", "SymphonyServer"] {
        return StubProcessRunner.success("built")
      }
      if command == "swift", arguments == ["build", "--show-bin-path"] {
        return StubProcessRunner.failure("bin path failed")
      }
      return StubProcessRunner.success()
    }
    let binPathFailureTool = SymphonyBuildTool(
      workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
      executionContextBuilder: ExecutionContextBuilder(),
      simulatorResolver: SimulatorResolver(
        catalog: StubSimulatorCatalog(devices: []), processRunner: binPathFailureRunner),
      processRunner: binPathFailureRunner,
      artifactManager: ArtifactManager(processRunner: binPathFailureRunner),
      endpointOverrideStore: EndpointOverrideStore(),
      doctorService: StubDoctorService(
        report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []),
        rendered: "ok"),
      productLocator: ProductLocator(processRunner: binPathFailureRunner),
      commitHarness: CommitHarness(processRunner: binPathFailureRunner),
      gitHookInstaller: GitHookInstaller(processRunner: binPathFailureRunner),
      statusSink: { _ in }
    )
    do {
      _ = try binPathFailureTool.run(
        RunCommandRequest(
          product: .server, scheme: nil, platform: nil, simulator: nil, workerID: 0, dryRun: false,
          serverURL: nil, host: nil, port: nil, environment: [:], outputMode: .filtered,
          currentDirectory: repoRoot)
      )
      Issue.record("Expected failing bin-path lookups to fail launch.")
    } catch let error as SymphonyBuildCommandFailure {
      #expect(error.message == "The launch step failed.")
    }

    let emptyBinPathRunner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "swift", arguments == ["build", "--product", "SymphonyServer"] {
        return StubProcessRunner.success("built")
      }
      if command == "swift", arguments == ["build", "--show-bin-path"] {
        return StubProcessRunner.success("\n")
      }
      return StubProcessRunner.success()
    }
    let emptyBinPathTool = SymphonyBuildTool(
      workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
      executionContextBuilder: ExecutionContextBuilder(),
      simulatorResolver: SimulatorResolver(
        catalog: StubSimulatorCatalog(devices: []), processRunner: emptyBinPathRunner),
      processRunner: emptyBinPathRunner,
      artifactManager: ArtifactManager(processRunner: emptyBinPathRunner),
      endpointOverrideStore: EndpointOverrideStore(),
      doctorService: StubDoctorService(
        report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []),
        rendered: "ok"),
      productLocator: ProductLocator(processRunner: emptyBinPathRunner),
      commitHarness: CommitHarness(processRunner: emptyBinPathRunner),
      gitHookInstaller: GitHookInstaller(processRunner: emptyBinPathRunner),
      statusSink: { _ in }
    )
    do {
      _ = try emptyBinPathTool.run(
        RunCommandRequest(
          product: .server, scheme: nil, platform: nil, simulator: nil, workerID: 0, dryRun: false,
          serverURL: nil, host: nil, port: nil, environment: [:], outputMode: .filtered,
          currentDirectory: repoRoot)
      )
      Issue.record("Expected empty bin-path responses to fail launch.")
    } catch let error as SymphonyBuildCommandFailure {
      #expect(error.message == "The launch step failed.")
    }
  }
}

@Test func buildToolCoversRemainingClientEdgeCasesAndFallbackMessages() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/symphony-build", isDirectory: true),
      xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
      xcodeProjectPath: nil
    )
    let devices = [
      SimulatorDevice(
        name: "iPhone 17", udid: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", state: "Shutdown",
        runtime: "iOS 18")
    ]

    let buildForTestingFailRunner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "xcodebuild", arguments.last == "build-for-testing" {
        return CommandResult(exitStatus: 1, stdout: "", stderr: "")
      }
      return StubProcessRunner.success()
    }
    let buildForTestingFailTool = SymphonyBuildTool(
      workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
      executionContextBuilder: ExecutionContextBuilder(),
      simulatorResolver: SimulatorResolver(
        catalog: StubSimulatorCatalog(devices: devices), processRunner: buildForTestingFailRunner),
      processRunner: buildForTestingFailRunner,
      artifactManager: ArtifactManager(processRunner: buildForTestingFailRunner),
      endpointOverrideStore: EndpointOverrideStore(),
      doctorService: StubDoctorService(
        report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []),
        rendered: "ok"),
      productLocator: ProductLocator(processRunner: buildForTestingFailRunner),
      commitHarness: CommitHarness(processRunner: buildForTestingFailRunner),
      gitHookInstaller: GitHookInstaller(processRunner: buildForTestingFailRunner),
      statusSink: { _ in }
    )
    do {
      _ = try buildForTestingFailTool.build(
        BuildCommandRequest(
          product: .client, scheme: nil, platform: nil, simulator: "iPhone 17", workerID: 0,
          dryRun: false, buildForTesting: true, outputMode: .filtered, currentDirectory: repoRoot)
      )
      Issue.record("Expected build-for-testing failures to keep their specific error message.")
    } catch let error as SymphonyBuildCommandFailure {
      #expect(error.message == "xcodebuild build-for-testing failed.")
    }

    let genericCoverageRunner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "xcodebuild", arguments.last == "test" {
        return StubProcessRunner.success("test ok")
      }
      if command == "xcrun", arguments.prefix(4) == ["xccov", "view", "--report", "--json"] {
        struct GenericCoverageFailure: Error {}
        throw GenericCoverageFailure()
      }
      return StubProcessRunner.success()
    }
    let genericCoverageTool = SymphonyBuildTool(
      workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
      executionContextBuilder: ExecutionContextBuilder(),
      simulatorResolver: SimulatorResolver(
        catalog: StubSimulatorCatalog(devices: devices), processRunner: genericCoverageRunner),
      processRunner: genericCoverageRunner,
      artifactManager: ArtifactManager(processRunner: genericCoverageRunner),
      endpointOverrideStore: EndpointOverrideStore(),
      doctorService: StubDoctorService(
        report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []),
        rendered: "ok"),
      productLocator: ProductLocator(processRunner: genericCoverageRunner),
      commitHarness: CommitHarness(processRunner: genericCoverageRunner),
      gitHookInstaller: GitHookInstaller(processRunner: genericCoverageRunner),
      statusSink: { _ in }
    )
    do {
      let testOutput = try genericCoverageTool.test(
        TestCommandRequest(
          product: .client, scheme: nil, platform: nil, simulator: "iPhone 17", workerID: 0,
          dryRun: false, onlyTesting: [], skipTesting: [], outputMode: .filtered,
          currentDirectory: repoRoot)
      )
      #expect(FileManager.default.fileExists(atPath: testOutput))
    }

    let emptyInstallOutputRunner = RoutedProcessRunner { command, arguments, _, _, _ in
      let invocation = ([command] + arguments).joined(separator: " ")
      if command == "xcodebuild", arguments.last == "build" {
        return StubProcessRunner.success("built")
      }
      if invocation.contains("-showBuildSettings") {
        return StubProcessRunner.success(
          #"[{"buildSettings":{"TARGET_BUILD_DIR":"/tmp/Build","FULL_PRODUCT_NAME":"Symphony.app","PRODUCT_BUNDLE_IDENTIFIER":"com.example.client"}}]"#
        )
      }
      if command == "xcrun",
        arguments == ["simctl", "bootstatus", "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", "-b"]
      {
        return StubProcessRunner.success()
      }
      if command == "xcrun", arguments.prefix(2) == ["simctl", "install"] {
        return CommandResult(exitStatus: 1, stdout: "", stderr: "")
      }
      return StubProcessRunner.success()
    }
    let emptyInstallOutputTool = SymphonyBuildTool(
      workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
      executionContextBuilder: ExecutionContextBuilder(),
      simulatorResolver: SimulatorResolver(
        catalog: StubSimulatorCatalog(devices: devices), processRunner: emptyInstallOutputRunner),
      processRunner: emptyInstallOutputRunner,
      artifactManager: ArtifactManager(processRunner: emptyInstallOutputRunner),
      endpointOverrideStore: EndpointOverrideStore(),
      doctorService: StubDoctorService(
        report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []),
        rendered: "ok"),
      productLocator: ProductLocator(processRunner: emptyInstallOutputRunner),
      commitHarness: CommitHarness(processRunner: emptyInstallOutputRunner),
      gitHookInstaller: GitHookInstaller(processRunner: emptyInstallOutputRunner),
      statusSink: { _ in }
    )
    do {
      _ = try emptyInstallOutputTool.run(
        RunCommandRequest(
          product: .client, scheme: nil, platform: nil, simulator: "iPhone 17", workerID: 0,
          dryRun: false, serverURL: nil, host: nil, port: nil, environment: [:],
          outputMode: .filtered, currentDirectory: repoRoot)
      )
      Issue.record("Expected empty install failures to use the fallback simulator install message.")
    } catch let error as SymphonyBuildCommandFailure {
      #expect(error.message == "The launch step failed.")
    }

    let emptyLaunchOutputRunner = RoutedProcessRunner { command, arguments, _, _, _ in
      let invocation = ([command] + arguments).joined(separator: " ")
      if command == "xcodebuild", arguments.last == "build" {
        return StubProcessRunner.success("built")
      }
      if invocation.contains("-showBuildSettings") {
        return StubProcessRunner.success(
          #"[{"buildSettings":{"TARGET_BUILD_DIR":"/tmp/Build","FULL_PRODUCT_NAME":"Symphony.app","PRODUCT_BUNDLE_IDENTIFIER":"com.example.client"}}]"#
        )
      }
      if command == "xcrun",
        arguments == ["simctl", "bootstatus", "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", "-b"]
      {
        return StubProcessRunner.success()
      }
      if command == "xcrun", arguments.prefix(2) == ["simctl", "install"] {
        return StubProcessRunner.success("installed")
      }
      if command == "xcrun", arguments.prefix(2) == ["simctl", "launch"] {
        return CommandResult(exitStatus: 1, stdout: "", stderr: "")
      }
      return StubProcessRunner.success()
    }
    let emptyLaunchOutputTool = SymphonyBuildTool(
      workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
      executionContextBuilder: ExecutionContextBuilder(),
      simulatorResolver: SimulatorResolver(
        catalog: StubSimulatorCatalog(devices: devices), processRunner: emptyLaunchOutputRunner),
      processRunner: emptyLaunchOutputRunner,
      artifactManager: ArtifactManager(processRunner: emptyLaunchOutputRunner),
      endpointOverrideStore: EndpointOverrideStore(),
      doctorService: StubDoctorService(
        report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []),
        rendered: "ok"),
      productLocator: ProductLocator(processRunner: emptyLaunchOutputRunner),
      commitHarness: CommitHarness(processRunner: emptyLaunchOutputRunner),
      gitHookInstaller: GitHookInstaller(processRunner: emptyLaunchOutputRunner),
      statusSink: { _ in }
    )
    do {
      _ = try emptyLaunchOutputTool.run(
        RunCommandRequest(
          product: .client, scheme: nil, platform: nil, simulator: "iPhone 17", workerID: 0,
          dryRun: false, serverURL: nil, host: nil, port: nil, environment: [:],
          outputMode: .filtered, currentDirectory: repoRoot)
      )
      Issue.record("Expected empty launch failures to use the fallback simulator launch message.")
    } catch let error as SymphonyBuildCommandFailure {
      #expect(error.message == "The launch step failed.")
    }

    let missingUDIDRunner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "xcodebuild", arguments.last == "build" {
        return StubProcessRunner.success("built")
      }
      if ([command] + arguments).joined(separator: " ").contains("-showBuildSettings") {
        return StubProcessRunner.success(
          #"[{"buildSettings":{"TARGET_BUILD_DIR":"/tmp/Build","FULL_PRODUCT_NAME":"Symphony.app","PRODUCT_BUNDLE_IDENTIFIER":"com.example.client"}}]"#
        )
      }
      return StubProcessRunner.success()
    }
    let missingUDIDTool = SymphonyBuildTool(
      workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
      executionContextBuilder: ExecutionContextBuilder(),
      simulatorResolver: SimulatorResolver(
        catalog: StubSimulatorCatalog(devices: devices), processRunner: missingUDIDRunner),
      processRunner: missingUDIDRunner,
      artifactManager: ArtifactManager(processRunner: missingUDIDRunner),
      endpointOverrideStore: EndpointOverrideStore(),
      doctorService: StubDoctorService(
        report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []),
        rendered: "ok"),
      productLocator: ProductLocator(processRunner: missingUDIDRunner),
      commitHarness: CommitHarness(processRunner: missingUDIDRunner),
      gitHookInstaller: GitHookInstaller(processRunner: missingUDIDRunner),
      statusSink: { _ in }
    )
    do {
      _ = try missingUDIDTool.run(
        RunCommandRequest(
          product: .client, scheme: nil, platform: .macos, simulator: nil, workerID: 0,
          dryRun: false, serverURL: nil, host: nil, port: nil, environment: [:],
          outputMode: .filtered, currentDirectory: repoRoot)
      )
      Issue.record("Expected non-simulator client launches to fail with missing launch metadata.")
    } catch let error as SymphonyBuildError {
      #expect(error.code == "missing_launch_metadata")
    }
  }
}

@Test func buildToolCoverageSupportsInspectionOutputsAndArtifactsForSwiftPM() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/symphony-build", isDirectory: true),
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
      "Sources/SymphonyRuntime/BootstrapSupport.swift")
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
              "filename": "__REPO__/Sources/SymphonyRuntime/BootstrapSupport.swift",
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
        arguments == ["test", "--enable-code-coverage", "--filter", "SymphonyServerTests"]
      {
        return StubProcessRunner.success("swift coverage ok")
      }
      if command == "swift", arguments == ["test", "--show-code-coverage-path"] {
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
      buildStateRoot: repoRoot.appendingPathComponent(".build/symphony-build", isDirectory: true),
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
    let tool = SymphonyBuildTool(
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
      buildStateRoot: repoRoot.appendingPathComponent(".build/symphony-build", isDirectory: true),
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
            { "filename": "__REPO__/Sources/SymphonyRuntime/BootstrapSupport.swift", "summary": { "lines": { "count": 4, "covered": 2 } } },
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
      "swift test --enable-code-coverage": StubProcessRunner.success(),
      "swift test --show-code-coverage-path": StubProcessRunner.success(coveragePath.path + "\n"),
    ])
    let tool = SymphonyBuildTool(
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

@Test func buildToolHarnessSkipsPackageInspectionWhenLLVMCovIsUnavailable() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources"), withIntermediateDirectories: true)

    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/symphony-build", isDirectory: true),
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
            { "filename": "__REPO__/Sources/SymphonyRuntime/BootstrapSupport.swift", "summary": { "lines": { "count": 4, "covered": 2 } } }
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
      "swift test --enable-code-coverage": StubProcessRunner.success(),
      "swift test --show-code-coverage-path": StubProcessRunner.success(coveragePath.path + "\n"),
    ])
    let missingLLVMCovRunner = StubProcessRunner(results: [
      "which xcrun": StubProcessRunner.failure(""),
      "which llvm-cov": StubProcessRunner.failure(""),
    ])
    let tool = SymphonyBuildTool(
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
      buildStateRoot: repoRoot.appendingPathComponent(".build/symphony-build", isDirectory: true),
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
      "swift test --enable-code-coverage": StubProcessRunner.success(),
      "swift test --show-code-coverage-path": StubProcessRunner.success(coveragePath.path + "\n"),
    ])
    let tool = SymphonyBuildTool(
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
    #expect(summary.contains("invocation: symphony-build harness --minimum-coverage 100.00 --json"))
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
      buildStateRoot: repoRoot.appendingPathComponent(".build/symphony-build", isDirectory: true),
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
      "swift test --enable-code-coverage": StubProcessRunner.success(),
      "swift test --show-code-coverage-path": StubProcessRunner.success(coveragePath.path + "\n"),
    ])
    let tool = SymphonyBuildTool(
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
        "invocation: symphony-build harness --minimum-coverage 50.00 --output-mode quiet"))
  }
}

@Test func buildToolHarnessFailureUsesCompactPreviewMessage() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources"), withIntermediateDirectories: true)

    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/symphony-build", isDirectory: true),
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
      "swift test --enable-code-coverage": StubProcessRunner.success(),
      "swift test --show-code-coverage-path": StubProcessRunner.success(coveragePath.path + "\n"),
    ])
    let tool = SymphonyBuildTool(
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
    } catch let error as SymphonyBuildCommandFailure {
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
      buildStateRoot: repoRoot.appendingPathComponent(".build/symphony-build", isDirectory: true),
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
    let tool = SymphonyBuildTool(
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
      buildStateRoot: repoRoot.appendingPathComponent(".build/symphony-build", isDirectory: true),
      xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
      xcodeProjectPath: nil
    )
    let silentRunner = RoutedProcessRunner { _, _, _, _, _ in
      Issue.record(
        "Dry-run fallback and unsupported simulator checks should not invoke subprocesses.")
      return StubProcessRunner.success()
    }

    let noXcodeTool = SymphonyBuildTool(
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
    let partialTool = SymphonyBuildTool(
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
    } catch let error as SymphonyBuildCommandFailure {
      #expect(
        error.message
          == "not supported because the current environment has no Xcode available; Editing those sources is not encouraged"
      )
    }
  }
}

@Test func buildToolDefaultInitializerPathsRemainConstructibleWithStubbedRunner() {
  let runner = StubProcessRunner()
  let tool = SymphonyBuildTool(
    processRunner: runner,
    artifactManager: ArtifactManager(processRunner: runner)
  )
  _ = tool
}

private func makeCoverageTool(
  workspace: WorkspaceContext, runner: RoutedProcessRunner,
  statusSink: @escaping @Sendable (String) -> Void
) -> SymphonyBuildTool {
  SymphonyBuildTool(
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
      capabilities: .fullyAvailableForTests),
    productLocator: ProductLocator(processRunner: runner),
    commitHarness: CommitHarness(
      processRunner: runner,
      clientCoverageLoader: { _ in
        CoverageReport(
          coveredLines: 1, executableLines: 1, lineCoverage: 1, includeTestTargets: false,
          excludedTargets: [], targets: [])
      },
      serverCoverageLoader: { _ in
        CoverageReport(
          coveredLines: 1, executableLines: 1, lineCoverage: 1, includeTestTargets: false,
          excludedTargets: [], targets: [])
      }),
    gitHookInstaller: GitHookInstaller(processRunner: runner),
    statusSink: statusSink
  )
}

private final class RoutedProcessRunner: ProcessRunning, @unchecked Sendable {
  private let handler:
    @Sendable (String, [String], [String: String], URL?, ProcessObservation?) throws ->
      CommandResult
  private let lock = NSLock()
  private(set) var startedDetachedExecutions = [
    (executablePath: String, environment: [String: String], output: URL)
  ]()

  init(
    handler:
      @escaping @Sendable (String, [String], [String: String], URL?, ProcessObservation?) throws ->
      CommandResult
  ) {
    self.handler = handler
  }

  func run(
    command: String, arguments: [String], environment: [String: String], currentDirectory: URL?,
    observation: ProcessObservation?
  ) throws -> CommandResult {
    try handler(command, arguments, environment, currentDirectory, observation)
  }

  func startDetached(
    executablePath: String, arguments: [String], environment: [String: String],
    currentDirectory: URL?, output: URL
  ) throws -> Int32 {
    lock.lock()
    startedDetachedExecutions.append((executablePath, environment, output))
    lock.unlock()
    return 4242
  }
}

private final class HarnessPackageInspectionOverwriteProcessRunner: ProcessRunning,
  @unchecked Sendable
{
  private let packageCoveragePath: String
  private let packageCoverageData: Data?
  private let showArguments: [String]
  private let reportArguments: [String]
  private let lock = NSLock()
  private var artifactsWereRewritten = false

  init(
    packageCoveragePath: String,
    sourceFilePath: String,
    profdataPath: String,
    testBinaryPath: String
  ) {
    self.packageCoveragePath = packageCoveragePath
    self.packageCoverageData = try? Data(contentsOf: URL(fileURLWithPath: packageCoveragePath))
    self.showArguments = [
      "llvm-cov", "show",
      "-instr-profile", profdataPath,
      testBinaryPath,
      sourceFilePath,
    ]
    self.reportArguments = [
      "llvm-cov", "report",
      "--show-functions",
      "-instr-profile", profdataPath,
      testBinaryPath,
      sourceFilePath,
    ]
  }

  func markArtifactsRewritten() {
    lock.lock()
    artifactsWereRewritten = true
    lock.unlock()
  }

  func run(
    command: String, arguments: [String], environment: [String: String], currentDirectory: URL?,
    observation: ProcessObservation?
  ) throws -> CommandResult {
    if command == "swift", arguments == ["test", "--enable-code-coverage"] {
      if let packageCoverageData,
        !FileManager.default.fileExists(atPath: packageCoveragePath)
      {
        let coverageURL = URL(fileURLWithPath: packageCoveragePath)
        try FileManager.default.createDirectory(
          at: coverageURL.deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
        try packageCoverageData.write(to: coverageURL)
      }
      return StubProcessRunner.success()
    }
    if command == "swift", arguments == ["test", "--show-code-coverage-path"] {
      return StubProcessRunner.success(packageCoveragePath + "\n")
    }
    if command == "xcrun", arguments == showArguments {
      return StubProcessRunner.success(
        artifactsWereRewritten
          ? """
            1|      0|func bar() {
            2|      0|    overwritten()
            3|      0|    overwrittenAgain()
            4|      0|}
          """
          : """
            1|      1|func bar() {
            2|      0|    initial()
            3|      0|    initialAgain()
            4|      1|}
          """
      )
    }
    if command == "xcrun", arguments == reportArguments {
      return StubProcessRunner.success(
        artifactsWereRewritten
          ? """
          File '':
          Name                                     Regions    Miss   Cover     Lines    Miss   Cover  Branches    Miss   Cover
          --------------------------------------------------------------------------------------------------------------------------------
          overwritten()                               2       2   0.00%         4       4   0.00%         0       0   0.00%
          --------------------------------------------------------------------------------------------------------------------------------
          TOTAL                                        2       2   0.00%         4       4   0.00%         0       0   0.00%
          """
          : """
          File '':
          Name                                     Regions    Miss   Cover     Lines    Miss   Cover  Branches    Miss   Cover
          --------------------------------------------------------------------------------------------------------------------------------
          initial()                                   2       1  50.00%         4       2  50.00%         0       0   0.00%
          --------------------------------------------------------------------------------------------------------------------------------
          TOTAL                                        2       1  50.00%         4       2  50.00%         0       0   0.00%
          """
      )
    }
    return StubProcessRunner.success()
  }

  func startDetached(
    executablePath: String, arguments: [String], environment: [String: String],
    currentDirectory: URL?, output: URL
  ) throws -> Int32 {
    0
  }
}
