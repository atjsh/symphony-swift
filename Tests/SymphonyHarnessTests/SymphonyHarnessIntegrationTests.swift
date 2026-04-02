import Foundation
import Testing

@testable import SymphonyHarness

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
  let doctor = DoctorService(
    workspaceDiscovery: discovery,
    processRunner: runner,
    simulatorCatalog: StubSimulatorCatalog(devices: [
      SimulatorDevice(name: "iPhone 17", udid: "A", state: "Booted", runtime: "iOS 26"),
      SimulatorDevice(name: "iPad Pro", udid: "B", state: "Booted", runtime: "iOS 26"),
    ])
  )
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

@Test func materializeGoEnryBuildsArchiveAndMovesHeaderIntoIncludeRoot() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let sharedRoot = repoRoot.appendingPathComponent("ThirdParty/go-enry/shared", isDirectory: true)
    try FileManager.default.createDirectory(at: sharedRoot, withIntermediateDirectories: true)
    try "package main\nimport \"C\"\nfunc main() {}\n".write(
      to: sharedRoot.appendingPathComponent("enry.go"),
      atomically: true,
      encoding: .utf8
    )

    let archivePath = repoRoot.appendingPathComponent(".build/vendor/go-enry/lib/libenry.a")
    let generatedHeaderPath = repoRoot.appendingPathComponent(".build/vendor/go-enry/lib/libenry.h")
    let finalHeaderPath = repoRoot.appendingPathComponent(".build/vendor/go-enry/include/enry.h")
    let runner = GoEnryMaterializationProcessRunner(
      results: [
        "git rev-parse --show-toplevel": StubProcessRunner.success(repoRoot.path + "\n")
      ]
    )
    let tool = SymphonyHarnessTool(
      workspaceDiscovery: WorkspaceDiscovery(processRunner: runner),
      processRunner: runner
    )

    let output = try tool.materializeGoEnry(
      GoEnryMaterializationRequest(currentDirectory: repoRoot))

    #expect(FileManager.default.fileExists(atPath: archivePath.path))
    #expect(FileManager.default.fileExists(atPath: finalHeaderPath.path))
    #expect(!FileManager.default.fileExists(atPath: generatedHeaderPath.path))
    #expect(Set(runner.goBuildArchitectures) == ["amd64", "arm64"])
    #expect(runner.lipoOutputPath == archivePath.path)
    #expect(runner.lipoInputPaths.count == 2)
    #expect(output.contains(archivePath.path))
    #expect(output.contains(finalHeaderPath.path))
  }
}

