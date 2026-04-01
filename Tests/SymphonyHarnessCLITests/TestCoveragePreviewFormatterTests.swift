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

