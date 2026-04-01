import Foundation
import SymphonyHarness
import Testing

@testable import SymphonyHarnessCLI

struct PreviewSubjectFixture {
  let name: String
  let coverage: CoverageReport?
  let inspection: CoverageInspectionReport?
}

final class PreviewFormattingCLITool: SymphonyHarnessTooling {
  var executionRequests = [ExecutionRequest]()
  var doctorRequests = [DoctorCommandRequest]()
  var materializeRequests = [GoEnryMaterializationRequest]()
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

  func materializeGoEnry(_ request: GoEnryMaterializationRequest) throws -> String {
    materializeRequests.append(request)
    return "materialize-output"
  }
}

final class OutputBox {
  private(set) var values = [String]()

  func append(_ value: String) {
    values.append(value)
  }
}

func makeSummaryFixture(
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

func makeCoverageReport(coveredLines: Int, executableLines: Int) -> CoverageReport {
  CoverageReport(
    coveredLines: coveredLines,
    executableLines: executableLines,
    lineCoverage: executableLines > 0 ? Double(coveredLines) / Double(executableLines) : 0,
    includeTestTargets: false,
    excludedTargets: [],
    targets: []
  )
}

func makeInspectionReport(
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

func makeInspectionFile(
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

func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    UUID().uuidString,
    isDirectory: true
  )
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  try body(root)
}
