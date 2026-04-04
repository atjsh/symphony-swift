import Foundation
import Testing

@testable import SymphonyHarness

@Test func subjectExecutionBridgePropagatesConcurrentWorkerErrors() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
      xcodeProjectPath: nil
    )
    let coveragePath = repoRoot.appendingPathComponent(".build/concurrent-worker-coverage.json")
    try FileManager.default.createDirectory(
      at: coveragePath.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try #"""
    {
      "data": [
        {
          "files": [
            { "filename": "__REPO__/Sources/SymphonyHarness/SymphonyHarnessTool.swift", "summary": { "lines": { "count": 4, "covered": 4 } } }
          ]
        }
      ]
    }
    """#
    .replacingOccurrences(of: "__REPO__", with: repoRoot.path)
    .write(to: coveragePath, atomically: true, encoding: .utf8)

    let runner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "swift",
        arguments == ["test", "--scratch-path", ".build/swiftpm-cache", "--enable-code-coverage", "--filter", "SymphonyHarnessTests"]
      {
        return StubProcessRunner.success("swift coverage ok")
      }
      if command == "swift", arguments == ["test", "--scratch-path", ".build/swiftpm-cache", "--show-code-coverage-path"] {
        return StubProcessRunner.success(coveragePath.path + "\n")
      }
      return StubProcessRunner.success()
    }
    let tool = SymphonyHarnessTool(
      workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
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

    do {
      _ = try tool.test(
        ExecutionRequest(
          command: .test,
          subjects: ["SymphonyHarness", "SymphonySwiftUIApp"],
          outputMode: .filtered
        )
      )
      Issue.record("Expected concurrent subject execution to surface worker errors.")
    } catch let error as SymphonyHarnessCommandFailure {
      #expect(error.message == "test failed for SymphonySwiftUIApp.")
      #expect(error.summaryPath != nil)
    }
  }
}

@Test func subjectExecutionBridgeWritesSyntheticArtifactsForUnsupportedAndFailedSubjectRuns() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
      xcodeProjectPath: nil
    )
    let coveragePath = repoRoot.appendingPathComponent(".build/subject-synthetic-coverage.json")
    try FileManager.default.createDirectory(
      at: coveragePath.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try #"""
    {
      "data": [
        {
          "files": [
            { "filename": "__REPO__/Sources/SymphonyHarness/SymphonyHarnessTool.swift", "summary": { "lines": { "count": 4, "covered": 4 } } }
          ]
        }
      ]
    }
    """#
    .replacingOccurrences(of: "__REPO__", with: repoRoot.path)
    .write(to: coveragePath, atomically: true, encoding: .utf8)

    let runner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "swift",
        arguments.count >= 6,
        arguments[0] == "test",
        arguments[3] == "--enable-code-coverage",
        arguments[4] == "--filter"
      {
        return StubProcessRunner.success("swift coverage ok")
      }
      if command == "swift", arguments == ["test", "--scratch-path", ".build/swiftpm-cache", "--show-code-coverage-path"] {
        return StubProcessRunner.success(coveragePath.path + "\n")
      }
      return StubProcessRunner.success()
    }
    let noXcodeCapabilities = StubToolchainCapabilitiesResolver(capabilities: .noXcodeForTests)
    let tool = SymphonyHarnessTool(
      workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
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
      toolchainCapabilitiesResolver: noXcodeCapabilities,
      productLocator: ProductLocator(processRunner: runner),
      commitHarness: CommitHarness(
        processRunner: runner,
        statusSink: { _ in },
        serverCoverageLoader: { _ in
          CoverageReport(
            coveredLines: 4,
            executableLines: 4,
            lineCoverage: 1,
            includeTestTargets: false,
            excludedTargets: [],
            targets: []
          )
        },
        toolchainCapabilitiesResolver: noXcodeCapabilities
      ),
      gitHookInstaller: GitHookInstaller(processRunner: runner),
      statusSink: { _ in }
    )

    let unsupportedSummaryPath = try tool.validate(
      ExecutionRequest(
        command: .validate,
        subjects: ["SymphonySwiftUIApp"],
        outputMode: .filtered
      )
    )
    let unsupportedSummary = try JSONDecoder().decode(
      SharedRunSummary.self,
      from: Data(
        contentsOf: URL(fileURLWithPath: unsupportedSummaryPath)
          .deletingLastPathComponent()
          .appendingPathComponent("summary.json")
      )
    )
    let unsupportedResult = try #require(unsupportedSummary.subjectResults.first)
    #expect([SubjectRunOutcome.unsupported, .skipped].contains(unsupportedResult.outcome))
    let unsupportedIndex = try JSONDecoder().decode(
      DecodedSharedRunIndex.self,
      from: Data(contentsOf: unsupportedResult.artifactSet.indexPath)
    )
    #expect(unsupportedIndex.anomalies.contains {
      ["unsupported_subject_execution", "skipped_subject_execution"].contains($0.code)
    })
    let unsupportedSubjectSummary = try String(
      contentsOf: unsupportedResult.artifactSet.summaryPath,
      encoding: .utf8
    )
    #expect(unsupportedSubjectSummary.contains("subject: SymphonySwiftUIApp"))
    #expect(unsupportedSubjectSummary.contains("reason:"))

    let failingRunner = RoutedProcessRunner { _, _, _, _, _ in
      StubProcessRunner.success()
    }
    let failingTool = SymphonyHarnessTool(
      workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
      executionContextBuilder: ExecutionContextBuilder(),
      simulatorResolver: SimulatorResolver(
        catalog: StubSimulatorCatalog(devices: []),
        processRunner: failingRunner
      ),
      processRunner: failingRunner,
      artifactManager: ArtifactManager(processRunner: failingRunner),
      endpointOverrideStore: EndpointOverrideStore(),
      doctorService: StubDoctorService(
        report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []),
        rendered: "ok"
      ),
      toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(
        capabilities: .fullyAvailableForTests),
      productLocator: ProductLocator(processRunner: failingRunner),
      commitHarness: CommitHarness(
        processRunner: failingRunner,
        statusSink: { _ in },
        serverCoverageLoader: { _ in
          CoverageReport(
            coveredLines: 4,
            executableLines: 4,
            lineCoverage: 1,
            includeTestTargets: false,
            excludedTargets: [],
            targets: []
          )
        },
        toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(
          capabilities: .fullyAvailableForTests)
      ),
      gitHookInstaller: GitHookInstaller(processRunner: failingRunner),
      statusSink: { _ in }
    )

    let failedSummaryPath: URL
    do {
      _ = try failingTool.execute(
        ExecutionRequest(
          command: .validate,
          subjects: ["SymphonySwiftUIApp"],
          outputMode: .filtered
        ),
        currentDirectory: repoRoot
      )
      Issue.record("Expected subject-scoped validate execution to fail without an available simulator.")
      return
    } catch let error as SymphonyHarnessCommandFailure {
      failedSummaryPath = try #require(error.summaryPath)
    }

    let failedSummary = try JSONDecoder().decode(
      SharedRunSummary.self,
      from: Data(contentsOf: failedSummaryPath.deletingLastPathComponent().appendingPathComponent("summary.json"))
    )
    let failedResult = try #require(failedSummary.subjectResults.first)
    #expect(failedResult.outcome == .failure)
    let failedIndex = try JSONDecoder().decode(
      DecodedSharedRunIndex.self,
      from: Data(contentsOf: failedResult.artifactSet.indexPath)
    )
    #expect(failedIndex.anomalies.map(\.code).contains("subject_execution_failed"))
    let failedSubjectSummary = try String(contentsOf: failedResult.artifactSet.summaryPath, encoding: .utf8)
    #expect(failedSubjectSummary.contains("outcome: failure"))
    #expect(failedSubjectSummary.contains("reason:"))
  }
}

@Test func subjectExecutionBridgeBuildsMultiSubjectSharedRunRoot() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
      xcodeProjectPath: nil
    )
    let runner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "swift", arguments == ["build", "--scratch-path", ".build/swiftpm-cache", "--product", "SymphonyShared"] {
        return StubProcessRunner.success("shared built")
      }
      if command == "swift", arguments == ["build", "--scratch-path", ".build/swiftpm-cache", "--product", "harness"] {
        return StubProcessRunner.success("harness built")
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
      toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(
        capabilities: .fullyAvailableForTests),
      productLocator: ProductLocator(processRunner: runner),
      commitHarness: CommitHarness(processRunner: runner),
      gitHookInstaller: GitHookInstaller(processRunner: runner),
      statusSink: { _ in }
    )

    let summaryPath = try tool.build(
      ExecutionRequest(
        command: .build,
        subjects: ["SymphonyShared", "SymphonyHarnessCLI"],
        outputMode: .filtered
      )
    )

    #expect(summaryPath.contains("/.build/harness/runs/"))
    #expect(summaryPath.hasSuffix("/summary.txt"))
    let summaryRoot = URL(fileURLWithPath: summaryPath).deletingLastPathComponent()
    #expect(FileManager.default.fileExists(atPath: summaryRoot.appendingPathComponent("summary.json").path))
    #expect(FileManager.default.fileExists(atPath: summaryRoot.appendingPathComponent("index.json").path))
    #expect(
      FileManager.default.fileExists(
        atPath: summaryRoot.appendingPathComponent("subjects/SymphonyShared/summary.txt").path))
    #expect(
      FileManager.default.fileExists(
        atPath: summaryRoot.appendingPathComponent("subjects/SymphonyHarnessCLI/summary.txt").path))
  }
}

@Test func executeBridgeRoutesCommandsAndRejectsUnsupportedShapes() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
      xcodeProjectPath: nil
    )
    let coveragePath = repoRoot.appendingPathComponent(".build/execute-routing-coverage.json")
    try FileManager.default.createDirectory(
      at: coveragePath.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try #"""
    {
      "data": [
        {
          "files": [
            { "filename": "__REPO__/Sources/SymphonyHarness/SymphonyHarnessTool.swift", "summary": { "lines": { "count": 4, "covered": 4 } } },
            { "filename": "__REPO__/Sources/SymphonyServerCLI/main.swift", "summary": { "lines": { "count": 2, "covered": 2 } } }
          ]
        }
      ]
    }
    """#
    .replacingOccurrences(of: "__REPO__", with: repoRoot.path)
    .write(to: coveragePath, atomically: true, encoding: .utf8)

    let runner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "swift",
        arguments == ["test", "--scratch-path", ".build/swiftpm-cache", "--enable-code-coverage", "--filter", "SymphonyHarnessTests"]
      {
        return StubProcessRunner.success("harness tests")
      }
      if command == "swift", arguments == ["test", "--scratch-path", ".build/swiftpm-cache", "--show-code-coverage-path"] {
        return StubProcessRunner.success(coveragePath.path + "\n")
      }
      if command == "swift", arguments == ["build", "--scratch-path", ".build/swiftpm-cache", "--product", "symphony-server"] {
        return StubProcessRunner.success("server built")
      }
      if command == "swift", arguments == ["build", "--scratch-path", ".build/swiftpm-cache", "--show-bin-path"] {
        return StubProcessRunner.success(repoRoot.appendingPathComponent(".build/debug").path + "\n")
      }
      return StubProcessRunner.success()
    }
    let tool = SymphonyHarnessTool(
      workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
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

    let testSummary = try tool.execute(
      ExecutionRequest(command: .test, subjects: ["SymphonyHarness"], outputMode: .filtered),
      currentDirectory: repoRoot
    )
    let runSummary = try tool.execute(
      ExecutionRequest(command: .run, subjects: ["SymphonyServerCLI"], outputMode: .filtered),
      currentDirectory: repoRoot
    )
    let validateSummary = try tool.execute(
      ExecutionRequest(command: .validate, subjects: ["SymphonyHarness"], outputMode: .filtered),
      currentDirectory: repoRoot
    )

    #expect(FileManager.default.fileExists(atPath: testSummary))
    #expect(FileManager.default.fileExists(atPath: runSummary))
    #expect(FileManager.default.fileExists(atPath: validateSummary))

    do {
      _ = try tool.execute(
        ExecutionRequest(command: .doctor, subjects: ["SymphonyHarness"], outputMode: .filtered),
        currentDirectory: repoRoot
      )
      Issue.record("Expected subject-scoped doctor execution to be rejected.")
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "subject_bridge_unavailable")
      #expect(error.message.contains("SymphonyHarness"))
    }

    do {
      _ = try tool.execute(
        ExecutionRequest(
          command: .build,
          subjects: [],
          explicitTestSubjects: ["SymphonyHarnessTests"],
          outputMode: .filtered
        ),
        currentDirectory: repoRoot
      )
      Issue.record("Expected build requests with explicit test subjects to be rejected.")
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "subject_bridge_unavailable")
      #expect(error.message.contains("SymphonyHarnessTests"))
    }

    do {
      _ = try tool.execute(
        ExecutionRequest(
          command: .run,
          subjects: ["SymphonyServerCLI", "SymphonyServer"],
          outputMode: .filtered
        ),
        currentDirectory: repoRoot
      )
      Issue.record("Expected run requests with multiple subjects to be rejected.")
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "subject_bridge_unavailable")
      #expect(error.message.contains("SymphonyServerCLI, SymphonyServer"))
    }

    do {
      _ = try tool.execute(
        ExecutionRequest(command: .run, subjects: ["SymphonyHarness"], outputMode: .filtered),
        currentDirectory: repoRoot
      )
      Issue.record("Expected non-runnable subjects to be rejected for run requests.")
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "subject_bridge_unavailable")
      #expect(error.message.contains("SymphonyHarness"))
    }

    do {
      _ = try tool.execute(
        ExecutionRequest(command: .test, subjects: ["UnknownHarnessSubject"], outputMode: .filtered),
        currentDirectory: repoRoot
      )
      Issue.record("Expected unknown canonical subjects to be rejected.")
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "subject_bridge_unavailable")
      #expect(error.message.contains("UnknownHarnessSubject"))
    }
  }
}

