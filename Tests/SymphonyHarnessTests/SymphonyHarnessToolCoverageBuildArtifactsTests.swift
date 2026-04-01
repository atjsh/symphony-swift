import Foundation
import Testing

@testable import SymphonyHarness

@Test func buildToolCoversArtifactsDoctorRunFallbackAndDefaultStatusSink() throws {
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
    let defaultSinkTool = SymphonyHarnessTool(
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
      if command == "swift", arguments == ["build", "--product", "symphony-server"] {
        return StubProcessRunner.failure("run build failed")
      }
      return StubProcessRunner.success()
    }
    let runBuildFailTool = SymphonyHarnessTool(
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
    } catch let error as SymphonyHarnessCommandFailure {
      #expect(error.message == "The run build step failed.")
    }

    let clientRunBuildFailRunner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "xcodebuild", arguments.last == "build" {
        return StubProcessRunner.failure("client run build failed")
      }
      return StubProcessRunner.success()
    }
    let clientRunBuildFailTool = SymphonyHarnessTool(
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
    } catch let error as SymphonyHarnessCommandFailure {
      #expect(error.message == "The run build step failed.")
    }

    let noExecutableRunner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "swift", arguments == ["build", "--product", "symphony-server"] {
        return StubProcessRunner.success("built")
      }
      if command == "swift", arguments == ["build", "--show-bin-path"] {
        return StubProcessRunner.success("/tmp/Build\n")
      }
      return StubProcessRunner.success()
    }
    let noExecutableTool = SymphonyHarnessTool(
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
    let artifactsTool = SymphonyHarnessTool(
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

    let unhealthyDoctorTool = SymphonyHarnessTool(
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
    } catch let error as SymphonyHarnessCommandFailure {
      #expect(error.message == "rendered-bad")
    }
  }
}

@Test func buildToolCoversSwiftPMCoverageAndRunFallbackFailures() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
      xcodeProjectPath: nil
    )

    let dryRunTool = SymphonyHarnessTool(
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
    #expect(runDryRun.contains("swift build --product symphony-server"))
    #expect(runDryRun.contains("swift build --show-bin-path"))
    #expect(runDryRun.contains("<built-product>/symphony-server"))

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
      if command == "swift", arguments == ["build", "--product", "symphony-server"] {
        return StubProcessRunner.success("built")
      }
      if command == "swift", arguments == ["build", "--show-bin-path"] {
        return StubProcessRunner.failure("bin path failed")
      }
      return StubProcessRunner.success()
    }
    let binPathFailureTool = SymphonyHarnessTool(
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
    } catch let error as SymphonyHarnessCommandFailure {
      #expect(error.message == "The launch step failed.")
    }

    let emptyBinPathRunner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "swift", arguments == ["build", "--product", "symphony-server"] {
        return StubProcessRunner.success("built")
      }
      if command == "swift", arguments == ["build", "--show-bin-path"] {
        return StubProcessRunner.success("\n")
      }
      return StubProcessRunner.success()
    }
    let emptyBinPathTool = SymphonyHarnessTool(
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
    } catch let error as SymphonyHarnessCommandFailure {
      #expect(error.message == "The launch step failed.")
    }
  }
}
