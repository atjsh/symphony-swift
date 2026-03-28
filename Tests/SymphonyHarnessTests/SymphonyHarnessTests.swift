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

@Test func artifactManagerCoversMissingArtifactSelectionsAndOptionalExports() throws {
  try withTemporaryDirectory { directory in
    let workspace = WorkspaceContext(
      projectRoot: directory,
      buildStateRoot: directory.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: nil,
      xcodeProjectPath: nil
    )
    let manager = ArtifactManager(processRunner: StubProcessRunner())

    do {
      _ = try manager.resolveArtifacts(
        workspace: workspace,
        request: ArtifactsCommandRequest(
          command: .build, latest: true, runID: nil, currentDirectory: directory)
      )
      Issue.record("Expected missing latest artifact roots to fail.")
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "missing_artifacts")
    }

    let worker = try WorkerScope(id: 1)
    let executionContext = try ExecutionContextBuilder().make(
      workspace: workspace,
      worker: worker,
      command: .test,
      runID: "sample",
      date: Date(timeIntervalSince1970: 1_700_000_400)
    )
    try FileManager.default.createDirectory(
      at: executionContext.resultBundlePath, withIntermediateDirectories: true)
    let diagnosticsPath = executionContext.artifactRoot.appendingPathComponent(
      "diagnostics", isDirectory: true)
    let attachmentsPath = executionContext.artifactRoot.appendingPathComponent(
      "attachments", isDirectory: true)
    let png = attachmentsPath.appendingPathComponent("capture.png")
    let text = diagnosticsPath.appendingPathComponent("view-hierarchy.txt")

    let runner = StubProcessRunner(results: [
      "xcrun xcresulttool get object --legacy --path \(executionContext.resultBundlePath.path) --format json":
        StubProcessRunner.failure(""),
      "xcrun xcresulttool export diagnostics --path \(executionContext.resultBundlePath.path) --output-path \(diagnosticsPath.path)":
        StubProcessRunner.failure(""),
      "xcrun xcresulttool export attachments --path \(executionContext.resultBundlePath.path) --output-path \(attachmentsPath.path)":
        StubProcessRunner.failure(""),
    ])
    let failingManager = ArtifactManager(processRunner: runner)

    _ = try failingManager.recordXcodeExecution(
      workspace: workspace,
      executionContext: executionContext,
      command: .test,
      product: .server,
      scheme: "SymphonyServer",
      destination: ResolvedDestination(
        platform: .macos, displayName: "macOS", simulatorName: nil, simulatorUDID: nil,
        xcodeDestination: expectedHostMacOSDestination()),
      invocation: "xcodebuild test",
      exitStatus: 0,
      combinedOutput: "",
      startedAt: Date(timeIntervalSince1970: 1_700_000_400),
      endedAt: Date(timeIntervalSince1970: 1_700_000_420)
    )

    do {
      _ = try failingManager.resolveArtifacts(
        workspace: workspace,
        request: ArtifactsCommandRequest(
          command: .test, latest: false, runID: "missing", currentDirectory: directory)
      )
      Issue.record("Expected missing run ids to fail.")
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "missing_artifact_run")
    }

    try FileManager.default.createDirectory(at: diagnosticsPath, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: attachmentsPath, withIntermediateDirectories: true)
    try Data().write(to: png)
    try Data("tree".utf8).write(to: text)
    _ = try ArtifactManager(
      processRunner: StubProcessRunner(results: [
        "xcrun xcresulttool get object --legacy --path \(executionContext.resultBundlePath.path) --format json":
          StubProcessRunner.success(#"{"kind":"ActionsInvocationRecord"}"#),
        "xcrun xcresulttool export diagnostics --path \(executionContext.resultBundlePath.path) --output-path \(diagnosticsPath.path)":
          StubProcessRunner.success(),
        "xcrun xcresulttool export attachments --path \(executionContext.resultBundlePath.path) --output-path \(attachmentsPath.path)":
          StubProcessRunner.success(),
      ])
    ).recordXcodeExecution(
      workspace: workspace,
      executionContext: executionContext,
      command: .test,
      product: .client,
      scheme: "SymphonySwiftUIApp",
      destination: ResolvedDestination(
        platform: .iosSimulator, displayName: "iPhone 17", simulatorName: "iPhone 17",
        simulatorUDID: "AAAA", xcodeDestination: "platform=iOS Simulator,id=AAAA"),
      invocation: "xcodebuild test",
      exitStatus: 0,
      combinedOutput: "",
      startedAt: Date(timeIntervalSince1970: 1_700_000_400),
      endedAt: Date(timeIntervalSince1970: 1_700_000_430)
    )

    let root = workspace.buildStateRoot.appendingPathComponent("artifacts/test/latest")
      .resolvingSymlinksInPath()
    let manualIndex = ArtifactIndex(
      entries: [
        ArtifactIndexEntry(
          name: "manual.txt", relativePath: "manual.txt", kind: "missing",
          createdAt: "2026-03-24T00:00:00Z", anomaly: nil)
      ],
      command: .test,
      runID: root.lastPathComponent,
      timestamp: "2026-03-24T00:00:00Z",
      anomalies: []
    )
    let indexPath = root.appendingPathComponent("index.json")
    try JSONEncoder().encode(manualIndex).write(to: indexPath)
    let rendered = try manager.resolveArtifacts(
      workspace: workspace,
      request: ArtifactsCommandRequest(
        command: .test, latest: true, runID: nil, currentDirectory: directory)
    )
    #expect(
      rendered.contains("manual.txt [missing] \(root.appendingPathComponent("manual.txt").path)"))
  }
}

@Test func artifactManagerInternalHelpersCoverRunSelectionAndIndexFallbacks() throws {
  try withTemporaryDirectory { directory in
    let workspace = WorkspaceContext(
      projectRoot: directory,
      buildStateRoot: directory.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: nil,
      xcodeProjectPath: nil
    )
    let manager = ArtifactManager(processRunner: StubProcessRunner())
    let familyRoot = workspace.buildStateRoot.appendingPathComponent(
      "artifacts/build", isDirectory: true)
    let older = familyRoot.appendingPathComponent("20260324-120000-sample", isDirectory: true)
    let newer = familyRoot.appendingPathComponent("20260324-130000-sample", isDirectory: true)
    try FileManager.default.createDirectory(at: older, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: newer, withIntermediateDirectories: true)

    let rendered = try manager.resolveArtifacts(
      workspace: workspace,
      request: ArtifactsCommandRequest(
        command: .build, latest: false, runID: "sample", currentDirectory: directory)
    )
    #expect(rendered.contains(newer.path))
    #expect(
      try manager.loadArtifactIndexIfPresent(at: newer.appendingPathComponent("index.json")) == nil)
    #expect(
      manager.recursiveFiles(in: [
        directory.appendingPathComponent("does-not-exist", isDirectory: true)
      ]).isEmpty)

    try manager.updateLatestLink(familyRoot: familyRoot, target: older)
    try manager.updateLatestLink(familyRoot: familyRoot, target: newer)
    #expect(
      familyRoot.appendingPathComponent("latest").resolvingSymlinksInPath().path == newer.path)
  }
}

@Test func artifactManagerIndexesSupplementalFilesAcrossBackendsAndHandlesNilEnumerators() throws {
  try withTemporaryDirectory { directory in
    let workspace = WorkspaceContext(
      projectRoot: directory,
      buildStateRoot: directory.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: nil,
      xcodeProjectPath: nil
    )

    let xcodeContext = try ExecutionContextBuilder().make(
      workspace: workspace,
      worker: WorkerScope(id: 0),
      command: .test,
      runID: "xcode-extra",
      date: Date(timeIntervalSince1970: 1_700_000_450)
    )
    try FileManager.default.createDirectory(
      at: xcodeContext.artifactRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: xcodeContext.resultBundlePath, withIntermediateDirectories: true)
    let xcodeExtra = xcodeContext.artifactRoot.appendingPathComponent("custom-note.txt")
    try "note\n".write(to: xcodeExtra, atomically: true, encoding: .utf8)

    let xcodeRunner = StubProcessRunner(results: [
      "xcrun xcresulttool get object --legacy --path \(xcodeContext.resultBundlePath.path) --format json":
        StubProcessRunner.success(#"{"kind":"ActionsInvocationRecord"}"#),
      "xcrun xcresulttool export diagnostics --path \(xcodeContext.resultBundlePath.path) --output-path \(xcodeContext.artifactRoot.appendingPathComponent("diagnostics").path)":
        StubProcessRunner.success(),
      "xcrun xcresulttool export attachments --path \(xcodeContext.resultBundlePath.path) --output-path \(xcodeContext.artifactRoot.appendingPathComponent("attachments").path)":
        StubProcessRunner.success(),
    ])
    let xcodeManager = ArtifactManager(processRunner: xcodeRunner)
    let xcodeRecord = try xcodeManager.recordXcodeExecution(
      workspace: workspace,
      executionContext: xcodeContext,
      command: .test,
      product: .client,
      scheme: "SymphonySwiftUIApp",
      destination: ResolvedDestination(
        platform: .macos, displayName: "macOS", simulatorName: nil, simulatorUDID: nil,
        xcodeDestination: expectedHostMacOSDestination()),
      invocation: "xcodebuild test",
      exitStatus: 0,
      combinedOutput: "tests passed",
      startedAt: Date(timeIntervalSince1970: 1_700_000_450),
      endedAt: Date(timeIntervalSince1970: 1_700_000_460)
    )
    let xcodeIndex = try JSONDecoder().decode(
      ArtifactIndex.self, from: Data(contentsOf: xcodeRecord.run.indexPath))
    #expect(
      xcodeIndex.entries.contains(where: { $0.name == "custom-note.txt" && $0.kind == "file" }))

    let swiftPMContext = try ExecutionContextBuilder().make(
      workspace: workspace,
      worker: WorkerScope(id: 1),
      command: .test,
      runID: "swiftpm-extra",
      date: Date(timeIntervalSince1970: 1_700_000_470)
    )
    try FileManager.default.createDirectory(
      at: swiftPMContext.artifactRoot, withIntermediateDirectories: true)
    let swiftPMExtra = swiftPMContext.artifactRoot.appendingPathComponent("manual-log.txt")
    try "manual\n".write(to: swiftPMExtra, atomically: true, encoding: .utf8)

    let swiftPMRecord = try ArtifactManager(processRunner: StubProcessRunner())
      .recordSwiftPMExecution(
        workspace: workspace,
        executionContext: swiftPMContext,
        command: .test,
        product: .server,
        scheme: "SymphonyServer",
        destination: ResolvedDestination(
          platform: .macos, displayName: "macOS", simulatorName: nil, simulatorUDID: nil,
          xcodeDestination: expectedHostMacOSDestination()),
        invocation: "swift test --enable-code-coverage --filter SymphonyServerTests",
        exitStatus: 0,
        combinedOutput: "ok",
        startedAt: Date(timeIntervalSince1970: 1_700_000_470),
        endedAt: Date(timeIntervalSince1970: 1_700_000_480)
      )
    let swiftPMIndex = try JSONDecoder().decode(
      ArtifactIndex.self, from: Data(contentsOf: swiftPMRecord.run.indexPath))
    #expect(
      swiftPMIndex.entries.contains(where: { $0.name == "manual-log.txt" && $0.kind == "file" }))

    let nilEnumeratorManager = ArtifactManager(
      processRunner: StubProcessRunner(), enumeratorFactory: { _ in nil })
    #expect(nilEnumeratorManager.recursiveFiles(in: [directory]).isEmpty)
  }
}

@Test func artifactManagerAdditionalEntriesMapsUnknownFilesIntoIndexEntries() throws {
  try withTemporaryDirectory { directory in
    let artifactRoot = directory.appendingPathComponent("artifacts", isDirectory: true)
    try FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)
    try "alpha\n".write(
      to: artifactRoot.appendingPathComponent("alpha.txt"), atomically: true, encoding: .utf8)
    try FileManager.default.createDirectory(
      at: artifactRoot.appendingPathComponent("nested", isDirectory: true),
      withIntermediateDirectories: true)

    let manager = ArtifactManager(processRunner: StubProcessRunner())
    let entries = try manager.additionalEntries(
      in: artifactRoot, excluding: [], createdAt: "2026-03-25T00:00:00Z")

    #expect(entries.map(\.name) == ["alpha.txt", "nested"])
    #expect(entries.first?.kind == "file")
    #expect(entries.last?.kind == "directory")
  }
}

@Test func artifactManagerWritesHarnessArtifactsAndResolvesHarnessFamily() throws {
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
      command: .harness,
      runID: "commit-harness",
      date: Date(timeIntervalSince1970: 1_700_000_500)
    )
    try FileManager.default.createDirectory(
      at: executionContext.artifactRoot, withIntermediateDirectories: true)
    try "{}\n".write(
      to: executionContext.artifactRoot.appendingPathComponent("package-inspection.json"),
      atomically: true, encoding: .utf8)
    try "{}\n".write(
      to: executionContext.artifactRoot.appendingPathComponent("client-inspection.json"),
      atomically: true, encoding: .utf8)
    try "{}\n".write(
      to: executionContext.artifactRoot.appendingPathComponent("server-inspection.json"),
      atomically: true, encoding: .utf8)
    try "package\n".write(
      to: executionContext.artifactRoot.appendingPathComponent("package-inspection.txt"),
      atomically: true, encoding: .utf8)
    try "client\n".write(
      to: executionContext.artifactRoot.appendingPathComponent("client-inspection.txt"),
      atomically: true, encoding: .utf8)
    try "server\n".write(
      to: executionContext.artifactRoot.appendingPathComponent("server-inspection.txt"),
      atomically: true, encoding: .utf8)
    try "alpha\n".write(
      to: executionContext.artifactRoot.appendingPathComponent("alpha.txt"), atomically: true,
      encoding: .utf8)
    try "extra\n".write(
      to: executionContext.artifactRoot.appendingPathComponent("notes.txt"), atomically: true,
      encoding: .utf8)

    let manager = ArtifactManager(processRunner: StubProcessRunner())
    let record = try manager.recordHarnessExecution(
      workspace: workspace,
      executionContext: executionContext,
      invocation: "harness harness",
      exitStatus: 1,
      summaryJSON: "{\"minimumCoveragePercent\":100}\n",
      summaryText: "harness summary",
      startedAt: Date(timeIntervalSince1970: 1_700_000_500),
      endedAt: Date(timeIntervalSince1970: 1_700_000_560),
      anomalies: [
        ArtifactAnomaly(
          code: "custom_harness_issue", message: "custom harness anomaly", phase: "harness")
      ]
    )

    #expect(record.run.command == .harness)
    let summaryJSON = try String(
      contentsOf: record.run.artifactRoot.appendingPathComponent("summary.json"), encoding: .utf8)
    #expect(summaryJSON == "{\"minimumCoveragePercent\":100}\n")
    let summaryText = try String(contentsOf: record.run.summaryPath, encoding: .utf8)
    #expect(summaryText.contains("anomalies: custom_harness_issue"))
    let rendered = try manager.resolveArtifacts(
      workspace: workspace,
      request: ArtifactsCommandRequest(
        command: .harness, latest: true, runID: nil, currentDirectory: directory)
    )
    #expect(rendered.contains(record.run.artifactRoot.path))
    #expect(rendered.contains("summary.txt \(record.run.summaryPath.path)"))
    #expect(rendered.contains("package-inspection.json"))
    #expect(rendered.contains("client-inspection.json"))
    #expect(rendered.contains("server-inspection.json"))
    #expect(rendered.contains("alpha.txt"))
    #expect(rendered.contains("notes.txt"))
    #expect(!rendered.contains("result.xcresult [missing]"))
  }
}

@Test func artifactManagerCoversAnomaliesNoneSwiftPMEmptyOutputAndXCResultFailureMessages() throws {
  try withTemporaryDirectory { directory in
    let workspace = WorkspaceContext(
      projectRoot: directory,
      buildStateRoot: directory.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: nil,
      xcodeProjectPath: nil
    )

    let xcodeWorker = try WorkerScope(id: 0)
    let xcodeExecution = try ExecutionContextBuilder().make(
      workspace: workspace,
      worker: xcodeWorker,
      command: .test,
      runID: "xcode",
      date: Date(timeIntervalSince1970: 1_700_000_580)
    )
    try FileManager.default.createDirectory(
      at: xcodeExecution.artifactRoot.appendingPathComponent("diagnostics"),
      withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: xcodeExecution.artifactRoot.appendingPathComponent("attachments"),
      withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: xcodeExecution.resultBundlePath, withIntermediateDirectories: true)
    try Data("tree".utf8).write(
      to: xcodeExecution.artifactRoot.appendingPathComponent("diagnostics/view-hierarchy.txt"))
    try Data().write(
      to: xcodeExecution.artifactRoot.appendingPathComponent("attachments/screen.png"))
    try Data().write(
      to: xcodeExecution.artifactRoot.appendingPathComponent("attachments/recording.mp4"))

    let successfulXcodeRunner = StubProcessRunner(results: [
      "xcrun xcresulttool get object --legacy --path \(xcodeExecution.resultBundlePath.path) --format json":
        StubProcessRunner.success(#"{"kind":"ActionsInvocationRecord"}"#),
      "xcrun xcresulttool export diagnostics --path \(xcodeExecution.resultBundlePath.path) --output-path \(xcodeExecution.artifactRoot.appendingPathComponent("diagnostics").path)":
        StubProcessRunner.success(),
      "xcrun xcresulttool export attachments --path \(xcodeExecution.resultBundlePath.path) --output-path \(xcodeExecution.artifactRoot.appendingPathComponent("attachments").path)":
        StubProcessRunner.success(),
    ])
    let successfulManager = ArtifactManager(processRunner: successfulXcodeRunner)
    let successfulRecord = try successfulManager.recordXcodeExecution(
      workspace: workspace,
      executionContext: xcodeExecution,
      command: .test,
      product: .client,
      scheme: "SymphonySwiftUIApp",
      destination: ResolvedDestination(
        platform: .macos, displayName: "macOS", simulatorName: nil, simulatorUDID: nil,
        xcodeDestination: expectedHostMacOSDestination()),
      invocation: "xcodebuild test",
      exitStatus: 0,
      combinedOutput: "tests passed",
      startedAt: Date(timeIntervalSince1970: 1_700_000_580),
      endedAt: Date(timeIntervalSince1970: 1_700_000_600)
    )
    let successfulSummary = try String(
      contentsOf: successfulRecord.run.summaryPath, encoding: .utf8)
    #expect(successfulSummary.contains("anomalies: none"))

    let swiftPMWorker = try WorkerScope(id: 1)
    let swiftPMExecution = try ExecutionContextBuilder().make(
      workspace: workspace,
      worker: swiftPMWorker,
      command: .test,
      runID: "swiftpm",
      date: Date(timeIntervalSince1970: 1_700_000_610)
    )
    let swiftPMRecord = try ArtifactManager(processRunner: StubProcessRunner())
      .recordSwiftPMExecution(
        workspace: workspace,
        executionContext: swiftPMExecution,
        command: .test,
        product: .server,
        scheme: "SymphonyServer",
        destination: ResolvedDestination(
          platform: .macos, displayName: "macOS", simulatorName: nil, simulatorUDID: nil,
          xcodeDestination: expectedHostMacOSDestination()),
        invocation: "swift test --enable-code-coverage --filter SymphonyServerTests",
        exitStatus: 0,
        combinedOutput: "",
        startedAt: Date(timeIntervalSince1970: 1_700_000_610),
        endedAt: Date(timeIntervalSince1970: 1_700_000_620)
      )
    let swiftPMSummary = try String(contentsOf: swiftPMRecord.run.summaryPath, encoding: .utf8)
    #expect(swiftPMSummary.contains("stdout_stderr:\n<empty>"))

    let failingWorker = try WorkerScope(id: 2)
    let failingExecution = try ExecutionContextBuilder().make(
      workspace: workspace,
      worker: failingWorker,
      command: .test,
      runID: "failing-xcresult",
      date: Date(timeIntervalSince1970: 1_700_000_630)
    )
    try FileManager.default.createDirectory(
      at: failingExecution.resultBundlePath, withIntermediateDirectories: true)
    let failingRunner = StubProcessRunner(results: [
      "xcrun xcresulttool get object --legacy --path \(failingExecution.resultBundlePath.path) --format json":
        StubProcessRunner.failure("summary broke"),
      "xcrun xcresulttool export diagnostics --path \(failingExecution.resultBundlePath.path) --output-path \(failingExecution.artifactRoot.appendingPathComponent("diagnostics").path)":
        StubProcessRunner.failure("diagnostics broke"),
      "xcrun xcresulttool export attachments --path \(failingExecution.resultBundlePath.path) --output-path \(failingExecution.artifactRoot.appendingPathComponent("attachments").path)":
        StubProcessRunner.failure("attachments broke"),
    ])
    let failingRecord = try ArtifactManager(processRunner: failingRunner).recordXcodeExecution(
      workspace: workspace,
      executionContext: failingExecution,
      command: .test,
      product: .client,
      scheme: "SymphonySwiftUIApp",
      destination: ResolvedDestination(
        platform: .macos, displayName: "macOS", simulatorName: nil, simulatorUDID: nil,
        xcodeDestination: expectedHostMacOSDestination()),
      invocation: "xcodebuild test",
      exitStatus: 1,
      combinedOutput: "tests failed",
      startedAt: Date(timeIntervalSince1970: 1_700_000_630),
      endedAt: Date(timeIntervalSince1970: 1_700_000_640)
    )
    let failingIndex = try JSONDecoder().decode(
      ArtifactIndex.self, from: Data(contentsOf: failingRecord.run.indexPath))
    #expect(
      failingIndex.anomalies.contains(where: {
        $0.code == "xcresult_summary_export_failed" && $0.message.contains("summary broke")
      }))
    #expect(
      failingIndex.anomalies.contains(where: {
        $0.code == "xcresult_diagnostics_export_failed" && $0.message.contains("diagnostics broke")
      }))
    #expect(
      failingIndex.anomalies.contains(where: {
        $0.code == "xcresult_attachments_export_failed" && $0.message.contains("attachments broke")
      }))
  }
}

@Test func artifactResolutionIncludesSupplementalCoverageReports() throws {
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
      date: Date(timeIntervalSince1970: 1_700_000_260)
    )
    try FileManager.default.createDirectory(
      at: executionContext.artifactRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: executionContext.resultBundlePath, withIntermediateDirectories: true)
    try #"{"coveredLines":96}"#.write(
      to: executionContext.artifactRoot.appendingPathComponent("coverage.json"),
      atomically: true,
      encoding: .utf8
    )
    try "overall 73.28% (96/131)\n".write(
      to: executionContext.artifactRoot.appendingPathComponent("coverage.txt"),
      atomically: true,
      encoding: .utf8
    )

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
      invocation: "xcodebuild test -enableCodeCoverage YES",
      exitStatus: 0,
      combinedOutput: "tests passed",
      startedAt: Date(timeIntervalSince1970: 1_700_000_260),
      endedAt: Date(timeIntervalSince1970: 1_700_000_320)
    )

    let rendered = try manager.resolveArtifacts(
      workspace: workspace,
      request: ArtifactsCommandRequest(
        command: .test, latest: true, runID: nil, currentDirectory: directory)
    )

    #expect(
      rendered.contains(
        "coverage.json \(executionContext.artifactRoot.appendingPathComponent("coverage.json").path)"
      ))
    #expect(
      rendered.contains(
        "coverage.txt \(executionContext.artifactRoot.appendingPathComponent("coverage.txt").path)")
    )
  }
}

@Test func coverageReporterFiltersOutTestBundlesByDefaultAndWritesReports() throws {
  try withTemporaryDirectory { directory in
    let resultBundlePath = directory.appendingPathComponent("result.xcresult", isDirectory: true)
    let artifactRoot = directory.appendingPathComponent("artifacts", isDirectory: true)
    let coverageJSON = #"""
      {"coveredLines":113,"executableLines":148,"lineCoverage":0.7635135135,"targets":[{"buildProductPath":"/tmp/SymphonyServer","coveredLines":0,"executableLines":1,"files":[{"coveredLines":0,"executableLines":1,"lineCoverage":0,"name":"main.swift","path":"/tmp/main.swift"}],"lineCoverage":0,"name":"SymphonyServer"},{"buildProductPath":"/tmp/SymphonyServerTests.xctest/Contents/MacOS/SymphonyServerTests","coveredLines":17,"executableLines":17,"files":[{"coveredLines":17,"executableLines":17,"lineCoverage":1,"name":"BootstrapServerRunnerTests.swift","path":"/tmp/BootstrapServerRunnerTests.swift"}],"lineCoverage":1,"name":"SymphonyServerTests.xctest"},{"buildProductPath":"/tmp/libXcodeSupport.a","coveredLines":96,"executableLines":130,"files":[{"coveredLines":96,"executableLines":130,"lineCoverage":0.7384615385,"name":"BootstrapSupport.swift","path":"/tmp/BootstrapSupport.swift"}],"lineCoverage":0.7384615385,"name":"libXcodeSupport.a"}]}
      """#
    let runner = StubProcessRunner(results: [
      "xcrun xccov view --report --json \(resultBundlePath.path)": StubProcessRunner.success(
        coverageJSON)
    ])
    let reporter = CoverageReporter(processRunner: runner)

    let artifacts = try reporter.export(
      resultBundlePath: resultBundlePath,
      artifactRoot: artifactRoot,
      product: .server,
      includeTestTargets: false,
      showFiles: true
    )

    #expect(artifacts.report.coveredLines == 96)
    #expect(artifacts.report.executableLines == 131)
    #expect(artifacts.report.targets.map(\.name) == ["SymphonyServer", "libXcodeSupport.a"])
    #expect(artifacts.report.excludedTargets == ["SymphonyServerTests.xctest"])
    #expect(artifacts.textOutput.contains("overall 73.28% (96/131)"))
    #expect(
      artifacts.textOutput.contains("file libXcodeSupport.a BootstrapSupport.swift 73.85% (96/130)")
    )
    #expect(FileManager.default.fileExists(atPath: artifacts.jsonPath.path))
    #expect(FileManager.default.fileExists(atPath: artifacts.textPath.path))
  }
}

@Test func packageCoverageReporterFiltersToFirstPartySources() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources"), withIntermediateDirectories: true)
    let coveragePath = directory.appendingPathComponent("package-coverage.json")
    let json = #"""
      {
        "data": [
          {
            "files": [
              {
                "filename": "__REPO__/Sources/Foo.swift",
                "summary": { "lines": { "count": 20, "covered": 10 } }
              },
              {
                "filename": "__REPO__/Tests/FooTests.swift",
                "summary": { "lines": { "count": 50, "covered": 50 } }
              },
              {
                "filename": "__REPO__/.build/checkouts/swift-argument-parser/Sources/Dependency.swift",
                "summary": { "lines": { "count": 100, "covered": 0 } }
              }
            ]
          }
        ]
      }
      """#
    try json
      .replacingOccurrences(of: "__REPO__", with: repoRoot.path)
      .write(to: coveragePath, atomically: true, encoding: .utf8)

    let report = try PackageCoverageReporter().loadReport(at: coveragePath, projectRoot: repoRoot)

    #expect(report.scope == "first_party_sources")
    #expect(report.coveredLines == 10)
    #expect(report.executableLines == 20)
    #expect(report.files.map(\.path) == ["Sources/Foo.swift"])
  }
}

@Test func harnessUsesSwiftTestCoverageAndFailsBelowThreshold() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources"), withIntermediateDirectories: true)
    let coveragePath = repoRoot.appendingPathComponent(".build/coverage/package.json")
    try FileManager.default.createDirectory(
      at: coveragePath.deletingLastPathComponent(), withIntermediateDirectories: true)
    let json = #"""
      {
        "data": [
          {
            "files": [
              {
                "filename": "__REPO__/Sources/Foo.swift",
                "summary": { "lines": { "count": 100, "covered": 60 } }
              }
            ]
          }
        ]
      }
      """#
    try json
      .replacingOccurrences(of: "__REPO__", with: repoRoot.path)
      .write(to: coveragePath, atomically: true, encoding: .utf8)

    let discovery = StubWorkspaceDiscovery(
      workspace: WorkspaceContext(
        projectRoot: repoRoot,
        buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
        xcodeWorkspacePath: nil,
        xcodeProjectPath: nil
      )
    )
    let runner = StubProcessRunner(results: [
      "swift test --enable-code-coverage": StubProcessRunner.success("tests passed\n"),
      "swift test --show-code-coverage-path": StubProcessRunner.success(coveragePath.path + "\n"),
    ])
    let passingCoverage = CoverageReport(
      coveredLines: 60,
      executableLines: 100,
      lineCoverage: 0.6,
      includeTestTargets: false,
      excludedTargets: [],
      targets: [
        CoverageTargetReport(
          name: "Symphony.app", buildProductPath: nil, coveredLines: 20, executableLines: 40,
          lineCoverage: 0.5, files: nil),
        CoverageTargetReport(
          name: "libXcodeSupport.a", buildProductPath: nil, coveredLines: 40, executableLines: 60,
          lineCoverage: 0.6666666667, files: nil),
      ]
    )
    let failingCoverage = CoverageReport(
      coveredLines: 20,
      executableLines: 100,
      lineCoverage: 0.2,
      includeTestTargets: false,
      excludedTargets: [],
      targets: [
        CoverageTargetReport(
          name: "SymphonyServer", buildProductPath: nil, coveredLines: 20, executableLines: 100,
          lineCoverage: 0.2, files: nil)
      ]
    )
    let tool = SymphonyHarnessTool(
      workspaceDiscovery: discovery,
      processRunner: runner,
      commitHarness: CommitHarness(
        processRunner: runner,
        statusSink: { _ in },
        clientCoverageLoader: { _ in passingCoverage },
        serverCoverageLoader: { _ in passingCoverage }
      )
    )

    let output = try tool.harness(
      HarnessCommandRequest(minimumCoveragePercent: 50, json: false, currentDirectory: repoRoot)
    )
    #expect(output.contains("package coverage 60.00% (60/100)"))
    #expect(output.contains("client coverage 60.00% (60/100)"))
    #expect(output.contains("server coverage 60.00% (60/100)"))
    #expect(output.contains("file Sources/Foo.swift 60.00% (60/100)"))
    #expect(output.contains("target Symphony.app 50.00% (20/40)"))

    let jsonOutput = try tool.harness(
      HarnessCommandRequest(minimumCoveragePercent: 50, json: true, currentDirectory: repoRoot)
    )
    #expect(jsonOutput.contains("\"clientCoverage\""))
    #expect(jsonOutput.contains("\"serverCoverage\""))

    do {
      let failingTool = SymphonyHarnessTool(
        workspaceDiscovery: discovery,
        processRunner: runner,
        commitHarness: CommitHarness(
          processRunner: runner,
          statusSink: { _ in },
          clientCoverageLoader: { _ in passingCoverage },
          serverCoverageLoader: { _ in failingCoverage }
        )
      )
      _ = try failingTool.harness(
        HarnessCommandRequest(minimumCoveragePercent: 80, json: false, currentDirectory: repoRoot)
      )
      Issue.record("Expected the harness to fail when coverage is below threshold.")
    } catch let error as SymphonyHarnessCommandFailure {
      #expect(error.message.contains("below the required threshold"))
      #expect(error.message.contains("Harness artifacts:"))
    }
  }
}

@Test func harnessRemovesStaleCoverageExportBeforeRunningSwiftTest() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources"), withIntermediateDirectories: true)
    let coveragePath = repoRoot.appendingPathComponent(
      ".build/arm64-apple-macosx/debug/codecov/symphony-swift.json")
    try FileManager.default.createDirectory(
      at: coveragePath.deletingLastPathComponent(), withIntermediateDirectories: true)
    try #"""
    {
      "data": [
        {
          "files": [
            {
              "filename": "__REPO__/Sources/Foo.swift",
              "summary": { "lines": { "count": 100, "covered": 0 } }
            }
          ]
        }
      ]
    }
    """#
    .replacingOccurrences(of: "__REPO__", with: repoRoot.path)
    .write(to: coveragePath, atomically: true, encoding: .utf8)

    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: nil,
      xcodeProjectPath: nil
    )
    let passingCoverage = CoverageReport(
      coveredLines: 4,
      executableLines: 4,
      lineCoverage: 1,
      includeTestTargets: false,
      excludedTargets: [],
      targets: []
    )
    let runner = StalePackageCoverageProcessRunner(repoRoot: repoRoot, coveragePath: coveragePath)
    let report = try CommitHarness(
      processRunner: runner,
      statusSink: { _ in },
      clientCoverageLoader: { _ in passingCoverage },
      serverCoverageLoader: { _ in passingCoverage }
    ).execute(
      workspace: workspace,
      request: HarnessCommandRequest(
        minimumCoveragePercent: 100,
        json: false,
        currentDirectory: repoRoot
      )
    ).report

    #expect(report.packageCoverage.lineCoverage == 1)
    #expect(runner.sawStaleCoverageBeforeSwiftTestRun == false)
  }
}

@Test func harnessWritesInspectionArtifactsAndReportsHarnessArtifactPathOnFailure() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources"), withIntermediateDirectories: true)

    let coveragePath = repoRoot.appendingPathComponent(
      ".build/arm64-apple-macosx/debug/codecov/symphony-swift.json")
    let profdataPath = coveragePath.deletingLastPathComponent().appendingPathComponent(
      "default.profdata")
    let testBinaryPath =
      repoRoot
      .appendingPathComponent(
        ".build/arm64-apple-macosx/debug/symphony-swiftPackageTests.xctest/Contents/MacOS/symphony-swiftPackageTests"
      )
    try FileManager.default.createDirectory(
      at: coveragePath.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: testBinaryPath.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data().write(to: profdataPath)
    try Data().write(to: testBinaryPath)
    try
      #"{"data":[{"files":[{"filename":"__REPO__/Sources/Foo.swift","summary":{"lines":{"count":4,"covered":2}}}]}]}"#
      .replacingOccurrences(of: "__REPO__", with: repoRoot.path)
      .write(to: coveragePath, atomically: true, encoding: .utf8)

    let coverageReport = CoverageReport(
      coveredLines: 2,
      executableLines: 4,
      lineCoverage: 0.5,
      includeTestTargets: false,
      excludedTargets: [],
      targets: [
        CoverageTargetReport(
          name: "Suite",
          buildProductPath: nil,
          coveredLines: 2,
          executableLines: 4,
          lineCoverage: 0.5,
          files: [
            CoverageFileReport(
              name: "Foo.swift", path: "/tmp/Foo.swift", coveredLines: 2, executableLines: 4,
              lineCoverage: 0.5)
          ]
        )
      ]
    )
    let clientInspection = CoverageInspectionReport(
      backend: .xcode,
      product: .client,
      generatedAt: "2026-03-25T00:00:00Z",
      files: [
        CoverageInspectionFileReport(
          targetName: "Suite",
          path: "/tmp/Foo.swift",
          coveredLines: 2,
          executableLines: 4,
          lineCoverage: 0.5,
          missingLineRanges: [CoverageLineRange(startLine: 10, endLine: 11)],
          functions: []
        )
      ]
    )
    let serverInspection = CoverageInspectionReport(
      backend: .swiftPM,
      product: .server,
      generatedAt: "2026-03-25T00:00:00Z",
      files: [
        CoverageInspectionFileReport(
          targetName: "Suite",
          path: "Sources/SymphonyServerCore/Foo.swift",
          coveredLines: 2,
          executableLines: 4,
          lineCoverage: 0.5,
          missingLineRanges: [CoverageLineRange(startLine: 3, endLine: 4)],
          functions: []
        )
      ]
    )
    // Create artifact directories with coverage files for client and server
    let clientArtifactRoot = directory.appendingPathComponent("client-artifacts", isDirectory: true)
    try FileManager.default.createDirectory(
      at: clientArtifactRoot, withIntermediateDirectories: true)
    try JSONEncoder().encode(coverageReport).write(
      to: clientArtifactRoot.appendingPathComponent("coverage.json"))
    try JSONEncoder().encode(clientInspection).write(
      to: clientArtifactRoot.appendingPathComponent("coverage-inspection.json"))

    let serverArtifactRoot = directory.appendingPathComponent("server-artifacts", isDirectory: true)
    try FileManager.default.createDirectory(
      at: serverArtifactRoot, withIntermediateDirectories: true)
    try JSONEncoder().encode(coverageReport).write(
      to: serverArtifactRoot.appendingPathComponent("coverage.json"))
    try JSONEncoder().encode(serverInspection).write(
      to: serverArtifactRoot.appendingPathComponent("coverage-inspection.json"))

    let packageShowCommand =
      "xcrun llvm-cov show -instr-profile \(profdataPath.path) \(testBinaryPath.path) \(repoRoot.appendingPathComponent("Sources/Foo.swift").path)"
    let packageFunctionsCommand =
      "xcrun llvm-cov report --show-functions -instr-profile \(profdataPath.path) \(testBinaryPath.path) \(repoRoot.appendingPathComponent("Sources/Foo.swift").path)"
    let runner = HarnessInspectionProcessRunner(
      packageCoveragePath: coveragePath.path,
      clientArtifactRoot: clientArtifactRoot.path,
      serverArtifactRoot: serverArtifactRoot.path,
      extraResults: [
        packageShowCommand: StubProcessRunner.success(
          """
              1|       |import Foundation
              2|      1|func foo() {
              3|      0|    uncovered()
              4|      0|    uncoveredAgain()
              5|      1|}
          """
        ),
        packageFunctionsCommand: StubProcessRunner.success(
          """
          File '\(repoRoot.appendingPathComponent("Sources/Foo.swift").path)':
          Name                                     Regions    Miss   Cover     Lines    Miss   Cover  Branches    Miss   Cover
          --------------------------------------------------------------------------------------------------------------------------------
          foo()                                         2       1  50.00%         4       2  50.00%         0       0   0.00%
          --------------------------------------------------------------------------------------------------------------------------------
          TOTAL                                         2       1  50.00%         4       2  50.00%         0       0   0.00%
          """
        ),
      ]
    )

    let discovery = StubWorkspaceDiscovery(
      workspace: WorkspaceContext(
        projectRoot: repoRoot,
        buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
        xcodeWorkspacePath: nil,
        xcodeProjectPath: nil
      )
    )
    let tool = SymphonyHarnessTool(
      workspaceDiscovery: discovery,
      processRunner: runner,
      artifactManager: ArtifactManager(processRunner: runner),
      commitHarness: CommitHarness(processRunner: runner, statusSink: { _ in })
    )

    do {
      _ = try tool.harness(
        HarnessCommandRequest(minimumCoveragePercent: 100, json: false, currentDirectory: repoRoot)
      )
      Issue.record("Expected the harness to fail below the threshold after writing artifacts.")
    } catch let error as SymphonyHarnessCommandFailure {
      #expect(error.message.contains("below the required threshold"))
      #expect(error.message.contains("Harness artifacts:"))
    }

    let rendered = try tool.artifacts(
      ArtifactsCommandRequest(
        command: .harness, latest: true, runID: nil, currentDirectory: repoRoot)
    )
    #expect(rendered.contains("package-inspection.json"))
    #expect(rendered.contains("package-inspection.txt"))
    #expect(rendered.contains("client-inspection.json"))
    #expect(rendered.contains("client-inspection.txt"))
    #expect(rendered.contains("server-inspection.json"))
    #expect(rendered.contains("server-inspection.txt"))
  }
}

@Test func hooksInstallConfiguresRepoLocalHooksPath() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)

    let discovery = StubWorkspaceDiscovery(
      workspace: WorkspaceContext(
        projectRoot: repoRoot,
        buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
        xcodeWorkspacePath: nil,
        xcodeProjectPath: nil
      )
    )
    let runner = RecordingProcessRunner()
    let tool = SymphonyHarnessTool(workspaceDiscovery: discovery, processRunner: runner)

    let installedPath = try tool.hooksInstall(HooksInstallRequest(currentDirectory: repoRoot))

    #expect(installedPath == repoRoot.appendingPathComponent(".githooks", isDirectory: true).path)
    #expect(runner.commands == ["git config core.hooksPath .githooks"])
  }
}

@Test func doctorReportSortsIssuesAndRendersJSONAndHumanOutput() throws {
  let runner = StubProcessRunner(results: [
    "which swift": StubProcessRunner.success(),
    "which xcodebuild": StubProcessRunner.success(),
    "xcrun simctl help": StubProcessRunner.success(),
    "xcrun xcresulttool help": StubProcessRunner.failure("xcresulttool missing"),
    "which xcrun": StubProcessRunner.success(),
    "xcodebuild -list -json -workspace /tmp/repo/Symphony.xcworkspace": StubProcessRunner.success(
      #"{"workspace":{"schemes":["SymphonySwiftUIApp"]},"project":{"schemes":[]}}"#),
  ])
  let discovery = StubWorkspaceDiscovery(
    workspace: WorkspaceContext(
      projectRoot: URL(fileURLWithPath: "/tmp/repo", isDirectory: true),
      buildStateRoot: URL(fileURLWithPath: "/tmp/repo/.build/harness", isDirectory: true),
      xcodeWorkspacePath: URL(fileURLWithPath: "/tmp/repo/Symphony.xcworkspace"),
      xcodeProjectPath: nil
    )
  )
  let doctor = DoctorService(workspaceDiscovery: discovery, processRunner: runner)
  let report = try doctor.makeReport(
    from: DoctorCommandRequest(
      strict: false, json: false, quiet: false, currentDirectory: URL(fileURLWithPath: "/tmp/repo"))
  )

  #expect(report.issues.map { $0.code } == ["missing_xcresulttool"])

  let human = try doctor.render(report: report, json: false, quiet: false)
  #expect(human.contains("ERROR [missing_xcresulttool]"))

  let json = try doctor.render(report: report, json: true, quiet: false)
  #expect(json.contains("\"missing_xcresulttool\""))
}

@Test func strictDoctorThrowsWhenAnyIssuesExist() throws {
  let report = DiagnosticsReport(
    issues: [
      DiagnosticIssue(
        severity: .warning, code: "warning_issue", message: "needs attention", suggestedFix: nil)
    ],
    checkedPaths: ["/tmp/repo"],
    checkedExecutables: ["swift"]
  )
  let tool = SymphonyHarnessTool(
    doctorService: StubDoctorService(report: report, rendered: "diagnostics"))

  do {
    _ = try tool.doctor(
      DoctorCommandRequest(
        strict: true, json: false, quiet: false, currentDirectory: URL(fileURLWithPath: "/tmp/repo")
      )
    )
    Issue.record("Expected strict doctor mode to fail when issues are present.")
  } catch let error as SymphonyHarnessCommandFailure {
    #expect(error.message == "diagnostics")
  }
}

@Test func strictDoctorSucceedsWhenReportIsClean() throws {
  let tool = SymphonyHarnessTool(
    doctorService: StubDoctorService(
      report: DiagnosticsReport(
        issues: [], checkedPaths: ["/tmp/repo"], checkedExecutables: ["swift"]),
      rendered: "OK: environment is ready"
    )
  )

  let output = try tool.doctor(
    DoctorCommandRequest(
      strict: true, json: false, quiet: false, currentDirectory: URL(fileURLWithPath: "/tmp/repo"))
  )

  #expect(output == "OK: environment is ready")
}

@Test func xcodeOutputReporterFullModeStreamsStdoutAndStderr() {
  let messages = SignalBox()
  let reporter = XcodeOutputReporter(mode: .full, sink: { messages.append($0) })
  let observation = reporter.makeObservation(label: "xcodebuild build")

  observation.onLine?(.stdout, "CompileSwift Sources/Foo.swift")
  observation.onLine?(.stderr, "error: build failed")
  reporter.finish()

  #expect(messages.values.count == 2)
  #expect(
    messages.values.contains(where: {
      $0.contains("[xcodebuild/stdout] CompileSwift Sources/Foo.swift")
    }))
  #expect(
    messages.values.contains(where: { $0.contains("[xcodebuild/stderr] error: build failed") }))
}

@Test func xcodeOutputReporterFilteredModeSuppressesLowSignalLines() {
  let messages = SignalBox()
  let reporter = XcodeOutputReporter(mode: .filtered, sink: { messages.append($0) })
  let observation = reporter.makeObservation(label: "xcodebuild test")

  observation.onLine?(.stdout, "CompileSwift normal arm64 Foo.swift")
  observation.onLine?(.stderr, "warning: deprecated API")
  observation.onLine?(.stdout, "Ld /tmp/Symphony")
  reporter.finish()

  #expect(messages.values.contains(where: { $0.contains("[xcodebuild] warning: deprecated API") }))
  #expect(messages.values.contains(where: { $0.contains("suppressed 2 low-signal lines") }))
  #expect(!messages.values.contains(where: { $0.contains("CompileSwift normal arm64 Foo.swift") }))
}

@Test func processOutputReporterCanSuppressSwiftTestCompileNoise() {
  let messages = SignalBox()
  let reporter = XcodeOutputReporter(
    mode: .filtered, sink: { messages.append($0) }, commandName: "swift test")
  let observation = reporter.makeObservation(label: "swift test")

  observation.onLine?(.stdout, "Compiling NIOCore AsyncChannel.swift")
  observation.onLine?(.stdout, "warning: package deprecation warning")
  observation.onLine?(.stderr, "Linking SymphonyServer")
  reporter.finish()

  #expect(
    messages.values.contains(where: {
      $0.contains("[swift test] warning: package deprecation warning")
    }))
  #expect(messages.values.contains(where: { $0.contains("suppressed 2 low-signal lines") }))
  #expect(!messages.values.contains(where: { $0.contains("Compiling NIOCore AsyncChannel.swift") }))
}

@Test func xcodeOutputReporterQuietModeEmitsNothing() {
  let messages = SignalBox()
  let reporter = XcodeOutputReporter(mode: .quiet, sink: { messages.append($0) })
  let observation = reporter.makeObservation(label: "xcodebuild test")

  observation.onLine?(.stdout, "Test Suite 'All tests' started")
  observation.onLine?(.stderr, "warning: still noisy")
  reporter.finish()

  #expect(messages.values.isEmpty)
}

@Test func xcodeOutputReporterIgnoresBlankLines() {
  let messages = SignalBox()
  let reporter = XcodeOutputReporter(mode: .full, sink: { messages.append($0) })
  let observation = reporter.makeObservation(label: "xcodebuild test")

  observation.onLine?(.stdout, "   ")
  reporter.finish()

  #expect(messages.values.isEmpty)
}

@Test func xcodeOutputReporterForwardsStaleSignalsIndependentlyOfOutputMode() {
  let messages = SignalBox()
  let reporter = XcodeOutputReporter(mode: .quiet, sink: { messages.append($0) })
  let observation = reporter.makeObservation(label: "xcodebuild test")

  observation.onStaleSignal?(
    "[harness] xcodebuild test still running with no new output for 15s")
  reporter.finish()

  #expect(
    messages.values == ["[harness] xcodebuild test still running with no new output for 15s"]
  )
}

@Test func processRunnerEmitsStaleSignalForSilentLongRunningCommands() throws {
  let runner = SystemProcessRunner()
  let messages = SignalBox()

  let result = try runner.run(
    command: "sh",
    arguments: ["-c", "sleep 3"],
    environment: [:],
    currentDirectory: nil,
    observation: ProcessObservation(
      label: "test command",
      staleInterval: 0.5,
      onStaleSignal: { message in
        messages.append(message)
      }
    )
  )

  #expect(result.exitStatus == 0)
  #expect(messages.values.contains(where: { $0.contains("test command still running") }))
}

@Test func buildAndTestDryRunRenderSingleInvocationWithoutSideEffects() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let tool = makeToolForFixture(repoRoot: repoRoot)

    let buildOutput = try tool.build(
      BuildCommandRequest(
        product: .server,
        scheme: nil,
        platform: nil,
        simulator: nil,
        workerID: 0,
        dryRun: true,
        buildForTesting: false,
        outputMode: .full,
        currentDirectory: repoRoot
      )
    )
    let testOutput = try tool.test(
      TestCommandRequest(
        product: .server,
        scheme: nil,
        platform: nil,
        simulator: nil,
        workerID: 0,
        dryRun: true,
        onlyTesting: [],
        skipTesting: [],
        outputMode: .quiet,
        currentDirectory: repoRoot
      )
    )

    #expect(!buildOutput.contains("\n"))
    #expect(buildOutput == "swift build --product symphony-server")
    #expect(!buildOutput.contains("xcodebuild"))
    let testLines = testOutput.split(separator: "\n").map(String.init)
    #expect(testLines.count == 2)
    #expect(testLines[0] == "swift test --enable-code-coverage --filter SymphonyServerTests")
    #expect(testLines[1] == "swift test --show-code-coverage-path")
    #expect(
      !FileManager.default.fileExists(
        atPath: repoRoot.appendingPathComponent(".build/harness").path))
  }
}

@Test func testDryRunRendersSwiftPMCommandsWithCoverageEnabled() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let tool = makeToolForFixture(repoRoot: repoRoot)
    let output = try tool.test(
      TestCommandRequest(
        product: .server,
        scheme: nil,
        platform: nil,
        simulator: nil,
        workerID: 0,
        dryRun: true,
        onlyTesting: [],
        skipTesting: [],
        outputMode: .filtered,
        currentDirectory: repoRoot
      )
    )

    let lines = output.split(separator: "\n").map(String.init)
    #expect(lines.count == 2)
    #expect(lines[0] == "swift test --enable-code-coverage --filter SymphonyServerTests")
    #expect(lines[1] == "swift test --show-code-coverage-path")
    #expect(
      !FileManager.default.fileExists(
        atPath: repoRoot.appendingPathComponent(".build/harness").path))
  }
}

@Test func runDryRunPrintsFullSequenceWithoutSideEffects() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let tool = makeToolForFixture(repoRoot: repoRoot)
    let output = try tool.run(
      RunCommandRequest(
        product: .client,
        scheme: nil,
        platform: nil,
        simulator: "iPhone 17 Plus",
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

    let lines = output.split(separator: "\n").map(String.init)
    #expect(lines.count == 4)
    #expect(lines[0].contains("xcodebuild"))
    #expect(lines[1].contains("xcrun simctl bootstatus CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC -b"))
    #expect(lines[2].contains("xcrun simctl install CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC <app>"))
    #expect(
      lines[3].contains("xcrun simctl launch CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC <bundle-id>"))
    #expect(
      !FileManager.default.fileExists(
        atPath: repoRoot.appendingPathComponent(".build/harness").path))
    #expect(
      !FileManager.default.fileExists(
        atPath: repoRoot.appendingPathComponent(
          ".build/harness/runtime/server-endpoint.json"
        ).path))
  }
}

@Test func simSetServerPersistsEndpointAndClearRemovesIt() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let tool = makeToolForFixture(repoRoot: repoRoot)

    let savedPath = try tool.simSetServer(
      SimSetServerRequest(
        serverURL: nil,
        scheme: "https",
        host: "persisted.example.com",
        port: 9443,
        currentDirectory: repoRoot
      )
    )
    let savedURL = URL(fileURLWithPath: savedPath)
    let saved = try JSONDecoder().decode(RuntimeEndpoint.self, from: Data(contentsOf: savedURL))
    #expect(saved.scheme == "https")
    #expect(saved.host == "persisted.example.com")
    #expect(saved.port == 9443)

    let clearedPath = try tool.simClearServer(currentDirectory: repoRoot)
    #expect(clearedPath == savedPath)
    #expect(!FileManager.default.fileExists(atPath: savedURL.path))
  }
}

@Test func checkedInWorkspaceAndSchemesExistAtRepositoryRoot() throws {
  let repoRoot = currentRepositoryRoot()
  let fileManager = FileManager.default

  #expect(
    fileManager.fileExists(
      atPath: repoRoot.appendingPathComponent("Symphony.xcworkspace/contents.xcworkspacedata").path)
  )
  #expect(
    fileManager.fileExists(
      atPath: repoRoot.appendingPathComponent("SymphonyApps.xcodeproj/project.pbxproj").path))
  #expect(
    fileManager.fileExists(
      atPath: repoRoot.appendingPathComponent(
        "SymphonyApps.xcodeproj/xcshareddata/xcschemes/SymphonySwiftUIApp.xcscheme"
      ).path))
  #expect(
    !fileManager.fileExists(
      atPath: repoRoot.appendingPathComponent(
        "SymphonyApps.xcodeproj/xcshareddata/xcschemes/SymphonyServer.xcscheme"
      ).path))
  #expect(
    !fileManager.fileExists(
      atPath: repoRoot.appendingPathComponent(
        "SymphonyApps.xcodeproj/xcshareddata/xcschemes/Symphony.xcscheme"
      ).path))

  let discovery = WorkspaceDiscovery(
    processRunner: StubProcessRunner(results: [
      "git rev-parse --show-toplevel": StubProcessRunner.success(repoRoot.path + "\n")
    ]))
  let workspace = try discovery.discover(from: repoRoot)
  #expect(workspace.xcodeWorkspacePath?.lastPathComponent == "Symphony.xcworkspace")
}

struct StubProcessRunner: ProcessRunning {
  private final class Storage: @unchecked Sendable {
    var cachedCoverageExports = [String: Data]()
  }

  static let success = CommandResult(exitStatus: 0, stdout: "", stderr: "")

  var results: [String: CommandResult] = [:]
  private let storage = Storage()
  private let lock = NSLock()

  init(results: [String: CommandResult] = [:]) {
    self.results = results
  }

  func run(
    command: String, arguments: [String], environment: [String: String], currentDirectory: URL?,
    observation: ProcessObservation?
  ) throws -> CommandResult {
    let key = ([command] + arguments).joined(separator: " ")
    let result = results[key] ?? Self.success()

    if command == "swift", arguments == ["test", "--show-code-coverage-path"] {
      cacheCoverageExportSeed(from: result)
    } else if command == "swift", arguments == ["test", "--enable-code-coverage"] {
      try restoreCachedCoverageExportsIfNeeded()
    }

    return result
  }

  func startDetached(
    executablePath: String, arguments: [String], environment: [String: String],
    currentDirectory: URL?, output: URL
  ) throws -> Int32 {
    1234
  }

  static func failure(_ stderr: String) -> CommandResult {
    CommandResult(exitStatus: 1, stdout: "", stderr: stderr)
  }

  static func success(_ stdout: String = "") -> CommandResult {
    CommandResult(exitStatus: 0, stdout: stdout, stderr: "")
  }

  private func cacheCoverageExportSeed(from result: CommandResult) {
    guard result.exitStatus == 0 else {
      return
    }

    let rawPath = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !rawPath.isEmpty else {
      return
    }

    let coverageURL = URL(fileURLWithPath: rawPath)
    guard let data = try? Data(contentsOf: coverageURL) else {
      return
    }

    lock.lock()
    storage.cachedCoverageExports[coverageURL.path] = data
    lock.unlock()
  }

  private func restoreCachedCoverageExportsIfNeeded() throws {
    lock.lock()
    let cachedCoverageExports = storage.cachedCoverageExports
    lock.unlock()

    for (path, data) in cachedCoverageExports {
      let coverageURL = URL(fileURLWithPath: path)
      guard !FileManager.default.fileExists(atPath: coverageURL.path) else {
        continue
      }

      try FileManager.default.createDirectory(
        at: coverageURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try data.write(to: coverageURL)
    }
  }
}

final class StalePackageCoverageProcessRunner: ProcessRunning, @unchecked Sendable {
  private let lock = NSLock()
  private let repoRoot: URL
  private let coveragePath: URL
  private var staleCoverageBeforeSwiftTestRun: Bool?

  init(repoRoot: URL, coveragePath: URL) {
    self.repoRoot = repoRoot
    self.coveragePath = coveragePath
  }

  func run(
    command: String, arguments: [String], environment: [String: String], currentDirectory: URL?,
    observation: ProcessObservation?
  ) throws -> CommandResult {
    if command == "swift", arguments == ["test", "--show-code-coverage-path"] {
      return StubProcessRunner.success(coveragePath.path + "\n")
    }

    if command == "swift", arguments == ["test", "--enable-code-coverage"] {
      lock.lock()
      staleCoverageBeforeSwiftTestRun = FileManager.default.fileExists(atPath: coveragePath.path)
      lock.unlock()

      try #"""
      {
        "data": [
          {
            "files": [
              {
                "filename": "__REPO__/Sources/Foo.swift",
                "summary": { "lines": { "count": 100, "covered": 100 } }
              }
            ]
          }
        ]
      }
      """#
      .replacingOccurrences(of: "__REPO__", with: repoRoot.path)
      .write(to: coveragePath, atomically: true, encoding: .utf8)
      return StubProcessRunner.success("tests passed\n")
    }

    return StubProcessRunner.success()
  }

  func startDetached(
    executablePath: String, arguments: [String], environment: [String: String],
    currentDirectory: URL?, output: URL
  ) throws -> Int32 {
    1234
  }

  var sawStaleCoverageBeforeSwiftTestRun: Bool? {
    lock.lock()
    defer { lock.unlock() }
    return staleCoverageBeforeSwiftTestRun
  }
}

final class RecordingProcessRunner: ProcessRunning, @unchecked Sendable {
  private let lock = NSLock()
  private var storage = [String]()

  func run(
    command: String, arguments: [String], environment: [String: String], currentDirectory: URL?,
    observation: ProcessObservation?
  ) throws -> CommandResult {
    lock.lock()
    storage.append(([command] + arguments).joined(separator: " "))
    lock.unlock()
    return StubProcessRunner.success()
  }

  func startDetached(
    executablePath: String, arguments: [String], environment: [String: String],
    currentDirectory: URL?, output: URL
  ) throws -> Int32 {
    1234
  }

  var commands: [String] {
    lock.lock()
    defer { lock.unlock() }
    return storage
  }
}

final class SignalBox: @unchecked Sendable {
  private let lock = NSLock()
  private var storage = [String]()

  func append(_ value: String) {
    lock.lock()
    storage.append(value)
    lock.unlock()
  }

  var values: [String] {
    lock.lock()
    defer { lock.unlock() }
    return storage
  }
}

struct StubSimulatorCatalog: SimulatorCataloging {
  let devices: [SimulatorDevice]

  func availableDevices() throws -> [SimulatorDevice] {
    devices
  }
}

struct StubWorkspaceDiscovery: WorkspaceDiscovering {
  let workspace: WorkspaceContext

  func discover(from startDirectory: URL) throws -> WorkspaceContext {
    workspace
  }
}

struct StubDoctorService: DoctorServicing {
  let report: DiagnosticsReport
  let rendered: String

  func makeReport(from request: DoctorCommandRequest) throws -> DiagnosticsReport {
    report
  }

  func render(report: DiagnosticsReport, json: Bool, quiet: Bool) throws -> String {
    rendered
  }
}

struct StubToolchainCapabilitiesResolver: ToolchainCapabilitiesResolving {
  let capabilities: ToolchainCapabilities

  func resolve() throws -> ToolchainCapabilities {
    capabilities
  }
}

extension ToolchainCapabilities {
  static let fullyAvailableForTests = ToolchainCapabilities(
    swiftAvailable: true,
    xcodebuildAvailable: true,
    xcrunAvailable: true,
    simctlAvailable: true,
    xcresulttoolAvailable: true,
    llvmCovCommand: .xcrun
  )

  static let noXcodeForTests = ToolchainCapabilities(
    swiftAvailable: true,
    xcodebuildAvailable: false,
    xcrunAvailable: false,
    simctlAvailable: false,
    xcresulttoolAvailable: false,
    llvmCovCommand: .direct
  )
}

func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  try body(directory)
}

func withTemporaryRepositoryFixture(_ body: (URL) throws -> Void) throws {
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
    try body(repoRoot)
  }
}

func makeToolForFixture(repoRoot: URL) -> SymphonyHarnessTool {
  let discovery = WorkspaceDiscovery(
    processRunner: StubProcessRunner(results: [
      "git rev-parse --show-toplevel": StubProcessRunner.success(repoRoot.path + "\n")
    ]))
  let simulators = StubSimulatorCatalog(
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
  return SymphonyHarnessTool(
    workspaceDiscovery: discovery,
    simulatorResolver: SimulatorResolver(catalog: simulators, processRunner: StubProcessRunner()),
    processRunner: StubProcessRunner()
  )
}

func currentRepositoryRoot() -> URL {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
}

func expectedHostMacOSDestination() -> String {
  #if arch(arm64)
    "platform=macOS,arch=arm64"
  #elseif arch(x86_64)
    "platform=macOS,arch=x86_64"
  #else
    "platform=macOS"
  #endif
}

final class HarnessInspectionProcessRunner: ProcessRunning, @unchecked Sendable {
  let packageCoveragePath: String
  let clientArtifactRoot: String
  let serverArtifactRoot: String
  let extraResults: [String: CommandResult]
  private let packageCoverageData: Data?

  init(
    packageCoveragePath: String, clientArtifactRoot: String, serverArtifactRoot: String,
    extraResults: [String: CommandResult]
  ) {
    self.packageCoveragePath = packageCoveragePath
    self.clientArtifactRoot = clientArtifactRoot
    self.serverArtifactRoot = serverArtifactRoot
    self.extraResults = extraResults
    self.packageCoverageData = try? Data(contentsOf: URL(fileURLWithPath: packageCoveragePath))
  }

  func run(
    command: String, arguments: [String], environment: [String: String], currentDirectory: URL?,
    observation: ProcessObservation?
  ) throws -> CommandResult {
    let rendered = ([command] + arguments).joined(separator: " ")
    if let result = extraResults[rendered] {
      return result
    }
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
    if arguments.prefix(2) == ["test", "SymphonySwiftUIApp"] {
      return StubProcessRunner.success(clientArtifactRoot + "\n")
    }
    if arguments.prefix(2) == ["test", "SymphonyServer"] {
      return StubProcessRunner.success(serverArtifactRoot + "\n")
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
