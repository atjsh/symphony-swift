import Foundation
import Testing

@testable import SymphonyHarness

@Test func workspaceDiscoveryPrefersWorkspaceOverProject() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(at: repoRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)
    try "# root package".write(
      to: repoRoot.appendingPathComponent("Package.swift"),
      atomically: true,
      encoding: .utf8
    )
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Symphony.xcworkspace"), withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("SymphonyApps.xcodeproj"),
      withIntermediateDirectories: true)

    let discovered = try WorkspaceDiscovery(processRunner: StubProcessRunner()).discover(
      from: repoRoot)

    #expect(discovered.projectRoot.path == repoRoot.path)
    #expect(discovered.xcodeWorkspacePath?.lastPathComponent == "Symphony.xcworkspace")
    #expect(discovered.xcodeProjectPath == nil)
  }
}

@Test func workspaceDiscoveryRejectsAmbiguousWorkspaces() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(at: repoRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)
    try "# root package".write(
      to: repoRoot.appendingPathComponent("Package.swift"),
      atomically: true,
      encoding: .utf8
    )
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("One.xcworkspace"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Two.xcworkspace"), withIntermediateDirectories: true)

    do {
      _ = try WorkspaceDiscovery(processRunner: StubProcessRunner()).discover(from: repoRoot)
      Issue.record("Expected ambiguous checked-in workspaces to fail discovery.")
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "ambiguous_workspace")
    }
  }
}

@Test func executionContextUsesWorkerScopedCanonicalPaths() throws {
  let workspace = WorkspaceContext(
    projectRoot: URL(fileURLWithPath: "/tmp/symphony-tests", isDirectory: true),
    buildStateRoot: URL(
      fileURLWithPath: "/tmp/symphony-tests/.build/harness", isDirectory: true),
    xcodeWorkspacePath: nil,
    xcodeProjectPath: nil
  )

  let worker = try WorkerScope(id: 7)
  let context = try ExecutionContextBuilder().make(
    workspace: workspace,
    worker: worker,
    command: .build,
    runID: "symphony",
    date: Date(timeIntervalSince1970: 1_700_000_000)
  )

  #expect(context.derivedDataPath.path.contains("derived-data/worker-7"))
  #expect(context.logPath.path.contains("logs/build/"))
  #expect(context.resultBundlePath.path.hasSuffix(".xcresult"))
  #expect(context.artifactRoot.lastPathComponent == "20231114-221320-symphony")
}

@Test func simulatorResolverRejectsDuplicateExactNames() throws {
  let catalog = StubSimulatorCatalog(
    devices: [
      SimulatorDevice(
        name: "iPhone 17", udid: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", state: "Shutdown",
        runtime: "iOS 18"),
      SimulatorDevice(
        name: "iPhone 17", udid: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB", state: "Shutdown",
        runtime: "iOS 18"),
    ]
  )
  let resolver = SimulatorResolver(catalog: catalog, processRunner: StubProcessRunner())

  do {
    _ = try resolver.resolve(
      DestinationSelector(platform: .iosSimulator, simulatorName: "iPhone 17"))
    Issue.record("Expected duplicate exact-name simulators to fail.")
  } catch let error as SymphonyHarnessError {
    #expect(error.code == "ambiguous_simulator_name")
  }
}

@Test func simulatorResolverSupportsUniqueFuzzyMatchAndExplicitUDID() throws {
  let catalog = StubSimulatorCatalog(
    devices: [
      SimulatorDevice(
        name: "iPhone 17", udid: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", state: "Shutdown",
        runtime: "iOS 18"),
      SimulatorDevice(
        name: "iPhone 17 Pro", udid: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB", state: "Shutdown",
        runtime: "iOS 18"),
      SimulatorDevice(
        name: "iPhone 17 Plus", udid: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC", state: "Shutdown",
        runtime: "iOS 18"),
    ]
  )
  let resolver = SimulatorResolver(catalog: catalog, processRunner: StubProcessRunner())

  let fuzzy = try resolver.resolve(
    DestinationSelector(platform: .iosSimulator, simulatorName: "plus"))
  #expect(fuzzy.simulatorUDID == "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")

  let explicitUDID = try resolver.resolve(
    DestinationSelector(
      platform: .iosSimulator,
      simulatorName: "iPhone 17",
      simulatorUDID: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"
    )
  )
  #expect(explicitUDID.simulatorUDID == "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")
}

@Test func simulatorResolverUsesHostArchitectureForMacOSDestination() throws {
  let resolver = SimulatorResolver(
    catalog: StubSimulatorCatalog(devices: []), processRunner: StubProcessRunner())
  let destination = try resolver.resolve(DestinationSelector(platform: .macos))

  #expect(destination.displayName == "macOS")
  #expect(destination.xcodeDestination == expectedHostMacOSDestination())
}

@Test func endpointOverridePrecedenceUsesCLIThenPersistedThenDefault() throws {
  try withTemporaryDirectory { directory in
    let workspace = WorkspaceContext(
      projectRoot: directory,
      buildStateRoot: directory.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: nil,
      xcodeProjectPath: nil
    )
    let store = EndpointOverrideStore()
    _ = try store.save(
      try RuntimeEndpoint(scheme: "https", host: "persisted.example.com", port: 9443), in: workspace
    )

    let cli = try store.resolve(
      workspace: workspace, serverURL: "http://cli.example.com:8081", host: "ignored.example.com",
      port: 1234)
    #expect(cli.host == "cli.example.com")
    #expect(cli.port == 8081)

    let split = try store.resolve(
      workspace: workspace, serverURL: nil, host: "split.example.com", port: 9090)
    #expect(split.host == "split.example.com")
    #expect(split.port == 9090)
    #expect(split.scheme == "https")

    try store.clear(in: workspace)
    let fallback = try store.resolve(workspace: workspace, serverURL: nil, host: nil, port: nil)
    #expect(fallback.host == "localhost")
    #expect(fallback.port == 8080)
  }
}

@Test func artifactManagerWritesSummaryIndexAndMissingBundleAnomaly() throws {
  try withTemporaryDirectory { directory in
    let workspace = WorkspaceContext(
      projectRoot: directory,
      buildStateRoot: directory.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: nil,
      xcodeProjectPath: nil
    )
    let worker = try WorkerScope(id: 0)
    let executionContext = try ExecutionContextBuilder().make(
      workspace: workspace,
      worker: worker,
      command: .build,
      runID: "symphony",
      date: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let manager = ArtifactManager(processRunner: StubProcessRunner())

    let record = try manager.recordXcodeExecution(
      workspace: workspace,
      executionContext: executionContext,
      command: .build,
      product: .client,
      scheme: "SymphonySwiftUIApp",
      destination: ResolvedDestination(
        platform: .macos, displayName: "macOS", simulatorName: nil, simulatorUDID: nil,
        xcodeDestination: "platform=macOS"),
      invocation: "xcodebuild build",
      exitStatus: 1,
      combinedOutput: "build failed",
      startedAt: Date(timeIntervalSince1970: 1_700_000_000),
      endedAt: Date(timeIntervalSince1970: 1_700_000_060)
    )

    let summary = try String(contentsOf: record.run.summaryPath, encoding: .utf8)
    #expect(summary.contains("command: build"))
    #expect(summary.contains("anomalies: missing_result_bundle"))

    let indexData = try Data(contentsOf: record.run.indexPath)
    let index = try JSONDecoder().decode(ArtifactIndex.self, from: indexData)
    #expect(index.anomalies.contains(where: { $0.code == "missing_result_bundle" }))
  }
}

@Test func artifactManagerExportsXCResultSummaryUsingLegacyCommand() throws {
  try withTemporaryDirectory { directory in
    let workspace = WorkspaceContext(
      projectRoot: directory,
      buildStateRoot: directory.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: nil,
      xcodeProjectPath: nil
    )
    let worker = try WorkerScope(id: 0)
    let executionContext = try ExecutionContextBuilder().make(
      workspace: workspace,
      worker: worker,
      command: .test,
      runID: "symphony",
      date: Date(timeIntervalSince1970: 1_700_000_100)
    )
    try FileManager.default.createDirectory(
      at: executionContext.resultBundlePath, withIntermediateDirectories: true)

    let runner = StubProcessRunner(results: [
      "xcrun xcresulttool get object --legacy --path \(executionContext.resultBundlePath.path) --format json":
        StubProcessRunner.success(#"{"kind":"ActionsInvocationRecord"}"#),
      "xcrun xcresulttool export diagnostics --path \(executionContext.resultBundlePath.path) --output-path \(executionContext.artifactRoot.appendingPathComponent("diagnostics").path)":
        StubProcessRunner.success(),
      "xcrun xcresulttool export attachments --path \(executionContext.resultBundlePath.path) --output-path \(executionContext.artifactRoot.appendingPathComponent("attachments").path)":
        StubProcessRunner.success(),
    ])
    let manager = ArtifactManager(processRunner: runner)

    let record = try manager.recordXcodeExecution(
      workspace: workspace,
      executionContext: executionContext,
      command: .test,
      product: .server,
      scheme: "SymphonyServer",
      destination: ResolvedDestination(
        platform: .macos,
        displayName: "macOS",
        simulatorName: nil,
        simulatorUDID: nil,
        xcodeDestination: expectedHostMacOSDestination()
      ),
      invocation: "xcodebuild test",
      exitStatus: 0,
      combinedOutput: "tests passed",
      startedAt: Date(timeIntervalSince1970: 1_700_000_100),
      endedAt: Date(timeIntervalSince1970: 1_700_000_140)
    )

    let summaryJSON = try String(
      contentsOf: record.run.artifactRoot.appendingPathComponent("summary.json"), encoding: .utf8)
    #expect(summaryJSON.contains(#""kind":"ActionsInvocationRecord""#))

    let indexData = try Data(contentsOf: record.run.indexPath)
    let index = try JSONDecoder().decode(ArtifactIndex.self, from: indexData)
    #expect(!index.anomalies.contains(where: { $0.code == "xcresult_summary_export_failed" }))
  }
}

@Test func artifactResolutionAnnotatesMissingEntries() throws {
  try withTemporaryDirectory { directory in
    let workspace = WorkspaceContext(
      projectRoot: directory,
      buildStateRoot: directory.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: nil,
      xcodeProjectPath: nil
    )
    let worker = try WorkerScope(id: 0)
    let executionContext = try ExecutionContextBuilder().make(
      workspace: workspace,
      worker: worker,
      command: .build,
      runID: "symphony",
      date: Date(timeIntervalSince1970: 1_700_000_200)
    )
    try FileManager.default.createDirectory(
      at: executionContext.resultBundlePath, withIntermediateDirectories: true)

    let runner = StubProcessRunner(results: [
      "xcrun xcresulttool get object --legacy --path \(executionContext.resultBundlePath.path) --format json":
        StubProcessRunner.success(#"{"kind":"ActionsInvocationRecord"}"#),
      "xcrun xcresulttool export diagnostics --path \(executionContext.resultBundlePath.path) --output-path \(executionContext.artifactRoot.appendingPathComponent("diagnostics").path)":
        StubProcessRunner.success(),
      "xcrun xcresulttool export attachments --path \(executionContext.resultBundlePath.path) --output-path \(executionContext.artifactRoot.appendingPathComponent("attachments").path)":
        StubProcessRunner.success(),
    ])
    let manager = ArtifactManager(processRunner: runner)

    _ = try manager.recordXcodeExecution(
      workspace: workspace,
      executionContext: executionContext,
      command: .build,
      product: .client,
      scheme: "SymphonySwiftUIApp",
      destination: ResolvedDestination(
        platform: .iosSimulator,
        displayName: "iPhone 17 (AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA)",
        simulatorName: "iPhone 17",
        simulatorUDID: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
        xcodeDestination: "platform=iOS Simulator,id=AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
      ),
      invocation: "xcodebuild build",
      exitStatus: 0,
      combinedOutput: "build succeeded",
      startedAt: Date(timeIntervalSince1970: 1_700_000_200),
      endedAt: Date(timeIntervalSince1970: 1_700_000_240)
    )

    let rendered = try manager.resolveArtifacts(
      workspace: workspace,
      request: ArtifactsCommandRequest(
        command: .build, latest: true, runID: nil, currentDirectory: directory)
    )

    #expect(
      rendered.contains(
        "log.txt \(executionContext.artifactRoot.appendingPathComponent("log.txt").path)"))
    #expect(
      rendered.contains(
        "recording.mp4 [missing: missing_recording] \(executionContext.artifactRoot.appendingPathComponent("recording.mp4").path)"
      ))
    #expect(
      rendered.contains(
        "screen.png [missing: missing_screen_capture] \(executionContext.artifactRoot.appendingPathComponent("screen.png").path)"
      ))
    #expect(
      rendered.contains(
        "ui-tree.txt [missing: missing_ui_tree] \(executionContext.artifactRoot.appendingPathComponent("ui-tree.txt").path)"
      ))
  }
}

