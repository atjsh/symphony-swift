import Foundation
import Testing

@testable import SymphonyHarness

@Test func subjectExecutionBridgeSpecializedEntryPointsRejectDoctorRequests() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
      xcodeProjectPath: nil
    )
    let runner = RoutedProcessRunner { _, _, _, _, _ in
      Issue.record("Doctor guard should reject specialized entry points before subprocess execution.")
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
    let doctorRequest = ExecutionRequest(
      command: .doctor,
      subjects: ["SymphonyHarness"],
      outputMode: .filtered
    )

    for specializedEntryPoint in [
      { try tool.build(doctorRequest) },
      { try tool.test(doctorRequest) },
      { try tool.run(doctorRequest) },
      { try tool.validate(doctorRequest) },
    ] {
      do {
        _ = try specializedEntryPoint()
        Issue.record("Expected specialized entry points to reject doctor requests.")
      } catch let error as SymphonyHarnessError {
        #expect(error.code == "subject_bridge_unavailable")
        #expect(error.message.contains("SymphonyHarness"))
      }
    }
  }
}

@Test func validationPolicyHelpersCoverArtifactFailuresAndDefaultAppFallbacks() throws {
  try withTemporaryDirectory { directory in
    let artifactRoot = directory.appendingPathComponent("subject-artifacts", isDirectory: true)
    try FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)
    let summaryPath = artifactRoot.appendingPathComponent("summary.txt")
    let indexPath = artifactRoot.appendingPathComponent("index.json")
    let logPath = artifactRoot.appendingPathComponent("process-stdout-stderr.txt")
    try "summary".write(to: summaryPath, atomically: true, encoding: .utf8)
    try "{}".write(to: indexPath, atomically: true, encoding: .utf8)
    try "log".write(to: logPath, atomically: true, encoding: .utf8)

    let successResult = SubjectRunResult(
      subject: "SymphonyHarness",
      outcome: .success,
      artifactSet: SubjectArtifactSet(
        subject: "SymphonyHarness",
        artifactRoot: artifactRoot,
        summaryPath: summaryPath,
        indexPath: indexPath,
        coverageTextPath: nil,
        coverageJSONPath: nil,
        resultBundlePath: nil,
        logPath: logPath,
        anomalies: []
      )
    )
    let missingArtifactResult = SubjectRunResult(
      subject: "SymphonyHarness",
      outcome: .success,
      artifactSet: SubjectArtifactSet(
        subject: "SymphonyHarness",
        artifactRoot: artifactRoot,
        summaryPath: artifactRoot.appendingPathComponent("missing-summary.txt"),
        indexPath: indexPath,
        coverageTextPath: nil,
        coverageJSONPath: nil,
        resultBundlePath: nil,
        logPath: logPath,
        anomalies: []
      )
    )

    let artifactSuccess = SymphonyHarnessTool.artifactValidationPolicyOutcome(for: [successResult])
    #expect(artifactSuccess.summaryLines == ["validation_policy_result artifacts: success"])
    #expect(artifactSuccess.anomalies.isEmpty)
    #expect(artifactSuccess.failureMessage == nil)

    let artifactFailure = SymphonyHarnessTool.artifactValidationPolicyOutcome(for: [missingArtifactResult])
    #expect(artifactFailure.summaryLines == ["validation_policy_result artifacts: failure"])
    #expect(artifactFailure.anomalies.map(\.code) == ["artifact_policy_failed"])
    #expect(artifactFailure.failureMessage == "validate failed for repository artifact policies.")

    let appFallback = SymphonyHarnessTool.defaultAppValidationPolicyOutcome(
      subjectResults: [successResult],
      supportsSimulatorCommands: true,
      buildStateRoot: directory
    )
    #expect(appFallback.summaryLines.contains("validation_policy_result xcodeTestPlans: failure"))
    #expect(appFallback.summaryLines.contains("validation_policy_result accessibility: success"))
    #expect(appFallback.anomalies.map(\.code) == ["xcode_test_plans_failed"])
    #expect(appFallback.failureMessage == "validate failed for required app validation plans.")
  }
}

@Test func validateExecutionBridgeCapturesPolicyExceptions() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
      xcodeProjectPath: nil
    )
    let coveragePath = repoRoot.appendingPathComponent(".build/policy-coverage.json")
    let coverageJSON = #"""
    {
      "data": [
        {
          "files": [
            { "filename": "__REPO__/Sources/SymphonyShared/SharedApp.swift", "summary": { "lines": { "count": 2, "covered": 2 } } },
            { "filename": "__REPO__/Sources/SymphonyServerCore/Orchestrator.swift", "summary": { "lines": { "count": 2, "covered": 2 } } },
            { "filename": "__REPO__/Sources/SymphonyServer/ProviderAdapter.swift", "summary": { "lines": { "count": 2, "covered": 2 } } },
            { "filename": "__REPO__/Sources/SymphonyServerCLI/main.swift", "summary": { "lines": { "count": 2, "covered": 2 } } },
            { "filename": "__REPO__/Sources/SymphonyHarness/SymphonyHarnessTool.swift", "summary": { "lines": { "count": 2, "covered": 2 } } },
            { "filename": "__REPO__/Sources/SymphonyHarnessCLI/SymphonyHarnessCommand.swift", "summary": { "lines": { "count": 2, "covered": 2 } } },
            { "filename": "__REPO__/Sources/harness/main.swift", "summary": { "lines": { "count": 1, "covered": 1 } } }
          ]
        }
      ]
    }
    """#.replacingOccurrences(of: "__REPO__", with: repoRoot.path)

    let runner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "swift",
        arguments.count >= 4,
        arguments[0] == "test",
        arguments[1] == "--enable-code-coverage",
        arguments[2] == "--filter"
      {
        try FileManager.default.createDirectory(
          at: coveragePath.deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
        try coverageJSON.write(to: coveragePath, atomically: true, encoding: .utf8)
        return StubProcessRunner.success("swift coverage ok")
      }
      if command == "swift", arguments == ["test", "--show-code-coverage-path"] {
        return StubProcessRunner.success(coveragePath.path + "\n")
      }
      return StubProcessRunner.success()
    }

    let failingDoctor = ThrowingDoctorService(
      error: SymphonyHarnessError(code: "synthetic_doctor_failure", message: "doctor exploded")
    )
    let coverageCapabilities = StubToolchainCapabilitiesResolver(capabilities: .noXcodeForTests)
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
      doctorService: failingDoctor,
      toolchainCapabilitiesResolver: coverageCapabilities,
      productLocator: ProductLocator(processRunner: runner),
      commitHarness: CommitHarness(
        processRunner: runner,
        statusSink: { _ in },
        serverCoverageLoader: { _ in
          throw SymphonyHarnessError(
            code: "synthetic_coverage_failure",
            message: "coverage exploded"
          )
        },
        toolchainCapabilitiesResolver: coverageCapabilities
      ),
      gitHookInstaller: GitHookInstaller(processRunner: runner),
      statusSink: { _ in }
    )

    do {
      _ = try tool.validate(
        ExecutionRequest(command: .validate, subjects: [], explicitTestSubjects: [], outputMode: .filtered)
      )
      Issue.record("Expected default validate to fail when policy checks throw and artifacts are removed.")
    } catch let error as SymphonyHarnessCommandFailure {
      let summaryPath = try #require(error.summaryPath)
      let summaryText = try String(contentsOf: summaryPath, encoding: .utf8)
      #expect(summaryText.contains("validation_policy_result environment: failure"))
      #expect(summaryText.contains("validation_policy_result coverage: failure"))
      #expect(summaryText.contains("environment_policy_failed"))
      #expect(summaryText.contains("coverage_policy_failed"))
    }
  }
}

@Test func validateExecutionBridgeCapturesCoverageFailureWithoutEarlierEnvironmentFailure() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
      xcodeProjectPath: nil
    )
    let coveragePath = repoRoot.appendingPathComponent(".build/policy-coverage.json")
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
        arguments.count >= 4,
        arguments[0] == "test",
        arguments[1] == "--enable-code-coverage",
        arguments[2] == "--filter"
      {
        return StubProcessRunner.success("swift coverage ok")
      }
      if command == "swift", arguments == ["test", "--show-code-coverage-path"] {
        return StubProcessRunner.success(coveragePath.path + "\n")
      }
      return StubProcessRunner.success()
    }
    let capabilities = StubToolchainCapabilitiesResolver(capabilities: .noXcodeForTests)
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
      toolchainCapabilitiesResolver: capabilities,
      productLocator: ProductLocator(processRunner: runner),
      commitHarness: CommitHarness(
        processRunner: runner,
        statusSink: { _ in },
        serverCoverageLoader: { _ in
          throw SymphonyHarnessError(
            code: "synthetic_coverage_failure",
            message: "coverage exploded"
          )
        },
        toolchainCapabilitiesResolver: capabilities
      ),
      gitHookInstaller: GitHookInstaller(processRunner: runner),
      statusSink: { _ in }
    )

    do {
      _ = try tool.validate(
        ExecutionRequest(command: .validate, subjects: [], explicitTestSubjects: [], outputMode: .filtered)
      )
      Issue.record("Expected default validate to fail when coverage policy fails.")
    } catch let error as SymphonyHarnessCommandFailure {
      let summaryPath = try #require(error.summaryPath)
      let summaryText = try String(contentsOf: summaryPath, encoding: .utf8)
      #expect(summaryText.contains("validation_policy_result environment: success"))
      #expect(summaryText.contains("validation_policy_result coverage: failure"))
      #expect(summaryText.contains("coverage_policy_failed"))
    }
  }
}

@Test
func validateExecutionBridgeCapturesBelowThresholdCoverageFailureFromCommitHarnessExecution()
  throws
{
  try withTemporaryRepositoryFixture { repoRoot in
    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
      xcodeProjectPath: nil
    )
    let coveragePath = repoRoot.appendingPathComponent(".build/policy-success-coverage.json")
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
        arguments.count >= 4,
        arguments[0] == "test",
        arguments[1] == "--enable-code-coverage",
        arguments[2] == "--filter"
      {
        return StubProcessRunner.success("swift coverage ok")
      }
      if command == "swift", arguments == ["test", "--show-code-coverage-path"] {
        return StubProcessRunner.success(coveragePath.path + "\n")
      }
      return StubProcessRunner.success()
    }
    let lowServerCoverage = CoverageReport(
      coveredLines: 1,
      executableLines: 2,
      lineCoverage: 0.5,
      includeTestTargets: false,
      excludedTargets: [],
      targets: [
        CoverageTargetReport(
          name: "SymphonyServer",
          buildProductPath: nil,
          coveredLines: 1,
          executableLines: 2,
          lineCoverage: 0.5,
          files: [
            CoverageFileReport(
              name: "BootstrapSupport.swift",
              path: "Sources/SymphonyServer/BootstrapSupport.swift",
              coveredLines: 1,
              executableLines: 2,
              lineCoverage: 0.5
            )
          ]
        )
      ]
    )
    let capabilities = StubToolchainCapabilitiesResolver(capabilities: .noXcodeForTests)
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
      toolchainCapabilitiesResolver: capabilities,
      productLocator: ProductLocator(processRunner: runner),
      commitHarness: CommitHarness(
        processRunner: runner,
        statusSink: { _ in },
        serverCoverageLoader: { _ in lowServerCoverage },
        toolchainCapabilitiesResolver: capabilities
      ),
      gitHookInstaller: GitHookInstaller(processRunner: runner),
      statusSink: { _ in }
    )

    do {
      _ = try tool.validate(
        ExecutionRequest(command: .validate, subjects: [], explicitTestSubjects: [], outputMode: .filtered)
      )
      Issue.record(
        "Expected default validate to fail when commit harness coverage is below threshold."
      )
    } catch let error as SymphonyHarnessCommandFailure {
      let summaryPath = try #require(error.summaryPath)
      let summaryText = try String(contentsOf: summaryPath, encoding: .utf8)
      #expect(error.message == "validate failed for repository coverage policies.")
      #expect(summaryText.contains("validation_policy_result environment: success"))
      #expect(summaryText.contains("validation_policy_result coverage: failure"))
      #expect(summaryText.contains("coverage_policy_failed"))
    }
  }
}

