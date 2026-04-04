import Foundation

public struct CoverageInspectionFileCandidate: Hashable, Sendable {
  public let targetName: String
  public let path: String
  public let coveredLines: Int
  public let executableLines: Int
  public let lineCoverage: Double

  public init(
    targetName: String, path: String, coveredLines: Int, executableLines: Int, lineCoverage: Double
  ) {
    self.targetName = targetName
    self.path = path
    self.coveredLines = coveredLines
    self.executableLines = executableLines
    self.lineCoverage = lineCoverage
  }
}

public struct CoverageInspectionResult: Hashable, Sendable {
  public let files: [CoverageInspectionFileReport]
  public let rawCommands: [CoverageInspectionRawCommand]

  public init(files: [CoverageInspectionFileReport], rawCommands: [CoverageInspectionRawCommand]) {
    self.files = files
    self.rawCommands = rawCommands
  }
}

public struct HarnessCoverageInspectionArtifact: Codable, Hashable, Sendable {
  public let suite: String
  public let backend: ProductBackend
  public let generatedAt: String
  public let files: [CoverageInspectionFileReport]
  public let skippedReason: String?

  public init(
    suite: String,
    backend: ProductBackend,
    generatedAt: String,
    files: [CoverageInspectionFileReport],
    skippedReason: String? = nil
  ) {
    self.suite = suite
    self.backend = backend
    self.generatedAt = generatedAt
    self.files = files
    self.skippedReason = skippedReason
  }
}

public struct SwiftPMCoverageContext: Hashable, Sendable {
  public let profileDataPath: URL
  public let testBinaryPath: URL

  public init(profileDataPath: URL, testBinaryPath: URL) {
    self.profileDataPath = profileDataPath
    self.testBinaryPath = testBinaryPath
  }
}

public struct SwiftPMCoverageInspector {
  private let processRunner: ProcessRunning
  private let fileManager: FileManager
  private let llvmCovCommand: LLVMCovCommand?

  public init(
    processRunner: ProcessRunning = SystemProcessRunner(),
    fileManager: FileManager = .default,
    llvmCovCommand: LLVMCovCommand? = nil
  ) {
    self.processRunner = processRunner
    self.fileManager = fileManager
    self.llvmCovCommand = llvmCovCommand
  }

  public func resolveContext(coverageJSONPath: URL) throws -> SwiftPMCoverageContext {
    let codecovRoot = coverageJSONPath.deletingLastPathComponent()
    let profileDataPath = codecovRoot.appendingPathComponent("default.profdata")
    guard fileManager.fileExists(atPath: profileDataPath.path) else {
      throw SymphonyHarnessError(
        code: "missing_swiftpm_profdata",
        message:
          "SwiftPM coverage inspection requires a profile data file at \(profileDataPath.path)."
      )
    }

    let debugRoot = codecovRoot.deletingLastPathComponent()
    let packageName = coverageJSONPath.deletingPathExtension().lastPathComponent
    let preferredBinaryPath =
      debugRoot
      .appendingPathComponent("\(packageName)PackageTests.xctest", isDirectory: true)
      .appendingPathComponent("Contents/MacOS", isDirectory: true)
      .appendingPathComponent("\(packageName)PackageTests")
    if isRegularFile(at: preferredBinaryPath) {
      return SwiftPMCoverageContext(
        profileDataPath: profileDataPath, testBinaryPath: preferredBinaryPath)
    }

    let preferredLinuxBinaryPath = debugRoot.appendingPathComponent(
      "\(packageName)PackageTests.xctest")
    if isRegularFile(at: preferredLinuxBinaryPath) {
      return SwiftPMCoverageContext(
        profileDataPath: profileDataPath, testBinaryPath: preferredLinuxBinaryPath)
    }

    let preferredDirectBinaryPath = debugRoot.appendingPathComponent("\(packageName)PackageTests")
    if isRegularFile(at: preferredDirectBinaryPath) {
      return SwiftPMCoverageContext(
        profileDataPath: profileDataPath, testBinaryPath: preferredDirectBinaryPath)
    }

    if let fallback = resolveFallbackTestBinary(debugRoot: debugRoot) {
      return SwiftPMCoverageContext(profileDataPath: profileDataPath, testBinaryPath: fallback)
    }

    throw SymphonyHarnessError(
      code: "missing_swiftpm_test_binary",
      message: "SwiftPM coverage inspection requires a PackageTests binary under \(debugRoot.path)."
    )
  }

  public func inspect(
    coverageJSONPath: URL,
    projectRoot: URL,
    candidates: [CoverageInspectionFileCandidate],
    includeFunctions: Bool,
    includeMissingLines: Bool
  ) throws -> CoverageInspectionResult {
    guard !candidates.isEmpty else {
      return CoverageInspectionResult(files: [], rawCommands: [])
    }
    let context = try resolveContext(coverageJSONPath: coverageJSONPath)
    let llvmCovCommand = try resolvedLLVMCovCommand()
    let resolvedRoot = projectRoot.resolvingSymlinksInPath()

    var files = [CoverageInspectionFileReport]()
    var rawCommands = [CoverageInspectionRawCommand]()
    for candidate in candidates {
      let filePath = absolutePath(for: candidate.path, projectRoot: resolvedRoot)
      let fileURL = URL(fileURLWithPath: filePath)
      let missingLineRanges: [CoverageLineRange]
      if includeMissingLines {
        let commandLine = renderedShowCommandLine(
          llvmCovCommand: llvmCovCommand,
          profileDataPath: context.profileDataPath,
          testBinaryPath: context.testBinaryPath,
          filePath: filePath
        )
        let invocation = llvmCovInvocation(
          command: llvmCovCommand,
          arguments: [
            "show", "-instr-profile", context.profileDataPath.path, context.testBinaryPath.path,
            filePath,
          ])
        let result = try processRunner.run(
          command: invocation.command,
          arguments: invocation.arguments,
          environment: [:],
          currentDirectory: nil,
          observation: nil
        )
        guard result.exitStatus == 0 else {
          throw SymphonyHarnessError(
            code: "swiftpm_coverage_inspection_failed",
            message: result.combinedOutput.isEmpty
              ? "Failed to inspect SwiftPM missing lines for \(candidate.path)."
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
        missingLineRanges = Self.parseAnnotatedMissingLineRanges(
          output: result.stdout, separator: "|")
      } else {
        missingLineRanges = []
      }

      let functions: [CoverageInspectionFunctionReport]
      if includeFunctions {
        let commandLine = renderedFunctionsCommandLine(
          llvmCovCommand: llvmCovCommand,
          profileDataPath: context.profileDataPath,
          testBinaryPath: context.testBinaryPath,
          filePath: filePath
        )
        let invocation = llvmCovInvocation(
          command: llvmCovCommand,
          arguments: [
            "report", "--show-functions", "-instr-profile", context.profileDataPath.path,
            context.testBinaryPath.path, filePath,
          ])
        let result = try processRunner.run(
          command: invocation.command,
          arguments: invocation.arguments,
          environment: [:],
          currentDirectory: nil,
          observation: nil
        )
        guard result.exitStatus == 0 else {
          throw SymphonyHarnessError(
            code: "swiftpm_coverage_inspection_failed",
            message: result.combinedOutput.isEmpty
              ? "Failed to inspect SwiftPM functions for \(candidate.path)." : result.combinedOutput
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
        functions = Self.parseLLVMCovFunctions(output: result.stdout)
      } else {
        functions = []
      }

      files.append(
        CoverageInspectionFileReport(
          targetName: candidate.targetName,
          path: fileURL.path.replacingOccurrences(of: resolvedRoot.path + "/", with: ""),
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

  func renderedShowCommandLine(
    llvmCovCommand: LLVMCovCommand, profileDataPath: URL, testBinaryPath: URL, filePath: String
  ) -> String {
    ShellQuoting.render(
      command: llvmCovInvocation(
        command: llvmCovCommand,
        arguments: ["show", "-instr-profile", profileDataPath.path, testBinaryPath.path, filePath]
      ).command,
      arguments: llvmCovInvocation(
        command: llvmCovCommand,
        arguments: ["show", "-instr-profile", profileDataPath.path, testBinaryPath.path, filePath]
      ).arguments
    )
  }

  func renderedFunctionsCommandLine(
    llvmCovCommand: LLVMCovCommand, profileDataPath: URL, testBinaryPath: URL, filePath: String
  ) -> String {
    ShellQuoting.render(
      command: llvmCovInvocation(
        command: llvmCovCommand,
        arguments: [
          "report", "--show-functions", "-instr-profile", profileDataPath.path, testBinaryPath.path,
          filePath,
        ]
      ).command,
      arguments: llvmCovInvocation(
        command: llvmCovCommand,
        arguments: [
          "report", "--show-functions", "-instr-profile", profileDataPath.path, testBinaryPath.path,
          filePath,
        ]
      ).arguments
    )
  }

  private func resolveFallbackTestBinary(debugRoot: URL) -> URL? {
    if let enumerator = fileManager.enumerator(
      at: debugRoot, includingPropertiesForKeys: [.isRegularFileKey])
    {
      for case let url as URL in enumerator {
        guard isRegularFile(at: url) else {
          continue
        }
        let path = url.path
        guard
          path.contains("PackageTests.xctest/Contents/MacOS/") && path.hasSuffix("PackageTests")
            || path.hasSuffix("PackageTests.xctest")
            || path.hasSuffix("PackageTests")
        else {
          continue
        }
        return url
      }
    }
    return nil
  }

  private func isRegularFile(at url: URL) -> Bool {
    var isDirectory = ObjCBool(false)
    guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
      return false
    }
    guard !isDirectory.boolValue else {
      return false
    }
    return (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? true
  }

  private func resolvedLLVMCovCommand() throws -> LLVMCovCommand {
    if let llvmCovCommand {
      return llvmCovCommand
    }
    guard
      let resolved = try ProcessToolchainCapabilitiesResolver(processRunner: processRunner)
        .resolve().llvmCovCommand
    else {
      throw SymphonyHarnessError(
        code: "missing_llvm_cov",
        message:
          "SwiftPM coverage inspection requires `llvm-cov`, either through `xcrun llvm-cov` or `llvm-cov` on PATH."
      )
    }
    return resolved
  }

  private func llvmCovInvocation(command: LLVMCovCommand, arguments: [String]) -> (
    command: String, arguments: [String]
  ) {
    switch command {
    case .xcrun:
      return ("xcrun", ["llvm-cov"] + arguments)
    case .direct:
      return ("llvm-cov", arguments)
    }
  }

  private func absolutePath(for path: String, projectRoot: URL) -> String {
    if path.hasPrefix("/") {
      return path
    }
    return projectRoot.appendingPathComponent(path).path
  }

  static func parseAnnotatedMissingLineRanges(output: String, separator: Character)
    -> [CoverageLineRange]
  {
    let missingLines = output.split(separator: "\n").compactMap { rawLine -> Int? in
      let line = String(rawLine)
      let pattern: String
      switch separator {
      case "|":
        pattern = #"^\s*(\d+)\|\s*(\d+)\|"#
      case ":":
        pattern = #"^\s*(\d+):\s*(\d+)\s*$"#
      default:
        return nil
      }

      guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
      let range = NSRange(line.startIndex..<line.endIndex, in: line)
      guard let match = regex.firstMatch(in: line, range: range),
        let lineRange = Range(match.range(at: 1), in: line),
        let countRange = Range(match.range(at: 2), in: line),
        let count = Int(line[countRange]),
        count == 0
      else {
        return nil
      }
      return Int(line[lineRange])
    }

    return collapsedRanges(for: missingLines)
  }

  static func parseLLVMCovFunctions(output: String) -> [CoverageInspectionFunctionReport] {
    let regex = try? NSRegularExpression(
      pattern:
        #"^\s*(.*?)\s+\d+\s+\d+\s+[0-9.]+%\s+(\d+)\s+(\d+)\s+([0-9.]+)%\s+\d+\s+\d+\s+[0-9.]+%\s*$"#
    )

    return
      output
      .split(separator: "\n")
      .compactMap { rawLine -> CoverageInspectionFunctionReport? in
        let line = String(rawLine)
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty,
          !line.hasPrefix("File "),
          !line.contains("Name"),
          !line.allSatisfy({ $0 == "-" || $0 == " " }),
          !line.trimmingCharacters(in: .whitespaces).hasPrefix("TOTAL"),
          let regex,
          let match = regex.firstMatch(
            in: line, range: NSRange(line.startIndex..<line.endIndex, in: line)),
          let nameRange = Range(match.range(at: 1), in: line),
          let executableRange = Range(match.range(at: 2), in: line),
          let missRange = Range(match.range(at: 3), in: line),
          let coverageRange = Range(match.range(at: 4), in: line),
          let executableLines = Int(line[executableRange]),
          let missLines = Int(line[missRange]),
          let lineCoverage = Double(line[coverageRange])
        else {
          return nil
        }

        let coveredLines = max(0, executableLines - missLines)
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

  static func collapsedRanges(for lines: [Int]) -> [CoverageLineRange] {
    let sortedLines = Array(Set(lines)).sorted()
    guard let first = sortedLines.first else {
      return []
    }

    var ranges = [CoverageLineRange]()
    var start = first
    var end = first
    for line in sortedLines.dropFirst() {
      if line == end + 1 {
        end = line
        continue
      }
      ranges.append(CoverageLineRange(startLine: start, endLine: end))
      start = line
      end = line
    }
    ranges.append(CoverageLineRange(startLine: start, endLine: end))
    return ranges
  }
}
