import Foundation
import Testing

@testable import SymphonyHarness

@Test func commitHarnessCoverageSuiteUsesFirstSummaryPathLineWhenCLIAddsCoveragePreview() throws {
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

    let sharedRunRoot = directory.appendingPathComponent("multiline-summary", isDirectory: true)
    let subjectArtifactRoot = sharedRunRoot.appendingPathComponent("subjects/SymphonySwiftUIApp", isDirectory: true)
    try FileManager.default.createDirectory(at: subjectArtifactRoot, withIntermediateDirectories: true)
    let summaryPath = sharedRunRoot.appendingPathComponent("summary.txt")
    try "summary\n".write(to: summaryPath, atomically: true, encoding: .utf8)
    let coverageJSON = #"""
      {"coveredLines":1,"executableLines":1,"lineCoverage":1,"includeTestTargets":false,"excludedTargets":[],"targets":[{"name":"Symphony.app","buildProductPath":null,"coveredLines":1,"executableLines":1,"lineCoverage":1,"files":[]}]}
      """#
    try coverageJSON.write(
      to: subjectArtifactRoot.appendingPathComponent("coverage.json"),
      atomically: true,
      encoding: .utf8
    )
    let sharedSummary = SharedRunSummary(
      command: .test,
      runID: "multiline-summary",
      startedAt: Date(timeIntervalSince1970: 1_700_000_000),
      endedAt: Date(timeIntervalSince1970: 1_700_000_060),
      subjects: ["SymphonySwiftUIApp"],
      subjectResults: [
        SubjectRunResult(
          subject: "SymphonySwiftUIApp",
          outcome: .success,
          artifactSet: SubjectArtifactSet(
            subject: "SymphonySwiftUIApp",
            artifactRoot: subjectArtifactRoot,
            summaryPath: subjectArtifactRoot.appendingPathComponent("summary.txt"),
            indexPath: subjectArtifactRoot.appendingPathComponent("index.json"),
            coverageTextPath: subjectArtifactRoot.appendingPathComponent("coverage.txt"),
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

    let inspectionPath = subjectArtifactRoot.appendingPathComponent("coverage-inspection.txt").path
    let previewOutput = [
      summaryPath.path,
      "",
      "subject SymphonySwiftUIApp",
      "coverage 100.00% (1/1)",
      "inspection \(inspectionPath)",
      "hotspots none",
    ].joined(separator: "\n")

    let execution = try CommitHarness(
      processRunner: CoverageCommandProcessRunner(
        packageCoveragePath: packageCoveragePath.path,
        coverageResult: CommandResult(exitStatus: 0, stdout: previewOutput, stderr: "")
      ),
      clientCoverageLoader: { _ in
        CoverageReport(
          coveredLines: 1,
          executableLines: 1,
          lineCoverage: 1,
          includeTestTargets: false,
          excludedTargets: [],
          targets: [
            CoverageTargetReport(
              name: "Symphony.app",
              buildProductPath: nil,
              coveredLines: 1,
              executableLines: 1,
              lineCoverage: 1,
              files: []
            )
          ]
        )
      },
      toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(
        capabilities: .fullyAvailableForTests
      )
    ).execute(
      workspace: workspace,
      request: HarnessCommandRequest(minimumCoveragePercent: 0, json: false, currentDirectory: repoRoot)
    )

    #expect(try #require(execution.report.clientCoverage).coveredLines == 1)
    #expect(execution.report.serverCoverage.coveredLines == 1)
  }
}

@Test func commitHarnessUsesDefaultCoverageLoadersForBothClientAndServer() throws {
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
    let artifactRoot = directory.appendingPathComponent("artifacts", isDirectory: true)
    try FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)
    try coverageJSON.write(
      to: artifactRoot.appendingPathComponent("coverage.json"), atomically: true, encoding: .utf8)
    let runner = DualCoverageProcessRunner(
      packageCoveragePath: coveragePath.path, artifactRoot: artifactRoot.path)

    let report = try CommitHarness(
      processRunner: runner,
      statusSink: { _ in },
      toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(
        capabilities: .fullyAvailableForTests)
    ).run(
      workspace: workspace,
      request: HarnessCommandRequest(
        minimumCoveragePercent: 0, json: false, currentDirectory: repoRoot)
    )

    #expect(try #require(report.clientCoverage).targets.map { $0.name } == ["Suite"])
    #expect(report.serverCoverage.targets.map { $0.name } == ["Suite"])
  }
}

@Test func commitHarnessExecuteDecodesInspectionFromArtifactFiles() throws {
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
    let coverageReport = CoverageReport(
      coveredLines: 1,
      executableLines: 2,
      lineCoverage: 0.5,
      includeTestTargets: false,
      excludedTargets: [],
      targets: [
        CoverageTargetReport(
          name: "Suite", buildProductPath: nil, coveredLines: 1, executableLines: 2,
          lineCoverage: 0.5,
          files: [
            CoverageFileReport(
              name: "Foo.swift", path: "/tmp/Foo.swift", coveredLines: 1, executableLines: 2,
              lineCoverage: 0.5)
          ])
      ]
    )
    let inspectionReport = CoverageInspectionReport(
      backend: .swiftPM,
      product: .server,
      generatedAt: "2026-03-25T00:00:00Z",
      files: [
        CoverageInspectionFileReport(
          targetName: "Suite",
          path: "/tmp/Foo.swift",
          coveredLines: 1,
          executableLines: 2,
          lineCoverage: 0.5,
          missingLineRanges: [CoverageLineRange(startLine: 10, endLine: 10)],
          functions: []
        )
      ]
    )

    // Create artifact directories with coverage files on disk
    let artifactRoot = directory.appendingPathComponent("artifacts", isDirectory: true)
    try FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)
    try JSONEncoder().encode(coverageReport).write(
      to: artifactRoot.appendingPathComponent("coverage.json"))
    try JSONEncoder().encode(inspectionReport).write(
      to: artifactRoot.appendingPathComponent("coverage-inspection.json"))

    let runner = ArtifactPathProcessRunner(
      packageCoveragePath: coveragePath.path, artifactRoot: artifactRoot.path)

    let execution = try CommitHarness(
      processRunner: runner,
      statusSink: { _ in },
      toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(
        capabilities: .fullyAvailableForTests)
    ).execute(
      workspace: workspace,
      request: HarnessCommandRequest(
        minimumCoveragePercent: 0, json: false, currentDirectory: repoRoot)
    )

    #expect(execution.report.clientCoverage == coverageReport)
    #expect(execution.report.serverCoverage == coverageReport)
    #expect(execution.clientInspection == inspectionReport)
    #expect(execution.serverInspection == inspectionReport)

    // Test without inspection file — harness should still succeed with nil inspection
    let noInspectionArtifactRoot = directory.appendingPathComponent(
      "artifacts-no-inspection", isDirectory: true)
    try FileManager.default.createDirectory(
      at: noInspectionArtifactRoot, withIntermediateDirectories: true)
    try JSONEncoder().encode(coverageReport).write(
      to: noInspectionArtifactRoot.appendingPathComponent("coverage.json"))

    let noInspectionRunner = ArtifactPathProcessRunner(
      packageCoveragePath: coveragePath.path, artifactRoot: noInspectionArtifactRoot.path)
    let noInspectionExecution = try CommitHarness(
      processRunner: noInspectionRunner,
      statusSink: { _ in },
      toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(
        capabilities: .fullyAvailableForTests)
    ).execute(
      workspace: workspace,
      request: HarnessCommandRequest(
        minimumCoveragePercent: 0, json: false, currentDirectory: repoRoot)
    )
    #expect(noInspectionExecution.clientInspection == nil)
    #expect(noInspectionExecution.serverInspection == nil)
  }
}
