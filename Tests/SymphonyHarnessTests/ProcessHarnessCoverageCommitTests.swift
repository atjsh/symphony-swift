import Foundation
import Testing

@testable import SymphonyHarness

@Test func commitHarnessCoversValidationFailuresAndCoverageCommandFailures() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources"), withIntermediateDirectories: true)
    let coveragePath = repoRoot.appendingPathComponent(".build/package.json")
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

    do {
      _ = try CommitHarness(processRunner: StubProcessRunner()).run(
        workspace: workspace,
        request: HarnessCommandRequest(
          minimumCoveragePercent: 101, json: false, currentDirectory: repoRoot)
      )
      Issue.record("Expected invalid coverage thresholds to fail.")
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "invalid_coverage_threshold")
    }

    do {
      _ = try CommitHarness(
        processRunner: StubProcessRunner(results: [
          "swift test --show-code-coverage-path": StubProcessRunner.success(
            coveragePath.path + "\n"),
          "swift test --enable-code-coverage": StubProcessRunner.failure("tests failed"),
        ])
      ).run(
        workspace: workspace,
        request: HarnessCommandRequest(
          minimumCoveragePercent: 0, json: false, currentDirectory: repoRoot)
      )
      Issue.record("Expected failing swift test runs to fail the harness.")
    } catch let error as SymphonyHarnessCommandFailure {
      #expect(error.message.contains("swift test --enable-code-coverage"))
    }

    do {
      _ = try CommitHarness(
        processRunner: StubProcessRunner(results: [
          "swift test --enable-code-coverage": StubProcessRunner.success(),
          "swift test --show-code-coverage-path": StubProcessRunner.failure("no path"),
        ])
      ).run(
        workspace: workspace,
        request: HarnessCommandRequest(
          minimumCoveragePercent: 0, json: false, currentDirectory: repoRoot)
      )
      Issue.record("Expected coverage-path lookup failures to fail the harness.")
    } catch let error as SymphonyHarnessCommandFailure {
      #expect(error.message.contains("coverage JSON path"))
    }

    do {
      _ = try CommitHarness(
        processRunner: StubProcessRunner(results: [
          "swift test --enable-code-coverage": StubProcessRunner.success(),
          "swift test --show-code-coverage-path": StubProcessRunner.success("\n"),
        ])
      ).run(
        workspace: workspace,
        request: HarnessCommandRequest(
          minimumCoveragePercent: 0, json: false, currentDirectory: repoRoot)
      )
      Issue.record("Expected empty coverage paths to fail.")
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "missing_package_coverage_path")
    }

    let status = SignalBox()
    let failingCoverageRunner = CoverageCommandProcessRunner(
      packageCoveragePath: coveragePath.path,
      coverageResult: CommandResult(exitStatus: 1, stdout: "", stderr: "coverage failed")
    )
    do {
      _ = try CommitHarness(processRunner: failingCoverageRunner, statusSink: { status.append($0) })
        .run(
          workspace: workspace,
          request: HarnessCommandRequest(
            minimumCoveragePercent: 0, json: false, currentDirectory: repoRoot)
        )
      Issue.record("Expected failing coverage commands to fail the harness.")
    } catch let error as SymphonyHarnessCommandFailure {
      #expect(error.message.contains("did not pass"))
    }
    #expect(status.values.contains(where: { $0.contains("running commit harness tests") }))

    let emptyCoverageRunner = CoverageCommandProcessRunner(
      packageCoveragePath: coveragePath.path,
      coverageResult: CommandResult(exitStatus: 0, stdout: "", stderr: "")
    )
    do {
      _ = try CommitHarness(processRunner: emptyCoverageRunner).run(
        workspace: workspace,
        request: HarnessCommandRequest(
          minimumCoveragePercent: 0, json: false, currentDirectory: repoRoot)
      )
      Issue.record("Expected empty test artifact root to fail.")
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "missing_test_artifact_root")
    }

    let invalidCoverageRunner = CoverageCommandProcessRunner(
      packageCoveragePath: coveragePath.path,
      coverageResult: CommandResult(exitStatus: 0, stdout: "/nonexistent/path", stderr: "")
    )
    do {
      _ = try CommitHarness(processRunner: invalidCoverageRunner).run(
        workspace: workspace,
        request: HarnessCommandRequest(
          minimumCoveragePercent: 0, json: false, currentDirectory: repoRoot)
      )
      Issue.record("Expected missing coverage.json at artifact root to fail.")
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "missing_bootstrap_coverage_json")
    }

    let undercoveredCoverageJSON = #"""
      {"coveredLines":1,"executableLines":2,"lineCoverage":0.5,"includeTestTargets":false,"excludedTargets":[],"targets":[{"name":"Suite","buildProductPath":null,"coveredLines":1,"executableLines":2,"lineCoverage":0.5,"files":[{"name":"Foo.swift","path":"/tmp/Foo.swift","coveredLines":1,"executableLines":2,"lineCoverage":0.5}]}]}
      """#
    let thresholdArtifactRoot = directory.appendingPathComponent(
      "threshold-artifacts", isDirectory: true)
    try FileManager.default.createDirectory(
      at: thresholdArtifactRoot, withIntermediateDirectories: true)
    try undercoveredCoverageJSON.write(
      to: thresholdArtifactRoot.appendingPathComponent("coverage.json"), atomically: true,
      encoding: .utf8)
    let thresholdFailureRunner = CoverageCommandProcessRunner(
      packageCoveragePath: coveragePath.path,
      coverageResult: CommandResult(exitStatus: 0, stdout: thresholdArtifactRoot.path, stderr: "")
    )
    do {
      _ = try CommitHarness(processRunner: thresholdFailureRunner).run(
        workspace: workspace,
        request: HarnessCommandRequest(
          minimumCoveragePercent: 100, json: false, currentDirectory: repoRoot)
      )
      Issue.record("Expected below-threshold coverage to fail the harness.")
    } catch let error as SymphonyHarnessCommandFailure {
      #expect(error.message.contains("below the required threshold"))
      #expect(error.message.contains("client coverage 50.00% (1/2)"))
    }

    #expect(
      CommitHarness.resolvedExecutablePath(raw: "/tmp/harness", workingDirectory: repoRoot)
        == "/tmp/harness")
    #expect(
      CommitHarness.resolvedExecutablePath(
        raw: "./.build/debug/harness", workingDirectory: repoRoot
      ).hasSuffix(".build/debug/harness"))
    #expect(
      CommitHarness.coverageSuiteArguments(
        product: "SymphonyHarness",
        platform: nil,
        outputMode: .quiet
      ) == ["test", "SymphonyHarness", "--xcode-output-mode", "quiet"]
    )
  }
}

@Test func commitHarnessCoverageSuiteRequiresReadableSharedSummaryArtifacts() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources"), withIntermediateDirectories: true)
    let packageCoveragePath = repoRoot.appendingPathComponent(".build/coverage/package.json")
    try FileManager.default.createDirectory(
      at: packageCoveragePath.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try
      #"{"data":[{"files":[{"filename":"__REPO__/Sources/Foo.swift","summary":{"lines":{"count":1,"covered":1}}}]}]}"#
      .replacingOccurrences(of: "__REPO__", with: repoRoot.path)
      .write(to: packageCoveragePath, atomically: true, encoding: .utf8)

    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: nil,
      xcodeProjectPath: nil
    )

    let missingSummaryPath = directory.appendingPathComponent("missing/summary.txt").path
    do {
      _ = try CommitHarness(
        processRunner: CoverageCommandProcessRunner(
          packageCoveragePath: packageCoveragePath.path,
          coverageResult: CommandResult(exitStatus: 0, stdout: missingSummaryPath, stderr: "")
        )
      ).run(
        workspace: workspace,
        request: HarnessCommandRequest(minimumCoveragePercent: 0, json: false, currentDirectory: repoRoot)
      )
      Issue.record("Expected missing shared summary paths to fail.")
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "missing_test_summary_path")
    }

    let missingSummaryJSONRoot = directory.appendingPathComponent("missing-summary-json", isDirectory: true)
    try FileManager.default.createDirectory(at: missingSummaryJSONRoot, withIntermediateDirectories: true)
    let missingSummaryJSONPath = missingSummaryJSONRoot.appendingPathComponent("summary.txt")
    try "summary\n".write(to: missingSummaryJSONPath, atomically: true, encoding: .utf8)
    do {
      _ = try CommitHarness(
        processRunner: CoverageCommandProcessRunner(
          packageCoveragePath: packageCoveragePath.path,
          coverageResult: CommandResult(exitStatus: 0, stdout: missingSummaryJSONPath.path, stderr: "")
        )
      ).run(
        workspace: workspace,
        request: HarnessCommandRequest(minimumCoveragePercent: 0, json: false, currentDirectory: repoRoot)
      )
      Issue.record("Expected missing shared summary JSON to fail.")
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "missing_test_summary_json")
    }

    let emptySummaryRoot = directory.appendingPathComponent("empty-summary", isDirectory: true)
    try FileManager.default.createDirectory(at: emptySummaryRoot, withIntermediateDirectories: true)
    let emptySummaryPath = emptySummaryRoot.appendingPathComponent("summary.txt")
    try "summary\n".write(to: emptySummaryPath, atomically: true, encoding: .utf8)
    let emptySummary = SharedRunSummary(
      command: .test,
      runID: "empty-summary",
      startedAt: Date(timeIntervalSince1970: 1_700_000_000),
      endedAt: Date(timeIntervalSince1970: 1_700_000_060),
      subjects: [],
      subjectResults: []
    )
    try JSONEncoder().encode(emptySummary).write(
      to: emptySummaryRoot.appendingPathComponent("summary.json")
    )
    do {
      _ = try CommitHarness(
        processRunner: CoverageCommandProcessRunner(
          packageCoveragePath: packageCoveragePath.path,
          coverageResult: CommandResult(exitStatus: 0, stdout: emptySummaryPath.path, stderr: "")
        )
      ).run(
        workspace: workspace,
        request: HarnessCommandRequest(minimumCoveragePercent: 0, json: false, currentDirectory: repoRoot)
      )
      Issue.record("Expected missing subject results to fail.")
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "missing_test_subject_result")
    }
  }
}

@Test func commitHarnessCoverageSuiteResolvesArtifactRootFromSuccessfulSharedSummary() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent(".git"),
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources"),
      withIntermediateDirectories: true
    )
    let packageCoveragePath = repoRoot.appendingPathComponent(".build/coverage/package.json")
    try FileManager.default.createDirectory(
      at: packageCoveragePath.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try
      #"{"data":[{"files":[{"filename":"__REPO__/Sources/Foo.swift","summary":{"lines":{"count":1,"covered":1}}}]}]}"#
      .replacingOccurrences(of: "__REPO__", with: repoRoot.path)
      .write(to: packageCoveragePath, atomically: true, encoding: .utf8)

    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: nil,
      xcodeProjectPath: nil
    )

    let sharedRunRoot = directory.appendingPathComponent("successful-summary", isDirectory: true)
    let subjectArtifactRoot = sharedRunRoot.appendingPathComponent("subjects/SymphonyServer", isDirectory: true)
    try FileManager.default.createDirectory(at: subjectArtifactRoot, withIntermediateDirectories: true)
    let summaryPath = sharedRunRoot.appendingPathComponent("summary.txt")
    try "summary\n".write(to: summaryPath, atomically: true, encoding: .utf8)
    let coverageJSON = #"""
      {"coveredLines":1,"executableLines":1,"lineCoverage":1,"includeTestTargets":false,"excludedTargets":[],"targets":[{"name":"Suite","buildProductPath":null,"coveredLines":1,"executableLines":1,"lineCoverage":1,"files":[]}]}
      """#
    try coverageJSON.write(
      to: subjectArtifactRoot.appendingPathComponent("coverage.json"),
      atomically: true,
      encoding: .utf8
    )
    let sharedSummary = SharedRunSummary(
      command: .test,
      runID: "successful-summary",
      startedAt: Date(timeIntervalSince1970: 1_700_000_000),
      endedAt: Date(timeIntervalSince1970: 1_700_000_060),
      subjects: ["SymphonyServer"],
      subjectResults: [
        SubjectRunResult(
          subject: "SymphonyServer",
          outcome: .success,
          artifactSet: SubjectArtifactSet(
            subject: "SymphonyServer",
            artifactRoot: subjectArtifactRoot,
            summaryPath: subjectArtifactRoot.appendingPathComponent("summary.txt"),
            indexPath: subjectArtifactRoot.appendingPathComponent("index.json"),
            coverageTextPath: nil,
            coverageJSONPath: subjectArtifactRoot.appendingPathComponent("coverage.json"),
            resultBundlePath: nil,
            logPath: subjectArtifactRoot.appendingPathComponent("process-stdout-stderr.txt"),
            anomalies: []
          )
        )
      ],
      anomalies: []
    )
    try JSONEncoder().encode(sharedSummary).write(
      to: sharedRunRoot.appendingPathComponent("summary.json")
    )

    let execution = try CommitHarness(
      processRunner: CoverageCommandProcessRunner(
        packageCoveragePath: packageCoveragePath.path,
        coverageResult: CommandResult(exitStatus: 0, stdout: summaryPath.path, stderr: "")
      ),
      clientCoverageLoader: { _ in
        CoverageReport(
          coveredLines: 1,
          executableLines: 1,
          lineCoverage: 1,
          includeTestTargets: false,
          excludedTargets: [],
          targets: []
        )
      },
      toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(
        capabilities: .fullyAvailableForTests
      )
    ).execute(
      workspace: workspace,
      request: HarnessCommandRequest(minimumCoveragePercent: 0, json: false, currentDirectory: repoRoot)
    )

    #expect(execution.report.serverCoverage.coveredLines == 1)
    #expect(execution.report.serverCoverage.executableLines == 1)
  }
}

