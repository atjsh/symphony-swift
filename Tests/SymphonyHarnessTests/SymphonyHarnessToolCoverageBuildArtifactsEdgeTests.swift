import Foundation
import Testing

@testable import SymphonyHarness

@Test func buildToolCoversRemainingClientEdgeCasesAndFallbackMessages() throws {
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

    let buildForTestingFailRunner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "xcodebuild", arguments.last == "build-for-testing" {
        return CommandResult(exitStatus: 1, stdout: "", stderr: "")
      }
      return StubProcessRunner.success()
    }
    let buildForTestingFailTool = SymphonyHarnessTool(
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
    } catch let error as SymphonyHarnessCommandFailure {
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
    let genericCoverageTool = SymphonyHarnessTool(
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
    let emptyInstallOutputTool = SymphonyHarnessTool(
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
    } catch let error as SymphonyHarnessCommandFailure {
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
    let emptyLaunchOutputTool = SymphonyHarnessTool(
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
    } catch let error as SymphonyHarnessCommandFailure {
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
    let missingUDIDTool = SymphonyHarnessTool(
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
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "missing_launch_metadata")
    }
  }
}

