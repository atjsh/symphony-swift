import Foundation
import SymphonyHarness

struct TestCoveragePreviewFormatter {
  func formatIfPossible(_ rawOutput: String) -> String {
    guard let summaryPath = readableSummaryPath(from: rawOutput) else {
      return rawOutput
    }

    var lines = [summaryPath.path]
    let summaryJSONPath = summaryPath.deletingLastPathComponent().appendingPathComponent("summary.json")

    do {
      let summary = try decode(SharedRunSummary.self, at: summaryJSONPath, named: "summary.json")
      let repositoryRoot = repositoryRoot(for: summaryPath)
      for result in summary.subjectResults {
        lines.append("")
        lines.append(contentsOf: renderSubject(result, repositoryRoot: repositoryRoot))
      }
    } catch {
      let error = error as! PreviewArtifactError
      lines.append("")
      lines.append("coverage preview unavailable")
      lines.append("reason \(error.reason)")
      lines.append("expected \(error.expectedPath.path)")
    }

    return lines.joined(separator: "\n")
  }

  private func renderSubject(_ result: SubjectRunResult, repositoryRoot: URL?) -> [String] {
    let artifactRoot = result.artifactSet.artifactRoot
    let coverageJSONPath = result.artifactSet.coverageJSONPath
      ?? artifactRoot.appendingPathComponent("coverage.json")
    let inspectionJSONPath = artifactRoot.appendingPathComponent("coverage-inspection.json")
    let inspectionTextPath = artifactRoot.appendingPathComponent("coverage-inspection.txt")

    do {
      let coverage = try decode(CoverageReport.self, at: coverageJSONPath, named: "coverage.json")
      let inspection = try decode(
        CoverageInspectionReport.self,
        at: inspectionJSONPath,
        named: "coverage-inspection.json"
      )
      return renderRichPreview(
        subject: result.subject,
        coverage: coverage,
        inspection: inspection,
        inspectionTextPath: inspectionTextPath,
        repositoryRoot: repositoryRoot
      )
    } catch {
      let error = error as! PreviewArtifactError
      return [
        "subject \(result.subject)",
        "coverage preview unavailable",
        "reason \(error.reason)",
        "expected \(error.expectedPath.path)",
        "artifacts \(artifactRoot.path)",
      ]
    }
  }

  private func renderRichPreview(
    subject: String,
    coverage: CoverageReport,
    inspection: CoverageInspectionReport,
    inspectionTextPath: URL,
    repositoryRoot: URL?
  ) -> [String] {
    var lines = [
      "subject \(subject)",
      "coverage \(percentage(coverage.lineCoverage)) (\(coverage.coveredLines)/\(coverage.executableLines))",
      "inspection \(inspectionTextPath.path)",
    ]

    let hotspotFiles = inspection.files
      .filter { uncoveredLines(in: $0) > 0 }
      .sorted(by: compareFiles)
      .prefix(3)

    if hotspotFiles.isEmpty {
      lines.append("hotspots none")
      return lines
    }

    for file in hotspotFiles {
      lines.append(
        "file \(normalizedSourcePath(file.path, repositoryRoot: repositoryRoot)) \(percentage(file.lineCoverage)) (\(file.coveredLines)/\(file.executableLines))"
      )
      if !file.missingLineRanges.isEmpty {
        lines.append("  missing_lines \(renderMissingLineRanges(file.missingLineRanges))")
      }
      let functions = file.functions
        .filter { uncoveredLines(in: $0) > 0 }
        .sorted(by: compareFunctions)
        .prefix(3)
      for function in functions {
        lines.append("  function \(function.name)")
      }
    }

    return lines
  }

  private func readableSummaryPath(from rawOutput: String) -> URL? {
    let trimmed = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !trimmed.contains("\n"), !trimmed.contains("\r") else {
      return nil
    }

    let candidate = URL(fileURLWithPath: trimmed)
    var isDirectory = ObjCBool(false)
    guard candidate.lastPathComponent == "summary.txt",
      FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
      !isDirectory.boolValue,
      FileManager.default.isReadableFile(atPath: candidate.path)
    else {
      return nil
    }

    return candidate
  }

  private func decode<Value: Decodable>(_ type: Value.Type, at path: URL, named name: String) throws
    -> Value
  {
    guard FileManager.default.fileExists(atPath: path.path) else {
      throw PreviewArtifactError.missing(name: name, path: path)
    }

    do {
      let data = try Data(contentsOf: path)
      return try JSONDecoder().decode(Value.self, from: data)
    } catch {
      throw PreviewArtifactError.invalid(name: name, path: path)
    }
  }

  private func repositoryRoot(for summaryPath: URL) -> URL? {
    let standardized = summaryPath.standardizedFileURL.path
    guard let buildRange = standardized.range(of: "/.build/"),
      buildRange.lowerBound > standardized.startIndex
    else {
      return nil
    }
    let root = String(standardized[..<buildRange.lowerBound])
    return URL(fileURLWithPath: root, isDirectory: true)
  }

  private func normalizedSourcePath(_ path: String, repositoryRoot: URL?) -> String {
    guard path.hasPrefix("/") else {
      return path
    }
    guard let repositoryRoot else {
      return path
    }

    let root = repositoryRoot.standardizedFileURL.path
    let candidate = URL(fileURLWithPath: path).standardizedFileURL.path
    guard candidate == root || candidate.hasPrefix(root + "/") else {
      return path
    }

    let index = candidate.index(candidate.startIndex, offsetBy: root.count)
    let suffix = String(candidate[index...]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return suffix.isEmpty ? path : suffix
  }

  private func uncoveredLines(in file: CoverageInspectionFileReport) -> Int {
    max(file.executableLines - file.coveredLines, 0)
  }

  private func uncoveredLines(in function: CoverageInspectionFunctionReport) -> Int {
    max(function.executableLines - function.coveredLines, 0)
  }

  private func compareFiles(
    _ lhs: CoverageInspectionFileReport,
    _ rhs: CoverageInspectionFileReport
  ) -> Bool {
    let lhsUncovered = uncoveredLines(in: lhs)
    let rhsUncovered = uncoveredLines(in: rhs)
    if lhsUncovered != rhsUncovered {
      return lhsUncovered > rhsUncovered
    }
    if lhs.lineCoverage != rhs.lineCoverage {
      return lhs.lineCoverage < rhs.lineCoverage
    }
    return lhs.path < rhs.path
  }

  private func compareFunctions(
    _ lhs: CoverageInspectionFunctionReport,
    _ rhs: CoverageInspectionFunctionReport
  ) -> Bool {
    let lhsUncovered = uncoveredLines(in: lhs)
    let rhsUncovered = uncoveredLines(in: rhs)
    if lhsUncovered != rhsUncovered {
      return lhsUncovered > rhsUncovered
    }
    if lhs.lineCoverage != rhs.lineCoverage {
      return lhs.lineCoverage < rhs.lineCoverage
    }
    return lhs.name < rhs.name
  }

  private func renderMissingLineRanges(_ ranges: [CoverageLineRange]) -> String {
    ranges.map { range in
      if range.startLine == range.endLine {
        return "\(range.startLine)"
      }
      return "\(range.startLine)-\(range.endLine)"
    }
    .joined(separator: ",")
  }

  private func percentage(_ coverage: Double) -> String {
    String(format: "%.2f%%", locale: Locale(identifier: "en_US_POSIX"), coverage * 100)
  }
}

private enum PreviewArtifactError: Error {
  case missing(name: String, path: URL)
  case invalid(name: String, path: URL)

  var reason: String {
    switch self {
    case .missing(let name, _):
      return "missing \(name)"
    case .invalid(let name, _):
      return "failed to decode \(name)"
    }
  }

  var expectedPath: URL {
    switch self {
    case .missing(_, let path), .invalid(_, let path):
      return path
    }
  }
}
