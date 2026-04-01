import Foundation

public struct XcodeCoverageInspector {
  private let processRunner: ProcessRunning

  public init(processRunner: ProcessRunning = SystemProcessRunner()) {
    self.processRunner = processRunner
  }

  public func inspect(
    resultBundlePath: URL,
    candidates: [CoverageInspectionFileCandidate],
    includeFunctions: Bool,
    includeMissingLines: Bool
  ) throws -> CoverageInspectionResult {
    guard !candidates.isEmpty else {
      return CoverageInspectionResult(files: [], rawCommands: [])
    }
    var files = [CoverageInspectionFileReport]()
    var rawCommands = [CoverageInspectionRawCommand]()

    for candidate in candidates {
      let missingLineRanges: [CoverageLineRange]
      if includeMissingLines {
        let commandLine = renderedMissingLinesCommandLine(
          resultBundlePath: resultBundlePath, filePath: candidate.path)
        let result = try processRunner.run(
          command: "xcrun",
          arguments: [
            "xccov", "view", "--archive", "--file", candidate.path, resultBundlePath.path,
          ],
          environment: [:],
          currentDirectory: nil,
          observation: nil
        )
        guard result.exitStatus == 0 else {
          throw SymphonyHarnessError(
            code: "xcode_coverage_archive_failed",
            message: result.combinedOutput.isEmpty
              ? "Failed to inspect Xcode missing lines for \(candidate.path)."
              : result.combinedOutput
          )
        }
        rawCommands.append(
          CoverageInspectionRawCommand(
            commandLine: commandLine,
            scope: "missing-lines",
            filePath: candidate.path,
            format: "text",
            output: result.stdout
          )
        )
        missingLineRanges = SwiftPMCoverageInspector.parseAnnotatedMissingLineRanges(
          output: result.stdout, separator: ":")
      } else {
        missingLineRanges = []
      }

      let functions: [CoverageInspectionFunctionReport]
      if includeFunctions {
        let commandLine = renderedFunctionsCommandLine(
          resultBundlePath: resultBundlePath, filePath: candidate.path)
        let result = try processRunner.run(
          command: "xcrun",
          arguments: [
            "xccov", "view", "--report", "--functions-for-file", candidate.path,
            resultBundlePath.path,
          ],
          environment: [:],
          currentDirectory: nil,
          observation: nil
        )
        guard result.exitStatus == 0 else {
          throw SymphonyHarnessError(
            code: "xcode_coverage_functions_failed",
            message: result.combinedOutput.isEmpty
              ? "Failed to inspect Xcode functions for \(candidate.path)." : result.combinedOutput
          )
        }
        rawCommands.append(
          CoverageInspectionRawCommand(
            commandLine: commandLine,
            scope: "functions",
            filePath: candidate.path,
            format: "text",
            output: result.stdout
          )
        )
        functions = Self.parseXcodeFunctions(output: result.stdout)
      } else {
        functions = []
      }

      files.append(
        CoverageInspectionFileReport(
          targetName: candidate.targetName,
          path: candidate.path,
          coveredLines: candidate.coveredLines,
          executableLines: candidate.executableLines,
          lineCoverage: candidate.lineCoverage,
          missingLineRanges: missingLineRanges,
          functions: functions
        )
      )
    }

    return CoverageInspectionResult(files: files, rawCommands: rawCommands)
  }

  func renderedMissingLinesCommandLine(resultBundlePath: URL, filePath: String) -> String {
    ShellQuoting.render(
      command: "xcrun",
      arguments: ["xccov", "view", "--archive", "--file", filePath, resultBundlePath.path])
  }

  func renderedFunctionsCommandLine(resultBundlePath: URL, filePath: String) -> String {
    ShellQuoting.render(
      command: "xcrun",
      arguments: [
        "xccov", "view", "--report", "--functions-for-file", filePath, resultBundlePath.path,
      ])
  }

  static func parseXcodeFunctions(output: String) -> [CoverageInspectionFunctionReport] {
    let regex = try? NSRegularExpression(
      pattern: #"^\s*\d+\s+(.*?)\s+\{\d+,\s*\d+\}\s+([0-9.]+)% \((\d+)/(\d+)\)\s*$"#
    )

    return
      output
      .split(separator: "\n")
      .compactMap { rawLine -> CoverageInspectionFunctionReport? in
        let line = String(rawLine)
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty,
          !line.hasSuffix(":"),
          !line.contains("Coverage"),
          !line.allSatisfy({ $0 == "-" || $0 == " " }),
          let regex,
          let match = regex.firstMatch(
            in: line, range: NSRange(line.startIndex..<line.endIndex, in: line)),
          let nameRange = Range(match.range(at: 1), in: line),
          let coverageRange = Range(match.range(at: 2), in: line),
          let coveredRange = Range(match.range(at: 3), in: line),
          let executableRange = Range(match.range(at: 4), in: line),
          let coveredLines = Int(line[coveredRange]),
          let executableLines = Int(line[executableRange]),
          let lineCoverage = Double(line[coverageRange])
        else {
          return nil
        }

        guard executableLines > 0, coveredLines < executableLines else {
          return nil
        }

        return CoverageInspectionFunctionReport(
          name: line[nameRange].trimmingCharacters(in: .whitespaces),
          coveredLines: coveredLines,
          executableLines: executableLines,
          lineCoverage: lineCoverage / 100
        )
      }
  }
}

func strippedCoverageReport(_ report: CoverageReport) -> CoverageReport {
  CoverageReport(
    coveredLines: report.coveredLines,
    executableLines: report.executableLines,
    lineCoverage: report.lineCoverage,
    includeTestTargets: report.includeTestTargets,
    excludedTargets: report.excludedTargets,
    targets: report.targets.map { target in
      CoverageTargetReport(
        name: target.name,
        buildProductPath: target.buildProductPath,
        coveredLines: target.coveredLines,
        executableLines: target.executableLines,
        lineCoverage: target.lineCoverage,
        files: nil
      )
    }
  )
}

func inspectionCandidates(from report: CoverageReport) -> [CoverageInspectionFileCandidate] {
  report.targets.flatMap { target in
    (target.files ?? []).compactMap { file in
      guard file.executableLines > 0, file.coveredLines < file.executableLines else {
        return nil
      }
      return CoverageInspectionFileCandidate(
        targetName: target.name,
        path: file.path,
        coveredLines: file.coveredLines,
        executableLines: file.executableLines,
        lineCoverage: file.lineCoverage
      )
    }
  }
}

func renderInspectionHuman(report: CoverageInspectionReport) -> String {
  var lines = ["inspection backend \(report.backend.rawValue)"]
  for file in report.files {
    lines.append(
      "inspection file \(file.path) \(percentage(file.lineCoverage)) (\(file.coveredLines)/\(file.executableLines))"
    )
    if !file.missingLineRanges.isEmpty {
      lines.append("missing_lines \(renderMissingLineRanges(file.missingLineRanges))")
    }
    for function in file.functions {
      lines.append(
        "function \(function.name) \(percentage(function.lineCoverage)) (\(function.coveredLines)/\(function.executableLines))"
      )
    }
  }
  return lines.joined(separator: "\n")
}

func renderRawInspectionHuman(report: CoverageInspectionRawReport) -> String {
  var lines = ["inspection raw backend \(report.backend.rawValue)"]
  for command in report.commands {
    let file = command.filePath ?? "<all-files>"
    lines.append("command \(command.scope) \(file) \(command.format)")
    lines.append(command.commandLine)
    lines.append(command.output.isEmpty ? "<empty>" : command.output)
  }
  return lines.joined(separator: "\n")
}

func renderHarnessInspectionHuman(artifact: HarnessCoverageInspectionArtifact) -> String {
  var lines = ["\(artifact.suite) inspection backend \(artifact.backend.rawValue)"]
  if let skippedReason = artifact.skippedReason {
    lines.append("skipped \(skippedReason)")
  }
  for file in artifact.files {
    lines.append(
      "inspection file \(file.path) \(percentage(file.lineCoverage)) (\(file.coveredLines)/\(file.executableLines))"
    )
    if !file.missingLineRanges.isEmpty {
      lines.append("missing_lines \(renderMissingLineRanges(file.missingLineRanges))")
    }
    for function in file.functions {
      lines.append(
        "function \(function.name) \(percentage(function.lineCoverage)) (\(function.coveredLines)/\(function.executableLines))"
      )
    }
  }
  return lines.joined(separator: "\n")
}

func renderMissingLineRanges(_ ranges: [CoverageLineRange]) -> String {
  ranges.map { range in
    if range.startLine == range.endLine {
      return "\(range.startLine)"
    }
    return "\(range.startLine)-\(range.endLine)"
  }
  .joined(separator: ",")
}

func encodePrettyJSON<T: Encodable>(_ value: T) throws -> String {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  return String(decoding: try encoder.encode(value), as: UTF8.self)
}

private func percentage(_ coverage: Double) -> String {
  String(format: "%.2f%%", locale: Locale(identifier: "en_US_POSIX"), coverage * 100)
}
