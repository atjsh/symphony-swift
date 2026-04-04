import Foundation
import Testing

@testable import SymphonyHarness

@Test func goEnryBuildPlanSupportsMacOSLinuxAndWindowsHostCombos() {
  let macARM = GoEnryBuildPlan.make(hostPlatform: .macOS, hostArchitecture: .arm64)
  #expect(macARM.variants.map(\.triple) == ["darwin-arm64", "darwin-amd64"])
  #expect(macARM.archiveStrategy == .universalMacOS)

  let macIntel = GoEnryBuildPlan.make(hostPlatform: .macOS, hostArchitecture: .amd64)
  #expect(macIntel.variants.map(\.triple) == ["darwin-amd64", "darwin-arm64"])
  #expect(macIntel.archiveStrategy == .universalMacOS)

  let linuxARM = GoEnryBuildPlan.make(hostPlatform: .linux, hostArchitecture: .arm64)
  #expect(linuxARM.variants.map(\.triple) == ["linux-arm64"])
  #expect(linuxARM.archiveStrategy == .singleHostVariant)

  let linuxIntel = GoEnryBuildPlan.make(hostPlatform: .linux, hostArchitecture: .amd64)
  #expect(linuxIntel.variants.map(\.triple) == ["linux-amd64"])
  #expect(linuxIntel.archiveStrategy == .singleHostVariant)

  let windowsARM = GoEnryBuildPlan.make(hostPlatform: .windows, hostArchitecture: .arm64)
  #expect(windowsARM.variants.map(\.triple) == ["windows-arm64"])
  #expect(windowsARM.archiveStrategy == .singleHostVariant)

  let windowsIntel = GoEnryBuildPlan.make(hostPlatform: .windows, hostArchitecture: .amd64)
  #expect(windowsIntel.variants.map(\.triple) == ["windows-amd64"])
  #expect(windowsIntel.archiveStrategy == .singleHostVariant)
}

@Test func materializeGoEnryUsesSingleHostArchiveOutsideMacOS() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let sharedRoot = repoRoot.appendingPathComponent("ThirdParty/go-enry/shared", isDirectory: true)
    try FileManager.default.createDirectory(at: sharedRoot, withIntermediateDirectories: true)
    try "package main\nimport \"C\"\nfunc main() {}\n".write(
      to: sharedRoot.appendingPathComponent("enry.go"),
      atomically: true,
      encoding: .utf8
    )

    let archivePath = repoRoot.appendingPathComponent(".build/vendor/go-enry/lib/libenry.a")
    let finalHeaderPath = repoRoot.appendingPathComponent(".build/vendor/go-enry/include/enry.h")
    let runner = GoEnryMaterializationProcessRunner(results: [:])
    let materializer = GoEnryMaterializer(
      processRunner: runner,
      fileManager: .default,
      hostPlatform: .linux,
      hostArchitecture: .arm64
    )

    let materialization = try materializer.materialize(
      workspace: WorkspaceContext(
        projectRoot: repoRoot,
        buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
        xcodeWorkspacePath: nil,
        xcodeProjectPath: nil
      )
    )

    #expect(FileManager.default.fileExists(atPath: archivePath.path))
    #expect(FileManager.default.fileExists(atPath: finalHeaderPath.path))
    #expect(runner.goBuildArchitectures == ["arm64"])
    #expect(runner.lipoOutputPath == nil)
    #expect(materialization.archivePath.path == archivePath.path)
    #expect(materialization.headerPath.path == finalHeaderPath.path)
  }
}

@Test func materializeGoEnryFailsWhenSubmoduleSourcesAreMissing() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let discovery = WorkspaceDiscovery(
      processRunner: StubProcessRunner(results: [
        "git rev-parse --show-toplevel": StubProcessRunner.success(repoRoot.path + "\n")
      ]))
    let tool = SymphonyHarnessTool(workspaceDiscovery: discovery, processRunner: StubProcessRunner())

    do {
      _ = try tool.materializeGoEnry(GoEnryMaterializationRequest(currentDirectory: repoRoot))
      Issue.record("Expected missing go-enry sources to fail materialization.")
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "missing_go_enry_submodule")
    }
  }
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
    #expect(buildOutput == "swift build --scratch-path .build/swiftpm-cache --product symphony-server")
    #expect(!buildOutput.contains("xcodebuild"))
    let testLines = testOutput.split(separator: "\n").map(String.init)
    #expect(testLines.count == 2)
    #expect(testLines[0] == "swift test --scratch-path .build/swiftpm-cache --enable-code-coverage --filter SymphonyServerTests")
    #expect(testLines[1] == "swift test --scratch-path .build/swiftpm-cache --show-code-coverage-path")
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
    #expect(lines[0] == "swift test --scratch-path .build/swiftpm-cache --enable-code-coverage --filter SymphonyServerTests")
    #expect(lines[1] == "swift test --scratch-path .build/swiftpm-cache --show-code-coverage-path")
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
