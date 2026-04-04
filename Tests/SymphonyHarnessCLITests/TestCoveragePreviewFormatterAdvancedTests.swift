// swiftlint:disable force_cast
import Foundation
import SymphonyHarness
import Testing

@testable import SymphonyHarnessCLI

@Test func formatterFallsBackToAbsolutePathsWhenSummaryIsOutsideBuildRoot() throws {
  try withTemporaryDirectory { directory in
    let runRoot = directory.appendingPathComponent("preview-run", isDirectory: true)
    let subjectRoot = runRoot.appendingPathComponent("subjects/SymphonyHarnessCLI", isDirectory: true)
    try FileManager.default.createDirectory(at: subjectRoot, withIntermediateDirectories: true)

    let summaryPath = runRoot.appendingPathComponent("summary.txt")
    let summaryJSONPath = runRoot.appendingPathComponent("summary.json")
    let sourcePath = directory.appendingPathComponent("Sources/Formatter.swift").path

    try "summary\n".write(to: summaryPath, atomically: true, encoding: .utf8)
    try "subject\n".write(
      to: subjectRoot.appendingPathComponent("summary.txt"),
      atomically: true,
      encoding: .utf8
    )
    try "{}\n".write(
      to: subjectRoot.appendingPathComponent("index.json"),
      atomically: true,
      encoding: .utf8
    )
    try "log\n".write(
      to: subjectRoot.appendingPathComponent("process-stdout-stderr.txt"),
      atomically: true,
      encoding: .utf8
    )
    try JSONEncoder().encode(makeCoverageReport(coveredLines: 3, executableLines: 5)).write(
      to: subjectRoot.appendingPathComponent("coverage.json")
    )
    try "coverage\n".write(
      to: subjectRoot.appendingPathComponent("coverage.txt"),
      atomically: true,
      encoding: .utf8
    )
    try JSONEncoder().encode(
          makeInspectionReport(
            target: .server,
        files: [makeInspectionFile(path: sourcePath, coveredLines: 3, executableLines: 5)]
      )
    ).write(to: subjectRoot.appendingPathComponent("coverage-inspection.json"))
    try "inspection\n".write(
      to: subjectRoot.appendingPathComponent("coverage-inspection.txt"),
      atomically: true,
      encoding: .utf8
    )

    let artifactSet = SubjectArtifactSet(
      subject: "SymphonyHarnessCLI",
      artifactRoot: subjectRoot,
      summaryPath: subjectRoot.appendingPathComponent("summary.txt"),
      indexPath: subjectRoot.appendingPathComponent("index.json"),
      coverageTextPath: subjectRoot.appendingPathComponent("coverage.txt"),
      coverageJSONPath: subjectRoot.appendingPathComponent("coverage.json"),
      resultBundlePath: nil,
      logPath: subjectRoot.appendingPathComponent("process-stdout-stderr.txt")
    )
    let summary = SharedRunSummary(
      command: .test,
      runID: "preview-run",
      startedAt: Date(timeIntervalSince1970: 1_700_000_000),
      endedAt: Date(timeIntervalSince1970: 1_700_000_060),
      subjects: ["SymphonyHarnessCLI"],
      subjectResults: [
        SubjectRunResult(
          subject: "SymphonyHarnessCLI",
          outcome: .success,
          artifactSet: artifactSet
        )
      ]
    )
    try JSONEncoder().encode(summary).write(to: summaryJSONPath)

    let output = TestCoveragePreviewFormatter().formatIfPossible(summaryPath.path)

    #expect(output.contains("file \(sourcePath) 60.00% (3/5)"))
  }
}

@Test func formatterSortsTiedHotspotsByCoverageAndName() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    let summaryPath = try makeSummaryFixture(
      repoRoot: repoRoot,
      subjects: [
        PreviewSubjectFixture(
          name: "SymphonyHarnessCLI",
          coverage: makeCoverageReport(coveredLines: 9, executableLines: 18),
          inspection: makeInspectionReport(
            target: .server,
            files: [
              makeInspectionFile(
                path: repoRoot.appendingPathComponent("Sources/Beta.swift").path,
                coveredLines: 4,
                executableLines: 8,
                functions: [
                  ("zeta", 3, 5),
                  ("alpha", 3, 5),
                ]
              ),
              makeInspectionFile(
                path: repoRoot.appendingPathComponent("Sources/Alpha.swift").path,
                coveredLines: 4,
                executableLines: 8,
                missingLineRanges: [(18, 18)],
                functions: []
              ),
              makeInspectionFile(
                path: repoRoot.appendingPathComponent("Sources/Gamma.swift").path,
                coveredLines: 1,
                executableLines: 2,
                functions: []
              ),
            ]
          )
        )
      ]
    )

    let output = TestCoveragePreviewFormatter().formatIfPossible(summaryPath.path)

    let alphaIndex = try #require(output.range(of: "file Sources/Alpha.swift 50.00% (4/8)")?.lowerBound)
    let betaIndex = try #require(output.range(of: "file Sources/Beta.swift 50.00% (4/8)")?.lowerBound)
    #expect(alphaIndex < betaIndex)
    let alphaFunctionIndex = try #require(output.range(of: "  function alpha")?.lowerBound)
    let zetaFunctionIndex = try #require(output.range(of: "  function zeta")?.lowerBound)
    #expect(alphaFunctionIndex < zetaFunctionIndex)
    #expect(output.contains("  missing_lines 18"))
  }
}

@Test func formatterSortsTiesByLowerCoverageBeforePathAndName() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    let summaryPath = try makeSummaryFixture(
      repoRoot: repoRoot,
      subjects: [
        PreviewSubjectFixture(
          name: "SymphonyHarnessCLI",
          coverage: makeCoverageReport(coveredLines: 9, executableLines: 18),
          inspection: makeInspectionReport(
            target: .server,
            files: [
              makeInspectionFile(
                path: repoRoot.appendingPathComponent("Sources/HigherCoverage.swift").path,
                coveredLines: 5,
                executableLines: 9,
                functions: [("higher", 5, 9)]
              ),
              makeInspectionFile(
                path: repoRoot.appendingPathComponent("Sources/LowerCoverage.swift").path,
                coveredLines: 4,
                executableLines: 8,
                functions: [("higherCoverageName", 4, 8), ("lowerCoverageName", 5, 9)]
              ),
            ]
          )
        )
      ]
    )

    let output = TestCoveragePreviewFormatter().formatIfPossible(summaryPath.path)

    let lowerCoverageIndex = try #require(
      output.range(of: "file Sources/LowerCoverage.swift 50.00% (4/8)")?.lowerBound
    )
    let higherCoverageIndex = try #require(
      output.range(of: "file Sources/HigherCoverage.swift 55.56% (5/9)")?.lowerBound
    )
    #expect(lowerCoverageIndex < higherCoverageIndex)
    let lowerFunctionIndex = try #require(output.range(of: "  function higherCoverageName")?.lowerBound)
    let higherFunctionIndex = try #require(output.range(of: "  function lowerCoverageName")?.lowerBound)
    #expect(lowerFunctionIndex < higherFunctionIndex)
  }
}

@Test func formatterBypassesRawNonPathOutput() {
  let output = TestCoveragePreviewFormatter().formatIfPossible("test-output")

  #expect(output == "test-output")
}

@Test func testCommandEmitsFormattedCoveragePreviewInQuietMode() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    let summaryPath = try makeSummaryFixture(
      repoRoot: repoRoot,
      subjects: [
        PreviewSubjectFixture(
          name: "SymphonyHarness",
          coverage: makeCoverageReport(coveredLines: 9, executableLines: 12),
          inspection: makeInspectionReport(
            target: .server,
            files: [makeInspectionFile(path: "Sources/Harness.swift", coveredLines: 6, executableLines: 10)]
          )
        )
      ]
    )
    let tool = PreviewFormattingCLITool(testOutput: summaryPath.path)
    let output = OutputBox()

    try CLIContext.withOverrides(
      toolFactory: { tool },
      printer: { output.append($0) },
      currentDirectoryProvider: { repoRoot },
      operation: {
        var test =
          try SymphonyHarnessCommand.Test.parseAsRoot([
            "SymphonyHarness",
            "--xcode-output-mode", "quiet",
          ]) as! SymphonyHarnessCommand.Test
        try test.run()
      }
    )

    #expect(tool.executionRequests.count == 1)
    #expect(tool.executionRequests[0].command == .test)
    #expect(tool.executionRequests[0].subjects == ["SymphonyHarness"])
    #expect(tool.executionRequests[0].outputMode == .quiet)
    let rendered = try #require(output.values.first)
    #expect(rendered.hasPrefix(summaryPath.path))
    #expect(rendered.contains("subject SymphonyHarness"))
    #expect(rendered.contains("coverage 75.00% (9/12)"))
  }
}

// swiftlint:enable force_cast
