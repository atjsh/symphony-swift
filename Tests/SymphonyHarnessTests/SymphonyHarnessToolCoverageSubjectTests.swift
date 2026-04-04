import Foundation
import Testing

@testable import SymphonyHarness

@Test func subjectExecutionBridgeUsesSuppliedCurrentDirectory() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    let currentDirectory = directory.appendingPathComponent("nested", isDirectory: true)
    try FileManager.default.createDirectory(at: repoRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: currentDirectory, withIntermediateDirectories: true)

    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: nil,
      xcodeProjectPath: nil
    )
    let discovery = RecordingWorkspaceDiscovery(workspace: workspace)
    let runner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "swift", arguments == ["build", "--scratch-path", ".build/swiftpm-cache", "--product", "symphony-server"] {
        return StubProcessRunner.success("server built")
      }
      return StubProcessRunner.success()
    }
    let tool = SymphonyHarnessTool(
      workspaceDiscovery: discovery,
      executionContextBuilder: ExecutionContextBuilder(),
      simulatorResolver: SimulatorResolver(
        catalog: StubSimulatorCatalog(devices: []),
        processRunner: runner
      ),
      processRunner: runner,
      artifactManager: ArtifactManager(processRunner: runner),
      endpointOverrideStore: EndpointOverrideStore(),
      doctorService: StubDoctorService(
        report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []),
        rendered: "ok"
      ),
      toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(
        capabilities: .fullyAvailableForTests
      ),
      productLocator: ProductLocator(processRunner: runner),
      commitHarness: CommitHarness(processRunner: runner),
      gitHookInstaller: GitHookInstaller(processRunner: runner),
      statusSink: { _ in }
    )

    let summaryPath = try tool.execute(
      ExecutionRequest(command: .build, subjects: ["SymphonyServerCLI"], outputMode: .filtered),
      currentDirectory: currentDirectory
    )

    #expect(discovery.discoveredFrom == [currentDirectory])
    #expect(FileManager.default.fileExists(atPath: summaryPath))
  }
}

@Test func subjectExecutionBridgeTestsCanonicalProductionAndExplicitSubjects() throws {
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
    let runner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "swift",
        arguments == ["test", "--scratch-path", ".build/swiftpm-cache", "--enable-code-coverage", "--filter", "SymphonyServerCoreTests"]
      {
        return StubProcessRunner.success("server core tests")
      }
      if command == "swift",
        arguments == ["test", "--scratch-path", ".build/swiftpm-cache", "--enable-code-coverage", "--filter", "SymphonyHarnessCLITests"]
      {
        return StubProcessRunner.success("harness cli tests")
      }
      if command == "swift", arguments == ["test", "--scratch-path", ".build/swiftpm-cache", "--show-code-coverage-path"] {
        return StubProcessRunner.success(
          repoRoot.appendingPathComponent("missing-coverage.json").path + "\n")
      }
      if command == "xcodebuild", arguments.last == "test" {
        #expect(arguments.contains("SymphonySwiftUIApp"))
        #expect(arguments.contains("-only-testing:SymphonySwiftUIAppUITests"))
        return StubProcessRunner.success("ui tests")
      }
      if command == "xcrun", arguments.prefix(4) == ["xccov", "view", "--report", "--json"] {
        return StubProcessRunner.failure("coverage unavailable")
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
      toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(
        capabilities: .fullyAvailableForTests),
      productLocator: ProductLocator(processRunner: runner),
      commitHarness: CommitHarness(processRunner: runner),
      gitHookInstaller: GitHookInstaller(processRunner: runner),
      statusSink: { _ in }
    )

    let productionOutput = try tool.test(
      ExecutionRequest(command: .test, subjects: ["SymphonyServerCore"], outputMode: .filtered)
    )
    let explicitSwiftPMOutput = try tool.test(
      ExecutionRequest(
        command: .test,
        subjects: [],
        explicitTestSubjects: ["SymphonyHarnessCLITests"],
        outputMode: .filtered
      )
    )
    let explicitXcodeOutput = try tool.test(
      ExecutionRequest(
        command: .test,
        subjects: [],
        explicitTestSubjects: ["SymphonySwiftUIAppUITests"],
        outputMode: .filtered
      )
    )

    #expect(FileManager.default.fileExists(atPath: productionOutput))
    #expect(FileManager.default.fileExists(atPath: explicitSwiftPMOutput))
    #expect(FileManager.default.fileExists(atPath: explicitXcodeOutput))
    let xcodeSummary = try String(
      contentsOf: URL(fileURLWithPath: explicitXcodeOutput),
      encoding: .utf8
    )
    #expect(xcodeSummary.contains("subject_artifact_root SymphonySwiftUIAppUITests"))
    let explicitXcodeSubjectSummary = try String(
      contentsOf: URL(fileURLWithPath: explicitXcodeOutput)
        .deletingLastPathComponent()
        .appendingPathComponent("subjects/SymphonySwiftUIAppUITests/summary.txt"),
      encoding: .utf8
    )
    #expect(explicitXcodeSubjectSummary.contains("subject: SymphonySwiftUIAppUITests"))
    #expect(!explicitXcodeSubjectSummary.contains("product:"))
    #expect(
      FileManager.default.fileExists(
        atPath: URL(fileURLWithPath: explicitXcodeOutput)
          .deletingLastPathComponent()
          .appendingPathComponent("subjects/SymphonySwiftUIAppUITests/summary.txt").path))
  }
}

@Test func subjectExecutionBridgeWritesSubjectOwnedSwiftPMCoverageArtifacts() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
      xcodeProjectPath: nil
    )
    let coveragePath = repoRoot.appendingPathComponent(".build/subject-owned-coverage.json")
    try FileManager.default.createDirectory(
      at: coveragePath.deletingLastPathComponent(), withIntermediateDirectories: true)
    try #"""
    {
      "data": [
        {
          "files": [
            { "filename": "__REPO__/Sources/SymphonyHarness/CoverageInspection.swift", "summary": { "lines": { "count": 12, "covered": 9 } } },
            { "filename": "__REPO__/Sources/SymphonyHarness/SymphonyHarnessTool.swift", "summary": { "lines": { "count": 6, "covered": 3 } } },
            { "filename": "__REPO__/Sources/SymphonyHarnessCLI/SymphonyHarnessCommand.swift", "summary": { "lines": { "count": 10, "covered": 8 } } },
            { "filename": "__REPO__/Sources/harness/main.swift", "summary": { "lines": { "count": 2, "covered": 2 } } },
            { "filename": "__REPO__/Sources/SymphonyServer/ProviderAdapter.swift", "summary": { "lines": { "count": 30, "covered": 30 } } }
          ]
        }
      ]
    }
    """#
    .replacingOccurrences(of: "__REPO__", with: repoRoot.path)
    .write(to: coveragePath, atomically: true, encoding: .utf8)

    let observedFilters = SignalBox()
    let runner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "swift",
        arguments.count == 6,
        arguments[0] == "test",
        arguments[3] == "--enable-code-coverage",
        arguments[4] == "--filter"
      {
        observedFilters.append(arguments[5])
        return StubProcessRunner.success("swift coverage ok")
      }
      if command == "swift", arguments == ["test", "--scratch-path", ".build/swiftpm-cache", "--show-code-coverage-path"] {
        return StubProcessRunner.success(coveragePath.path + "\n")
      }
      return StubProcessRunner.success()
    }
    let tool = makeCoverageTool(workspace: workspace, runner: runner, statusSink: { _ in })

    let harnessSummary = try tool.test(
      ExecutionRequest(command: .test, subjects: ["SymphonyHarness"], outputMode: .filtered)
    )
    let harnessCLISummary = try tool.test(
      ExecutionRequest(command: .test, subjects: ["SymphonyHarnessCLI"], outputMode: .filtered)
    )
    let explicitHarnessCLISummary = try tool.test(
      ExecutionRequest(
        command: .test,
        subjects: [],
        explicitTestSubjects: ["SymphonyHarnessCLITests"],
        outputMode: .filtered
      )
    )

    #expect(observedFilters.values == [
      "SymphonyHarnessTests",
      "SymphonyHarnessCLITests",
      "SymphonyHarnessCLITests",
    ])

    let harnessReport = try loadCoverageReport(
      fromSharedSummaryPath: harnessSummary,
      subject: "SymphonyHarness"
    )
    #expect(harnessReport.targets.map(\.name) == ["SymphonyHarness"])
    #expect(
      harnessReport.targets[0].files?.map(\.path) == [
        "Sources/SymphonyHarness/CoverageInspection.swift",
        "Sources/SymphonyHarness/SymphonyHarnessTool.swift",
      ])
    #expect(!harnessReport.targets.flatMap { $0.files ?? [] }.contains { $0.path.contains("ProviderAdapter.swift") })

    let harnessCLIReport = try loadCoverageReport(
      fromSharedSummaryPath: harnessCLISummary,
      subject: "SymphonyHarnessCLI"
    )
    #expect(harnessCLIReport.targets.map(\.name) == ["SymphonyHarnessCLI"])
    #expect(
      harnessCLIReport.targets[0].files?.map(\.path) == [
        "Sources/SymphonyHarnessCLI/SymphonyHarnessCommand.swift",
        "Sources/harness/main.swift",
      ])
    #expect(!harnessCLIReport.targets.flatMap { $0.files ?? [] }.contains { $0.path.contains("ProviderAdapter.swift") })

    let explicitHarnessCLIReport = try loadCoverageReport(
      fromSharedSummaryPath: explicitHarnessCLISummary,
      subject: "SymphonyHarnessCLITests"
    )
    #expect(explicitHarnessCLIReport.targets.map(\.name) == ["SymphonyHarnessCLI"])
    #expect(
      explicitHarnessCLIReport.targets[0].files?.map(\.path) == [
        "Sources/SymphonyHarnessCLI/SymphonyHarnessCommand.swift",
        "Sources/harness/main.swift",
      ])
  }
}

