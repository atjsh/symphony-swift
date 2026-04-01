import Foundation
import Testing

@testable import SymphonyHarness

@Test func commitHarnessSkipsClientCoverageWhenXcodeIsUnavailable() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources"), withIntermediateDirectories: true)
    let coveragePath = repoRoot.appendingPathComponent(".build/coverage/package.json")
    try FileManager.default.createDirectory(
      at: coveragePath.deletingLastPathComponent(), withIntermediateDirectories: true)
    try
      #"{"data":[{"files":[{"filename":"__REPO__/Sources/Foo.swift","summary":{"lines":{"count":1,"covered":1}}}]}]}"#
      .replacingOccurrences(of: "__REPO__", with: repoRoot.path)
      .write(to: coveragePath, atomically: true, encoding: .utf8)

    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: nil,
      xcodeProjectPath: nil
    )
    let coverageJSON = #"""
      {"coveredLines":1,"executableLines":1,"lineCoverage":1,"includeTestTargets":false,"excludedTargets":[],"targets":[{"name":"Suite","buildProductPath":null,"coveredLines":1,"executableLines":1,"lineCoverage":1,"files":[]}]}
      """#
    let noXcodeArtifactRoot = directory.appendingPathComponent(
      "artifacts-noxcode", isDirectory: true)
    try FileManager.default.createDirectory(
      at: noXcodeArtifactRoot, withIntermediateDirectories: true)
    try coverageJSON.write(
      to: noXcodeArtifactRoot.appendingPathComponent("coverage.json"), atomically: true,
      encoding: .utf8)
    let runner = DualCoverageProcessRunner(
      packageCoveragePath: coveragePath.path, artifactRoot: noXcodeArtifactRoot.path)

    let report = try CommitHarness(
      processRunner: runner,
      statusSink: { _ in },
      toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(
        capabilities: .noXcodeForTests)
    ).run(
      workspace: workspace,
      request: HarnessCommandRequest(
        minimumCoveragePercent: 0, json: false, currentDirectory: repoRoot)
    )

    #expect(report.clientCoverageInvocation == nil)
    #expect(report.clientCoverage == nil)
    #expect(
      report.clientCoverageSkipReason
        == "not supported because the current environment has no Xcode available; Editing those sources is not encouraged"
    )
    #expect(report.serverCoverage.targets.map(\.name) == ["Suite"])
  }
}

@Test func commitHarnessFiltersSwiftTestCompileNoiseAndPropagatesOutputModeToCoverageCommands()
  throws
{
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources"), withIntermediateDirectories: true)
    let packageCoveragePath = repoRoot.appendingPathComponent(".build/coverage/package.json")
    try FileManager.default.createDirectory(
      at: packageCoveragePath.deletingLastPathComponent(), withIntermediateDirectories: true)
    try #"""
    {
      "data": [
        {
          "files": [
            { "filename": "__REPO__/Sources/Foo.swift", "summary": { "lines": { "count": 1, "covered": 1 } } }
          ]
        }
      ]
    }
    """#
    .replacingOccurrences(of: "__REPO__", with: repoRoot.path)
    .write(to: packageCoveragePath, atomically: true, encoding: .utf8)

    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: nil,
      xcodeProjectPath: nil
    )
    let coverageJSON = #"""
      {"coveredLines":1,"executableLines":1,"lineCoverage":1,"includeTestTargets":false,"excludedTargets":[],"targets":[{"name":"Suite","buildProductPath":null,"coveredLines":1,"executableLines":1,"lineCoverage":1,"files":[]}]}
      """#

    let artifactRoot = directory.appendingPathComponent("artifacts", isDirectory: true)
    try FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)
    try coverageJSON.write(
      to: artifactRoot.appendingPathComponent("coverage.json"), atomically: true, encoding: .utf8)

    let filteredStatus = SignalBox()
    let filteredRunner = HarnessOutputControlProcessRunner(
      packageCoveragePath: packageCoveragePath.path,
      artifactRoot: artifactRoot.path
    )
    _ = try CommitHarness(
      processRunner: filteredRunner,
      statusSink: { filteredStatus.append($0) },
      toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(
        capabilities: .fullyAvailableForTests)
    ).run(
      workspace: workspace,
      request: HarnessCommandRequest(
        minimumCoveragePercent: 0, json: false, currentDirectory: repoRoot)
    )

    #expect(
      filteredStatus.values.contains(where: { $0.contains("warning: important harness warning") }))
    #expect(
      !filteredStatus.values.contains(where: { $0.contains("Compiling NIOCore AsyncChannel.swift") }
      ))
    #expect(filteredStatus.values.contains(where: { $0.contains("suppressed 1 low-signal lines") }))

    let quietStatus = SignalBox()
    let quietRunner = HarnessOutputControlProcessRunner(
      packageCoveragePath: packageCoveragePath.path,
      artifactRoot: artifactRoot.path
    )
    _ = try CommitHarness(
      processRunner: quietRunner,
      statusSink: { quietStatus.append($0) },
      toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(
        capabilities: .fullyAvailableForTests)
    ).run(
      workspace: workspace,
      request: HarnessCommandRequest(
        minimumCoveragePercent: 0, json: false, outputMode: .quiet, currentDirectory: repoRoot)
    )

    #expect(
      !quietStatus.values.contains(where: { $0.contains("warning: important harness warning") }))
    #expect(
      !quietStatus.values.contains(where: { $0.contains("Compiling NIOCore AsyncChannel.swift") }))
    #expect(
      quietRunner.commands.contains(where: {
        $0.contains("test SymphonySwiftUIApp") && $0.contains("--xcode-output-mode quiet")
      }))
    #expect(
      quietRunner.commands.contains(where: {
        $0.contains("test SymphonyServer") && $0.contains("--xcode-output-mode quiet")
      }))
  }
}

@Test func commitHarnessHelperClosuresForwardSignalsAndFilterCoverageOutput() throws {
  let status = SignalBox()
  let observation = ProcessObservation(
    label: "swift test",
    onStaleSignal: { message in
      status.append(message)
    },
    onLine: { stream, line in
      guard stream == .stderr else {
        return
      }
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else {
        return
      }
      status.append(trimmed)
    }
  )
  observation.onStaleSignal?("stale-signal")
  observation.onLine?(.stdout, "   ")
  observation.onLine?(.stderr, "observed line")
  #expect(status.values == ["stale-signal", "observed line"])

  let coverageJSON = #"""
    {"coveredLines":4,"executableLines":4,"lineCoverage":1,"includeTestTargets":false,"excludedTargets":[],"targets":[{"name":"SymphonyServer","buildProductPath":"/tmp/SymphonyServer","coveredLines":4,"executableLines":4,"lineCoverage":1,"files":[]}]}
    """#
  let artifactDir = FileManager.default.temporaryDirectory.appendingPathComponent(
    UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: artifactDir, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: artifactDir) }
  try coverageJSON.write(
    to: artifactDir.appendingPathComponent("coverage.json"), atomically: true, encoding: .utf8)
  let runner = ObservationCoverageRunner(stdout: artifactDir.path + "\n") { observation in
    observation?.onStaleSignal?("coverage stale")
    observation?.onLine?(.stdout, "ignore stdout")
    observation?.onLine?(.stderr, " ")
    observation?.onLine?(.stderr, "stderr line")
  }
  let report = try CommitHarness.runCoverageSuite(
    processRunner: runner,
    executablePath: "/tmp/harness",
    arguments: ["test", "SymphonyServer"],
    currentDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true),
    statusSink: { status.append($0) }
  )
  #expect(report.targets.map { $0.name } == ["SymphonyServer"])
  #expect(status.values.contains("coverage stale"))
  #expect(status.values.contains("stderr line"))
  #expect(!status.values.contains("ignore stdout"))
}

@Test func gitHookInstallerAndProcessRunnersCoverDetachedAndObservationPaths() throws {
  try withTemporaryDirectory { directory in
    let workspace = WorkspaceContext(
      projectRoot: directory,
      buildStateRoot: directory.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: nil,
      xcodeProjectPath: nil
    )

    do {
      _ = try GitHookInstaller(
        processRunner: StubProcessRunner(results: [
          "git config core.hooksPath .githooks": StubProcessRunner.failure("git broke")
        ])
      ).install(workspace: workspace)
      Issue.record("Expected git hook install failures to surface.")
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "git_hooks_install_failed")
    }

    do {
      _ = try GitHookInstaller(
        processRunner: StubProcessRunner(results: [
          "git config core.hooksPath .githooks": CommandResult(
            exitStatus: 1, stdout: "", stderr: "")
        ])
      ).install(workspace: workspace)
      Issue.record("Expected empty-output git hook install failures to use the fallback message.")
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "git_hooks_install_failed")
      #expect(error.message == "Failed to configure core.hooksPath.")
    }

    let combined = CommandResult(exitStatus: 0, stdout: "one", stderr: "two")
    #expect(combined.combinedOutput == "one\ntwo")
    #expect(CommandResult(exitStatus: 0, stdout: "one", stderr: "").combinedOutput == "one")
    #expect(CommandResult(exitStatus: 0, stdout: "", stderr: "two").combinedOutput == "two")

    let protocolRunner = ProtocolExtensionRunner()
    _ = try protocolRunner.run(
      command: "echo", arguments: [], environment: [:], currentDirectory: directory)
    #expect(protocolRunner.lastObservationWasNil)

    let systemRunner = SystemProcessRunner()
    let noObservation = try systemRunner.run(
      command: "sh",
      arguments: ["-c", "printf 'plain-output\n'"],
      environment: [:],
      currentDirectory: directory
    )
    #expect(noObservation.stdout == "plain-output\n")

    let lines = SignalBox()
    let result = try systemRunner.run(
      command: "/bin/sh",
      arguments: ["-c", "printf 'hello\\n'; printf 'problem\\n' >&2"],
      environment: ["FOO": "bar"],
      currentDirectory: directory,
      observation: ProcessObservation(
        label: "shell",
        onLine: { stream, line in lines.append("\(stream.rawValue):\(line)") }
      )
    )
    #expect(result.stdout == "hello\n")
    #expect(result.stderr == "problem\n")
    #expect(lines.values.contains("stdout:hello"))
    #expect(lines.values.contains("stderr:problem"))

    let detachedOutput = directory.appendingPathComponent("detached/output.txt")
    let pid = try systemRunner.startDetached(
      executablePath: "/bin/sh",
      arguments: ["-c", "echo $DETACHED_VALUE"],
      environment: ["DETACHED_VALUE": "detached"],
      currentDirectory: directory,
      output: detachedOutput
    )
    #expect(pid > 0)

    let deadline = Date().addingTimeInterval(2)
    while Date() < deadline {
      if let contents = try? String(contentsOf: detachedOutput, encoding: .utf8),
        contents.contains("detached")
      {
        break
      }
      Thread.sleep(forTimeInterval: 0.05)
    }
    #expect((try String(contentsOf: detachedOutput, encoding: .utf8)).contains("detached"))

    _ = try systemRunner.run(
      command: "sh",
      arguments: ["-c", "sleep 0.12"],
      environment: [:],
      currentDirectory: nil,
      observation: ProcessObservation(label: "stderr-heartbeat", staleInterval: 0.05)
    )
  }
}

@Test func systemProcessRunnerDefaultArgumentsAndEmptyCombinedOutputRemainUsable() throws {
  try withTemporaryDirectory { directory in
    #expect(CommandResult(exitStatus: 0, stdout: "", stderr: "").combinedOutput.isEmpty)

    let runner = SystemProcessRunner()
    let result = try runner.run(
      command: "/bin/sh",
      arguments: ["-c", "printf 'defaults-covered'"]
    )
    #expect(result.stdout == "defaults-covered")
    #expect(result.stderr.isEmpty)

    let output = directory.appendingPathComponent("detached-existing.txt")
    try "stale".write(to: output, atomically: true, encoding: .utf8)

    let pid = try runner.startDetached(
      executablePath: "/bin/sh",
      arguments: ["-c", "printf 'existing-file-covered'"],
      output: output
    )
    #expect(pid > 0)

    let deadline = Date().addingTimeInterval(2)
    while Date() < deadline {
      if let contents = try? String(contentsOf: output, encoding: .utf8),
        contents.contains("existing-file-covered")
      {
        break
      }
      Thread.sleep(forTimeInterval: 0.05)
    }

    let contents = try String(contentsOf: output, encoding: .utf8)
    #expect(contents.contains("existing-file-covered"))
    #expect(!contents.contains("stale"))
  }
}

@Test func processHelpersCoverLineEmitterRemaindersAndIdleStaleSignals() {
  let silentEmitter = LineEmitter(stream: .stdout, observation: nil)
  silentEmitter.append(Data())
  silentEmitter.append(Data("ignored\n".utf8))
  silentEmitter.finish()

  let lines = SignalBox()
  let observedEmitter = LineEmitter(
    stream: .stderr,
    observation: ProcessObservation(
      label: "emitter",
      onLine: { stream, line in
        lines.append("\(stream.rawValue):\(line)")
      })
  )
  observedEmitter.append(Data("line-1\npartial".utf8))
  observedEmitter.finish()

  #expect(lines.values == ["stderr:line-1", "stderr:partial"])

  let collector = DataCollector()
  let staleSignals = SignalBox()
  let controller = StaleSignalController(
    observation: ProcessObservation(
      label: "idle", staleInterval: 60, onStaleSignal: { staleSignals.append($0) }),
    collector: collector
  )
  controller.signalIfNeeded()

  #expect(collector.data.isEmpty)
  #expect(staleSignals.values.isEmpty)
}

@Test func staleSignalControllerWritesHeartbeatWhenNoCallbackIsConfigured() {
  let collector = DataCollector()
  let controller = StaleSignalController(
    observation: ProcessObservation(label: "heartbeat", staleInterval: 0.01),
    collector: collector
  )

  Thread.sleep(forTimeInterval: 0.02)
  controller.signalIfNeeded()

  let message = String(decoding: collector.data, as: UTF8.self)
  #expect(message.contains("heartbeat still running"))
}

@Test func artifactManagerRecursiveFilesSkipsPlainFilesWhenEnumerationIsUnavailable() throws {
  let manager = ArtifactManager(processRunner: StubProcessRunner(), enumeratorFactory: { _ in nil })
  #expect(
    manager.recursiveFiles(in: [URL(fileURLWithPath: "/tmp/missing", isDirectory: true)]).isEmpty)
}

