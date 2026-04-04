import Foundation
import Testing

@testable import SymphonyHarness

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
        invocation: "swift test --scratch-path .build/swiftpm-cache --enable-code-coverage --filter SymphonyServerTests",
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
      "swift test --scratch-path .build/swiftpm-cache --enable-code-coverage": StubProcessRunner.success("tests passed\n"),
      "swift test --scratch-path .build/swiftpm-cache --show-code-coverage-path": StubProcessRunner.success(coveragePath.path + "\n"),
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
