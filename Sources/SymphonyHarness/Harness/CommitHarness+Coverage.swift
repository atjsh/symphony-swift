import Foundation

extension CommitHarness {
  static func runCoverageSuite(
    processRunner: ProcessRunning,
    executablePath: String,
    arguments: [String],
    currentDirectory: URL,
    statusSink: @escaping @Sendable (String) -> Void
  ) throws -> CoverageReport {
    try runCoverageSuiteExecution(
      processRunner: processRunner,
      executablePath: executablePath,
      arguments: arguments,
      currentDirectory: currentDirectory,
      statusSink: statusSink
    ).report
  }

  static func resolveSwiftPMCoveragePath(
    processRunner: ProcessRunning,
    projectRoot: URL
  ) throws -> URL {
    let coveragePathResult = try processRunner.run(
      command: "swift",
      arguments: ["test", "--show-code-coverage-path"],
      environment: [:],
      currentDirectory: projectRoot,
      observation: nil
    )
    guard coveragePathResult.exitStatus == 0 else {
      throw SymphonyHarnessCommandFailure(
        message: "Commit harness failed because SwiftPM did not return a coverage JSON path.")
    }

    let rawPath = coveragePathResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !rawPath.isEmpty else {
      throw SymphonyHarnessError(
        code: "missing_package_coverage_path",
        message: "SwiftPM returned an empty coverage JSON path.")
    }

    return URL(fileURLWithPath: rawPath)
  }

  static func clearExistingCoverageExport(at coveragePath: URL) throws {
    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: coveragePath.path) {
      try fileManager.removeItem(at: coveragePath)
    }
  }

  static func runCoverageSuiteExecution(
    processRunner: ProcessRunning,
    executablePath: String,
    arguments: [String],
    currentDirectory: URL,
    statusSink: @escaping @Sendable (String) -> Void
  ) throws -> CoverageSuiteExecution {
    let label = "harness " + arguments.joined(separator: " ")
    let result = try processRunner.run(
      command: executablePath,
      arguments: arguments,
      environment: [:],
      currentDirectory: currentDirectory,
      observation: ProcessObservation(
        label: label,
        onStaleSignal: { message in
          statusSink(message)
        },
        onLine: { stream, line in
          guard stream == .stderr else {
            return
          }
          let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !trimmed.isEmpty else {
            return
          }
          statusSink(trimmed)
        }
      )
    )

    guard result.exitStatus == 0 else {
      throw SymphonyHarnessCommandFailure(
        message:
          "Commit harness failed because `\(ShellQuoting.render(command: executablePath, arguments: arguments))` did not pass."
      )
    }

    let outputPath = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !outputPath.isEmpty else {
      throw SymphonyHarnessError(
        code: "missing_test_artifact_root",
        message: "The test command did not return a shared summary or artifact root path.")
    }
    let artifactRootURL = try resolveCoverageArtifactRoot(from: outputPath)

    let coverageJSONPath = artifactRootURL.appendingPathComponent("coverage.json")
    guard FileManager.default.fileExists(atPath: coverageJSONPath.path) else {
      throw SymphonyHarnessError(
        code: "missing_bootstrap_coverage_json",
        message: "The test artifact root does not contain coverage.json.")
    }
    let coverageData = try Data(contentsOf: coverageJSONPath)
    let report = try JSONDecoder().decode(CoverageReport.self, from: coverageData)

    let inspectionJSONPath = artifactRootURL.appendingPathComponent("coverage-inspection.json")
    var inspection: CoverageInspectionReport?
    if FileManager.default.fileExists(atPath: inspectionJSONPath.path) {
      let inspectionData = try Data(contentsOf: inspectionJSONPath)
      inspection = try JSONDecoder().decode(CoverageInspectionReport.self, from: inspectionData)
    }

    return CoverageSuiteExecution(report: report, inspection: inspection)
  }

  static func currentExecutablePath(workingDirectory: URL) -> String {
    var rawPath = ProcessInfo.processInfo.processName
    if let firstArgument = CommandLine.arguments.first {
      rawPath = firstArgument
    }
    return resolvedExecutablePath(raw: rawPath, workingDirectory: workingDirectory)
  }

  static func resolvedExecutablePath(raw: String, workingDirectory: URL) -> String {
    if raw.hasPrefix("/") {
      return raw
    }
    return URL(fileURLWithPath: raw, relativeTo: workingDirectory).standardizedFileURL.path
  }

  static func coverageSuiteArguments(
    product: String, platform: String?, outputMode: XcodeOutputMode
  ) -> [String] {
    let subject: String
    switch product {
    case "client":
      subject = "SymphonySwiftUIApp"
    case "server":
      subject = "SymphonyServer"
    default:
      subject = product
    }

    var arguments = ["test", subject]
    if outputMode != .filtered {
      arguments.append(contentsOf: ["--xcode-output-mode", outputMode.rawValue])
    }
    _ = platform
    return arguments
  }

  static func resolveCoverageArtifactRoot(from outputPath: String) throws -> URL {
    var canonicalPath = outputPath.trimmingCharacters(in: .whitespacesAndNewlines)
    for line in outputPath.components(separatedBy: .newlines) {
      let candidate = line.trimmingCharacters(in: .whitespacesAndNewlines)
      if !candidate.isEmpty {
        canonicalPath = candidate
        break
      }
    }
    let resolvedURL = URL(fileURLWithPath: canonicalPath)
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: resolvedURL.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    {
      return resolvedURL
    }

    guard resolvedURL.lastPathComponent == "summary.txt" else {
      return resolvedURL
    }

    let sharedSummaryURL =
      resolvedURL.lastPathComponent == "summary.txt"
      ? resolvedURL : resolvedURL.appendingPathComponent("summary.txt")
    guard FileManager.default.fileExists(atPath: sharedSummaryURL.path) else {
      throw SymphonyHarnessError(
        code: "missing_test_summary_path",
        message: "The test command did not return a readable shared summary path."
      )
    }

    let sharedSummaryJSONURL = sharedSummaryURL.deletingLastPathComponent().appendingPathComponent(
      "summary.json")
    guard FileManager.default.fileExists(atPath: sharedSummaryJSONURL.path) else {
      throw SymphonyHarnessError(
        code: "missing_test_summary_json",
        message: "The shared run root does not contain summary.json."
      )
    }

    let summary = try JSONDecoder().decode(
      SharedRunSummary.self,
      from: Data(contentsOf: sharedSummaryJSONURL)
    )
    guard let subjectResult = summary.subjectResults.first else {
      throw SymphonyHarnessError(
        code: "missing_test_subject_result",
        message: "The shared run summary did not include any subject results."
      )
    }
    return subjectResult.artifactSet.artifactRoot
  }

  static func inspectPackageCoverageFiles(
    report: PackageCoverageReport,
    projectRoot: URL,
    processRunner: ProcessRunning,
    llvmCovCommand: LLVMCovCommand?
  ) throws -> [CoverageInspectionFileReport] {
    guard let llvmCovCommand else {
      return []
    }
    let candidates = report.files.compactMap { file -> CoverageInspectionFileCandidate? in
      guard file.executableLines > 0, file.coveredLines < file.executableLines else {
        return nil
      }
      let components = file.path.split(separator: "/")
      let targetName = components.count > 2 ? String(components[1]) : "Sources"
      return CoverageInspectionFileCandidate(
        targetName: targetName,
        path: file.path,
        coveredLines: file.coveredLines,
        executableLines: file.executableLines,
        lineCoverage: file.lineCoverage
      )
    }
    guard !candidates.isEmpty else {
      return []
    }

    let inspection = try SwiftPMCoverageInspector(
      processRunner: processRunner,
      llvmCovCommand: llvmCovCommand
    ).inspect(
      coverageJSONPath: URL(fileURLWithPath: report.coverageJSONPath),
      projectRoot: projectRoot,
      candidates: candidates,
      includeFunctions: true,
      includeMissingLines: true
    )
    return inspection.files
  }

  static func applyInspectionFiles(
    _ inspectionFiles: [CoverageInspectionFileReport],
    to violations: [HarnessCoverageViolation],
    processRunner: ProcessRunning,
    xcrunAvailable: Bool
  ) -> [HarnessCoverageViolation] {
    var demangledNames = [String: String]()
    return violations.map { violation in
      let fileReport = inspectionFiles.first { $0.path == violation.name }
      let functions = fileReport?
        .functions
        .map {
          demangleCoverageFunctionName(
            $0.name,
            processRunner: processRunner,
            xcrunAvailable: xcrunAvailable,
            cache: &demangledNames
          )
        }
      let missingLineRanges = fileReport?.missingLineRanges
      return HarnessCoverageViolation(
        suite: violation.suite,
        kind: violation.kind,
        name: violation.name,
        coveredLines: violation.coveredLines,
        executableLines: violation.executableLines,
        lineCoverage: violation.lineCoverage,
        uncoveredFunctions: functions?.isEmpty == false ? functions : nil,
        missingLineRanges: missingLineRanges?.isEmpty == false ? missingLineRanges : nil
      )
    }
  }

  static func demangleCoverageFunctionName(
    _ name: String,
    processRunner: ProcessRunning,
    xcrunAvailable: Bool,
    cache: inout [String: String]
  ) -> String {
    if let cached = cache[name] {
      return cached
    }

    let resolvedName: String
    if xcrunAvailable,
      isSwiftMangledSymbol(name),
      let demangled = try? demangleSwiftSymbol(name, processRunner: processRunner)
    {
      resolvedName = demangled
    } else {
      resolvedName = name
    }
    cache[name] = resolvedName
    return resolvedName
  }

  static func isSwiftMangledSymbol(_ name: String) -> Bool {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.hasPrefix("$s")
      || trimmed.hasPrefix("_$s")
      || trimmed.hasPrefix("$S")
      || trimmed.hasPrefix("_$S")
  }

  static func demangleSwiftSymbol(_ symbol: String, processRunner: ProcessRunning) throws
    -> String
  {
    let result = try processRunner.run(
      command: "xcrun",
      arguments: ["swift-demangle", symbol],
      environment: [:],
      currentDirectory: nil,
      observation: nil
    )
    guard result.exitStatus == 0 else {
      return symbol
    }

    let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !output.isEmpty else {
      return symbol
    }
    let firstLine: String
    if let newlineIndex = output.firstIndex(of: "\n") {
      firstLine = String(output[..<newlineIndex])
    } else {
      firstLine = output
    }
    guard let separatorRange = firstLine.range(of: " ---> ") else {
      return firstLine
    }
    return String(firstLine[separatorRange.upperBound...]).trimmingCharacters(
      in: .whitespacesAndNewlines
    )
  }
}
