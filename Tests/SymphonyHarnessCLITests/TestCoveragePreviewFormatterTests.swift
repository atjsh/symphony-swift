import Foundation
import SymphonyHarness
import Testing

@testable import SymphonyHarnessCLI

@Test func formatterRendersSingleSubjectRichPreview() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    let summaryPath = try makeSummaryFixture(
      repoRoot: repoRoot,
      subjects: [
        PreviewSubjectFixture(
          name: "SymphonyHarness",
          coverage: makeCoverageReport(coveredLines: 18, executableLines: 24),
          inspection: makeInspectionReport(
            target: .server,
            files: [
              makeInspectionFile(
                path: repoRoot.appendingPathComponent("Sources/SymphonyHarness/SymphonyHarnessTool.swift").path,
                coveredLines: 8,
                executableLines: 12,
                missingLineRanges: [(1935, 2027)],
                functions: [
                  ("SymphonyHarness.SymphonyHarnessTool.executeRepositoryValidationPolicies(...)", 0, 12),
                  ("SymphonyHarness.SymphonyHarnessTool.writeSyntheticSubjectArtifacts(...)", 0, 8),
                ]
              )
            ]
          )
        )
      ]
    )

    let output = TestCoveragePreviewFormatter().formatIfPossible(summaryPath.path)

    #expect(output.hasPrefix(summaryPath.path))
    #expect(output.contains("subject SymphonyHarness"))
    #expect(output.contains("coverage 75.00% (18/24)"))
    #expect(
      output.contains(
        "inspection \(summaryPath.deletingLastPathComponent().appendingPathComponent("subjects/SymphonyHarness/coverage-inspection.txt").path)"
      ))
    #expect(
      output.contains(
        "file Sources/SymphonyHarness/SymphonyHarnessTool.swift 66.67% (8/12)"
      ))
    #expect(output.contains("  missing_lines 1935-2027"))
    #expect(
      output.contains(
        "  function SymphonyHarness.SymphonyHarnessTool.executeRepositoryValidationPolicies(...)"
      ))
    #expect(
      output.contains(
        "  function SymphonyHarness.SymphonyHarnessTool.writeSyntheticSubjectArtifacts(...)"
      ))
  }
}

@Test func formatterNormalizesAbsolutePathsAndCapsHotspotsAndFunctions() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    let files = [
      makeInspectionFile(
        path: repoRoot.appendingPathComponent("Sources/Four.swift").path,
        coveredLines: 7,
        executableLines: 12,
        missingLineRanges: [(40, 42)],
        functions: [("fn4", 2, 7)]
      ),
      makeInspectionFile(
        path: repoRoot.appendingPathComponent("Sources/Three.swift").path,
        coveredLines: 4,
        executableLines: 12,
        missingLineRanges: [(30, 32)],
        functions: [("fn3", 1, 8)]
      ),
      makeInspectionFile(
        path: repoRoot.appendingPathComponent("Sources/Two.swift").path,
        coveredLines: 3,
        executableLines: 12,
        missingLineRanges: [(20, 22)],
        functions: [
          ("fn2a", 0, 9),
          ("fn2b", 0, 8),
          ("fn2c", 0, 7),
          ("fn2d", 0, 6),
        ]
      ),
      makeInspectionFile(
        path: repoRoot.appendingPathComponent("Sources/One.swift").path,
        coveredLines: 2,
        executableLines: 12,
        missingLineRanges: [(10, 12)],
        functions: [("fn1", 0, 10)]
      ),
    ]
    let summaryPath = try makeSummaryFixture(
      repoRoot: repoRoot,
      subjects: [
        PreviewSubjectFixture(
          name: "SymphonyHarness",
          coverage: makeCoverageReport(coveredLines: 16, executableLines: 48),
          inspection: makeInspectionReport(target: .server, files: files)
        )
      ]
    )

    let output = TestCoveragePreviewFormatter().formatIfPossible(summaryPath.path)

    #expect(!output.contains(repoRoot.appendingPathComponent("Sources/One.swift").path))
    let oneIndex = try #require(output.range(of: "file Sources/One.swift 16.67% (2/12)")?.lowerBound)
    let twoIndex = try #require(output.range(of: "file Sources/Two.swift 25.00% (3/12)")?.lowerBound)
    let threeIndex = try #require(output.range(of: "file Sources/Three.swift 33.33% (4/12)")?.lowerBound)
    #expect(output.range(of: "file Sources/Four.swift") == nil)
    #expect(oneIndex < twoIndex)
    #expect(twoIndex < threeIndex)
    #expect(output.contains("  function fn2a"))
    #expect(output.contains("  function fn2b"))
    #expect(output.contains("  function fn2c"))
    #expect(!output.contains("  function fn2d"))
  }
}

@Test func formatterRendersMultipleSubjectsInSummaryOrder() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    let summaryPath = try makeSummaryFixture(
      repoRoot: repoRoot,
      subjects: [
        PreviewSubjectFixture(
          name: "SymphonyShared",
          coverage: makeCoverageReport(coveredLines: 4, executableLines: 4),
          inspection: makeInspectionReport(target: .server, files: [])
        ),
        PreviewSubjectFixture(
          name: "SymphonyHarness",
          coverage: makeCoverageReport(coveredLines: 6, executableLines: 10),
          inspection: makeInspectionReport(
            target: .server,
            files: [makeInspectionFile(path: "Sources/Harness.swift", coveredLines: 6, executableLines: 10)]
          )
        ),
      ]
    )

    let output = TestCoveragePreviewFormatter().formatIfPossible(summaryPath.path)

    let sharedIndex = try #require(output.range(of: "subject SymphonyShared")?.lowerBound)
    let harnessIndex = try #require(output.range(of: "subject SymphonyHarness")?.lowerBound)
    #expect(sharedIndex < harnessIndex)
  }
}

@Test func formatterPrintsHotspotsNoneForFullyCoveredSubject() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    let summaryPath = try makeSummaryFixture(
      repoRoot: repoRoot,
      subjects: [
        PreviewSubjectFixture(
          name: "SymphonyServer",
          coverage: makeCoverageReport(coveredLines: 32, executableLines: 32),
          inspection: makeInspectionReport(target: .server, files: [])
        )
      ]
    )

    let output = TestCoveragePreviewFormatter().formatIfPossible(summaryPath.path)

    #expect(output.contains("subject SymphonyServer"))
    #expect(output.contains("coverage 100.00% (32/32)"))
    #expect(output.contains("hotspots none"))
  }
}

@Test func formatterFallsBackWhenCoverageInspectionIsMissing() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    let summaryPath = try makeSummaryFixture(
      repoRoot: repoRoot,
      subjects: [
        PreviewSubjectFixture(
          name: "SymphonyHarness",
          coverage: makeCoverageReport(coveredLines: 10, executableLines: 20),
          inspection: nil
        )
      ]
    )

    let output = TestCoveragePreviewFormatter().formatIfPossible(summaryPath.path)
    let subjectRoot = summaryPath.deletingLastPathComponent().appendingPathComponent("subjects/SymphonyHarness")

    #expect(output.contains("subject SymphonyHarness"))
    #expect(output.contains("coverage preview unavailable"))
    #expect(output.contains("reason missing coverage-inspection.json"))
    #expect(
      output.contains(
        "expected \(subjectRoot.appendingPathComponent("coverage-inspection.json").path)"
      ))
    #expect(output.contains("artifacts \(subjectRoot.path)"))
  }
}

@Test func formatterFallsBackWhenCoverageJSONIsMissing() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    let summaryPath = try makeSummaryFixture(
      repoRoot: repoRoot,
      subjects: [
        PreviewSubjectFixture(
          name: "SymphonyHarness",
          coverage: nil,
          inspection: makeInspectionReport(
            target: .server,
            files: [makeInspectionFile(path: "Sources/Harness.swift", coveredLines: 1, executableLines: 2)]
          )
        )
      ]
    )

    let output = TestCoveragePreviewFormatter().formatIfPossible(summaryPath.path)
    let subjectRoot = summaryPath.deletingLastPathComponent().appendingPathComponent("subjects/SymphonyHarness")

    #expect(output.contains("subject SymphonyHarness"))
    #expect(output.contains("coverage preview unavailable"))
    #expect(output.contains("reason missing coverage.json"))
    #expect(output.contains("expected \(subjectRoot.appendingPathComponent("coverage.json").path)"))
    #expect(output.contains("artifacts \(subjectRoot.path)"))
  }
}

@Test func formatterFallsBackWhenSummaryJSONIsMissing() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    let summaryPath = try makeSummaryFixture(
      repoRoot: repoRoot,
      subjects: [],
      writeSummaryJSON: false
    )

    let output = TestCoveragePreviewFormatter().formatIfPossible(summaryPath.path)

    #expect(output.hasPrefix(summaryPath.path))
    #expect(output.contains("coverage preview unavailable"))
    #expect(output.contains("reason missing summary.json"))
    #expect(
      output.contains(
        "expected \(summaryPath.deletingLastPathComponent().appendingPathComponent("summary.json").path)"
      ))
  }
}

@Test func formatterFallsBackWhenSummaryJSONIsMalformed() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    let summaryPath = try makeSummaryFixture(
      repoRoot: repoRoot,
      subjects: [],
      malformedSummaryJSON: "{not-json"
    )

    let output = TestCoveragePreviewFormatter().formatIfPossible(summaryPath.path)
    let summaryJSONPath = summaryPath.deletingLastPathComponent().appendingPathComponent("summary.json")

    #expect(output.hasPrefix(summaryPath.path))
    #expect(output.contains("coverage preview unavailable"))
    #expect(output.contains("reason failed to decode summary.json"))
    #expect(output.contains("expected \(summaryJSONPath.path)"))
  }
}

@Test func formatterBypassesPathLikeOutputContainingNewlines() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    let summaryPath = try makeSummaryFixture(repoRoot: repoRoot, subjects: [])

    let output = TestCoveragePreviewFormatter().formatIfPossible("\(summaryPath.path)\nextra")

    #expect(output == "\(summaryPath.path)\nextra")
  }
}

@Test func formatterPreservesAbsolutePathsOutsideRepositoryRoot() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    let externalPath = directory.appendingPathComponent("outside/External.swift").path
    let summaryPath = try makeSummaryFixture(
      repoRoot: repoRoot,
      subjects: [
        PreviewSubjectFixture(
          name: "SymphonyHarnessCLI",
          coverage: makeCoverageReport(coveredLines: 2, executableLines: 4),
          inspection: makeInspectionReport(
            target: .server,
            files: [makeInspectionFile(path: externalPath, coveredLines: 2, executableLines: 4)]
          )
        )
      ]
    )

    let output = TestCoveragePreviewFormatter().formatIfPossible(summaryPath.path)

    #expect(output.contains("file \(externalPath) 50.00% (2/4)"))
  }
}

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
      currentDirectoryProvider: { repoRoot }
    ) {
      var test =
        try SymphonyHarnessCommand.Test.parseAsRoot([
          "SymphonyHarness",
          "--xcode-output-mode", "quiet",
        ]) as! SymphonyHarnessCommand.Test
      try test.run()
    }

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

private struct PreviewSubjectFixture {
  let name: String
  let coverage: CoverageReport?
  let inspection: CoverageInspectionReport?
}

private final class PreviewFormattingCLITool: SymphonyHarnessTooling {
  var executionRequests = [ExecutionRequest]()
  var doctorRequests = [DoctorCommandRequest]()
  private let testOutput: String

  init(testOutput: String) {
    self.testOutput = testOutput
  }

  func build(_ request: ExecutionRequest) throws -> String {
    executionRequests.append(request)
    return "build-output"
  }

  func test(_ request: ExecutionRequest) throws -> String {
    executionRequests.append(request)
    return testOutput
  }

  func run(_ request: ExecutionRequest) throws -> String {
    executionRequests.append(request)
    return "run-output"
  }

  func validate(_ request: ExecutionRequest) throws -> String {
    executionRequests.append(request)
    return "validate-output"
  }

  func doctor(_ request: DoctorCommandRequest) throws -> String {
    doctorRequests.append(request)
    return "doctor-output"
  }
}

private final class OutputBox {
  private(set) var values = [String]()

  func append(_ value: String) {
    values.append(value)
  }
}

private func makeSummaryFixture(
  repoRoot: URL,
  subjects: [PreviewSubjectFixture],
  writeSummaryJSON: Bool = true,
  malformedSummaryJSON: String? = nil
) throws -> URL {
  let runRoot = repoRoot.appendingPathComponent(".build/harness/runs/preview-run", isDirectory: true)
  let subjectsRoot = runRoot.appendingPathComponent("subjects", isDirectory: true)
  try FileManager.default.createDirectory(at: subjectsRoot, withIntermediateDirectories: true)
  let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
  let endedAt = Date(timeIntervalSince1970: 1_700_000_060)

  var subjectResults = [SubjectRunResult]()
  for fixture in subjects {
    let subjectRoot = subjectsRoot.appendingPathComponent(fixture.name, isDirectory: true)
    try FileManager.default.createDirectory(at: subjectRoot, withIntermediateDirectories: true)
    let summaryPath = subjectRoot.appendingPathComponent("summary.txt")
    let indexPath = subjectRoot.appendingPathComponent("index.json")
    let logPath = subjectRoot.appendingPathComponent("process-stdout-stderr.txt")
    try "subject \(fixture.name)\n".write(to: summaryPath, atomically: true, encoding: .utf8)
    try "{}\n".write(to: indexPath, atomically: true, encoding: .utf8)
    try "<empty>\n".write(to: logPath, atomically: true, encoding: .utf8)

    let coverageTextPath: URL?
    let coverageJSONPath: URL?
    if let coverage = fixture.coverage {
      let coverageJSONURL = subjectRoot.appendingPathComponent("coverage.json")
      let coverageTextURL = subjectRoot.appendingPathComponent("coverage.txt")
      try JSONEncoder().encode(coverage).write(to: coverageJSONURL)
      try "coverage\n".write(to: coverageTextURL, atomically: true, encoding: .utf8)
      coverageJSONPath = coverageJSONURL
      coverageTextPath = coverageTextURL
    } else {
      coverageJSONPath = nil
      coverageTextPath = nil
    }

    if let inspection = fixture.inspection {
      try JSONEncoder().encode(inspection).write(
        to: subjectRoot.appendingPathComponent("coverage-inspection.json"))
      try "inspection\n".write(
        to: subjectRoot.appendingPathComponent("coverage-inspection.txt"),
        atomically: true,
        encoding: .utf8
      )
    }

    let artifactSet = SubjectArtifactSet(
      subject: fixture.name,
      artifactRoot: subjectRoot,
      summaryPath: summaryPath,
      indexPath: indexPath,
      coverageTextPath: coverageTextPath,
      coverageJSONPath: coverageJSONPath,
      resultBundlePath: nil,
      logPath: logPath
    )
    subjectResults.append(
      SubjectRunResult(subject: fixture.name, outcome: .success, artifactSet: artifactSet))
  }

  let summary = SharedRunSummary(
    command: .test,
    runID: "preview-run",
    startedAt: startedAt,
    endedAt: endedAt,
    subjects: subjects.map(\.name),
    subjectResults: subjectResults
  )
  let summaryPath = runRoot.appendingPathComponent("summary.txt")
  try "shared summary\n".write(to: summaryPath, atomically: true, encoding: .utf8)
  if let malformedSummaryJSON {
    try malformedSummaryJSON.write(
      to: runRoot.appendingPathComponent("summary.json"),
      atomically: true,
      encoding: .utf8
    )
  } else if writeSummaryJSON {
    try JSONEncoder().encode(summary).write(to: runRoot.appendingPathComponent("summary.json"))
  }

  return summaryPath
}

private func makeCoverageReport(coveredLines: Int, executableLines: Int) -> CoverageReport {
  CoverageReport(
    coveredLines: coveredLines,
    executableLines: executableLines,
    lineCoverage: executableLines > 0 ? Double(coveredLines) / Double(executableLines) : 0,
    includeTestTargets: false,
    excludedTargets: [],
    targets: []
  )
}

private func makeInspectionReport(
  target: RuntimeTarget,
  files: [CoverageInspectionFileReport]
) -> CoverageInspectionReport {
  CoverageInspectionReport(
    backend: target == .client ? .xcode : .swiftPM,
    target: target,
    generatedAt: "2026-03-28T00:00:00Z",
    files: files
  )
}

private func makeInspectionFile(
  path: String,
  coveredLines: Int,
  executableLines: Int,
  missingLineRanges: [(Int, Int)] = [],
  functions: [(String, Int, Int)] = []
) -> CoverageInspectionFileReport {
  CoverageInspectionFileReport(
    targetName: "Target",
    path: path,
    coveredLines: coveredLines,
    executableLines: executableLines,
    lineCoverage: executableLines > 0 ? Double(coveredLines) / Double(executableLines) : 0,
    missingLineRanges: missingLineRanges.map { CoverageLineRange(startLine: $0.0, endLine: $0.1) },
    functions: functions.map { name, covered, executable in
      CoverageInspectionFunctionReport(
        name: name,
        coveredLines: covered,
        executableLines: executable,
        lineCoverage: executable > 0 ? Double(covered) / Double(executable) : 0
      )
    }
  )
}

private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    UUID().uuidString,
    isDirectory: true
  )
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  try body(root)
}
