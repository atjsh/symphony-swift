import Foundation
import Testing

@testable import SymphonyHarness

@Test func buildToolCoversRunServerAndClientLaunchPaths() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
      xcodeProjectPath: nil
    )
    let runner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "swift", arguments == ["build", "--scratch-path", ".build/swiftpm-cache", "--product", "symphony-server"] {
        return StubProcessRunner.success("built")
      }
      if command == "swift", arguments == ["build", "--scratch-path", ".build/swiftpm-cache", "--show-bin-path"] {
        return StubProcessRunner.success("/tmp/Build\n")
      }
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
    #expect(runner.startedDetachedExecutions[0].executablePath == "/tmp/Build/symphony-server")
    #expect(runner.startedDetachedExecutions[0].environment == ["CUSTOM": "1"])
    let serverSummary = try String(contentsOf: URL(fileURLWithPath: serverOutput), encoding: .utf8)
    #expect(serverSummary.contains("swift build --scratch-path .build/swiftpm-cache --product symphony-server"))
    #expect(serverSummary.contains("swift build --scratch-path .build/swiftpm-cache --show-bin-path"))

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
    let clientTool = SymphonyHarnessTool(
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
    let missingMetadataTool = SymphonyHarnessTool(
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
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "missing_launch_metadata")
    }
  }
}

@Test func buildToolCoversRunClientFailureAndSimulatorManagementPaths() throws {
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
    let installFailTool = SymphonyHarnessTool(
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
    } catch let error as SymphonyHarnessCommandFailure {
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
    let launchFailTool = SymphonyHarnessTool(
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
    } catch let error as SymphonyHarnessCommandFailure {
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
    let managementTool = SymphonyHarnessTool(
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

