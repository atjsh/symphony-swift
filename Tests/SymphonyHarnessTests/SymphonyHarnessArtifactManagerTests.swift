import Foundation
import Testing

@testable import SymphonyHarness

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
        invocation: "swift test --scratch-path .build/swiftpm-cache --enable-code-coverage --filter SymphonyServerTests",
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

