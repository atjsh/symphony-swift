import Foundation
import GoEnryBridge
import SymphonyServerCore
import SymphonyShared

// MARK: - Repository Syntax Health

public protocol RepositorySyntaxHealthRunning: Sendable {
  func syntaxHealth(in workspacePath: String, syntaxConfig: AnalysisSyntaxConfig)
    -> RepositorySyntaxHealth
}

public struct ProcessRepositorySyntaxHealthRunner: RepositorySyntaxHealthRunning {
  public init() {}

  public func syntaxHealth(in workspacePath: String, syntaxConfig: AnalysisSyntaxConfig)
    -> RepositorySyntaxHealth
  {
    guard let command = syntaxConfig.command?.trimmingCharacters(in: .whitespacesAndNewlines),
      !command.isEmpty
    else {
      return RepositorySyntaxHealth(status: .unsupported, checkedFileCount: 0, diagnosticCount: 0)
    }

    do {
      let output = try ProcessShellCommandRunner().run(command: command, in: workspacePath)
      let payload = try JSONDecoder().decode(SyntaxHealthPayload.self, from: Data(output.utf8))
      return RepositorySyntaxHealth(
        status: .configured,
        checkedFileCount: payload.checkedFileCount,
        diagnosticCount: payload.diagnosticCount,
        diagnostics: payload.diagnostics.map {
          RepositorySyntaxDiagnostic(
            path: $0.path,
            message: $0.message,
            severity: $0.severity,
            line: $0.line,
            column: $0.column
          )
        }
      )
    } catch {
      return RepositorySyntaxHealth(
        status: .failed,
        checkedFileCount: 0,
        diagnosticCount: 0,
        failureMessage: String(describing: error)
      )
    }
  }
}

private struct SyntaxHealthPayload: Decodable, Sendable {
  let checkedFileCount: Int
  let diagnosticCount: Int
  let diagnostics: [SyntaxHealthDiagnosticPayload]

  private enum CodingKeys: String, CodingKey {
    case checkedFileCount = "checked_file_count"
    case diagnosticCount = "diagnostic_count"
    case diagnostics
  }
}

private struct SyntaxHealthDiagnosticPayload: Decodable, Sendable {
  let path: String
  let message: String
  let severity: String
  let line: Int?
  let column: Int?
}

// MARK: - Git Command Running

public protocol GitCommandRunning: Sendable {
  func run(in workspacePath: String, arguments: [String]) throws -> Data
  func loadBlobMetrics(in workspacePath: String, blobIDs: [String]) throws -> [String: BlobMetrics]
}

public struct ProcessGitCommandRunner: GitCommandRunning {
  public init() {}

  public func run(in workspacePath: String, arguments: [String]) throws -> Data {
    try ProcessRunner.run(
      executable: "/usr/bin/env",
      arguments: ["git", "-C", workspacePath] + arguments
    )
  }

  public func loadBlobMetrics(in workspacePath: String, blobIDs: [String]) throws -> [String: BlobMetrics] {
    guard !blobIDs.isEmpty else {
      return [:]
    }

    let input = blobIDs.joined(separator: "\n") + "\n"
    let data = try ProcessRunner.run(
      executable: "/usr/bin/env",
      arguments: ["git", "-C", workspacePath, "cat-file", "--batch"],
      standardInput: Data(input.utf8)
    )

    var offset = data.startIndex
    var results = [String: BlobMetrics]()
    while offset < data.endIndex {
      guard let headerEnd = data[offset...].firstIndex(of: 10) else {
        break
      }
      let header = String(decoding: data[offset..<headerEnd], as: UTF8.self)
      let headerFields = header.split(separator: " ", omittingEmptySubsequences: true)
      guard headerFields.count == 3 else {
        break
      }
      let blobID = String(headerFields[0])
      let size = Int(headerFields[2]) ?? 0
      let contentStart = data.index(after: headerEnd)
      let contentEnd = data.index(contentStart, offsetBy: size, limitedBy: data.endIndex) ?? data.endIndex
      let content = Data(data[contentStart..<contentEnd])
      results[blobID] = BlobMetrics.make(from: content)

      offset = contentEnd
      if offset < data.endIndex, data[offset] == 10 {
        offset = data.index(after: offset)
      }
    }

    return results
  }
}

extension GitCommandRunning {
  func runString(in workspacePath: String, arguments: [String]) throws -> String {
    String(decoding: try run(in: workspacePath, arguments: arguments), as: UTF8.self)
  }
}

// MARK: - Repository Language Detection

public protocol RepositoryLanguageDetecting: Sendable {
  var version: String { get }
  func isBinary(content: Data) throws -> Bool
  func isConfiguration(path: String) throws -> Bool
  func isDocumentation(path: String) throws -> Bool
  func isDotFile(path: String) throws -> Bool
  func isImage(path: String) throws -> Bool
  func isVendor(path: String) throws -> Bool
  func isGenerated(path: String, content: Data) throws -> Bool
  func isTest(path: String) throws -> Bool
  func language(path: String, content: Data) throws -> String?
  func languageType(language: String) throws -> String?
}

// MARK: - Repository File Classification

public protocol RepositoryFileClassifying: Sendable {
  var version: String { get }
  func classify(path: String, content: Data, historyConfig: AnalysisHistoryConfig) throws
    -> RepositoryFileCategory
}

public struct RepositoryFileClassifier: RepositoryFileClassifying {
  public let detector: any RepositoryLanguageDetecting

  public init(detector: any RepositoryLanguageDetecting) {
    self.detector = detector
  }

  public var version: String {
    detector.version
  }

  public func classify(path: String, content: Data, historyConfig: AnalysisHistoryConfig) throws
    -> RepositoryFileCategory
  {
    if Self.matches(path: path, globs: historyConfig.testPaths) {
      return .test
    }
    if Self.matches(path: path, globs: historyConfig.sourcePaths) {
      return .source
    }
    if try detector.isBinary(content: content)
      || detector.isVendor(path: path)
      || detector.isConfiguration(path: path)
      || detector.isDocumentation(path: path)
      || detector.isDotFile(path: path)
      || detector.isImage(path: path)
      || detector.isGenerated(path: path, content: content)
    {
      return .other
    }
    if try detector.isTest(path: path) || Self.isFallbackTestPath(path) {
      return .test
    }
    guard let language = try detector.language(path: path, content: content),
      !language.isEmpty,
      let languageType = try detector.languageType(language: language)
    else {
      return .other
    }
    switch languageType.lowercased() {
    case "programming", "markup":
      return .source
    default:
      return .other
    }
  }

  private static func matches(path: String, globs: [String]) -> Bool {
    globs.contains { GlobPattern($0).matches(path: path) }
  }

  private static func isFallbackTestPath(_ path: String) -> Bool {
    let lowercased = path.lowercased()
    return lowercased.hasPrefix("test_")
      || lowercased.contains(".test.")
      || lowercased.contains(".spec.")
      || lowercased.contains("_test.")
      || lowercased.contains("_tests.")
  }
}

// MARK: - Go-Enry Language Detector

public struct GoEnryRepositoryLanguageDetector: RepositoryLanguageDetecting {
  private let detector: GoEnryLanguageDetector

  public init(detector: GoEnryLanguageDetector = GoEnryLanguageDetector()) {
    self.detector = detector
  }

  public var version: String {
    detector.version
  }

  public func isBinary(content: Data) throws -> Bool {
    detector.isBinary(content: content)
  }

  public func isConfiguration(path: String) throws -> Bool {
    detector.isConfiguration(path: path)
  }

  public func isDocumentation(path: String) throws -> Bool {
    detector.isDocumentation(path: path)
  }

  public func isDotFile(path: String) throws -> Bool {
    detector.isDotFile(path: path)
  }

  public func isImage(path: String) throws -> Bool {
    detector.isImage(path: path)
  }

  public func isVendor(path: String) throws -> Bool {
    detector.isVendor(path: path)
  }

  public func isGenerated(path: String, content: Data) throws -> Bool {
    detector.isGenerated(path: path, content: content)
  }

  public func isTest(path: String) throws -> Bool {
    detector.isTest(path: path)
  }

  public func language(path: String, content: Data) throws -> String? {
    detector.language(path: path, content: content)
  }

  public func languageType(language: String) throws -> String? {
    detector.languageType(language: language)
  }
}

// MARK: - Unavailable Language Detector

public struct UnavailableRepositoryLanguageDetector: RepositoryLanguageDetecting {
  public init() {}

  public var version: String {
    "unavailable"
  }

  public func isBinary(content: Data) throws -> Bool {
    throw IssueProgressReportError.repositoryHistoryUnavailable(
      "go-enry is not materialized. Run `just materialize-go-enry` before requesting progress reports."
    )
  }

  public func isConfiguration(path: String) throws -> Bool { false }
  public func isDocumentation(path: String) throws -> Bool { false }
  public func isDotFile(path: String) throws -> Bool { false }
  public func isImage(path: String) throws -> Bool { false }
  public func isVendor(path: String) throws -> Bool { false }
  public func isGenerated(path: String, content: Data) throws -> Bool { false }
  public func isTest(path: String) throws -> Bool { false }
  public func language(path: String, content: Data) throws -> String? { nil }
  public func languageType(language: String) throws -> String? { nil }
}

// MARK: - Process Runners

public struct ProcessShellCommandRunner: Sendable {
  public init() {}

  public func run(command: String, in workspacePath: String) throws -> String {
    let data = try ProcessRunner.run(
      executable: "/bin/bash",
      arguments: ["-lc", command],
      currentDirectoryPath: workspacePath
    )
    return String(decoding: data, as: UTF8.self)
  }
}

enum ProcessRunner {
  static func run(
    executable: String,
    arguments: [String],
    currentDirectoryPath: String? = nil,
    standardInput: Data? = nil
  ) throws -> Data {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    if let currentDirectoryPath {
      process.currentDirectoryURL = URL(fileURLWithPath: currentDirectoryPath)
    }

    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    if let standardInput {
      let inputPipe = Pipe()
      process.standardInput = inputPipe
      try process.run()
      inputPipe.fileHandleForWriting.write(standardInput)
      try inputPipe.fileHandleForWriting.close()
    } else {
      try process.run()
    }

    process.waitUntilExit()
    let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
    guard process.terminationStatus == 0 else {
      let errorOutput = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
      throw IssueProgressReportError.repositoryHistoryUnavailable(
        errorOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          ? "\(executable) \(arguments.joined(separator: " ")) failed."
          : errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
      )
    }
    return output
  }
}

// MARK: - Glob Pattern

private struct GlobPattern {
  private let regex: NSRegularExpression?

  init(_ pattern: String) {
    self.regex = try? NSRegularExpression(pattern: Self.regexPattern(for: pattern))
  }

  func matches(path: String) -> Bool {
    guard let regex else {
      return false
    }
    let range = NSRange(path.startIndex..<path.endIndex, in: path)
    return regex.firstMatch(in: path, range: range) != nil
  }

  private static func regexPattern(for pattern: String) -> String {
    var result = "^"
    var index = pattern.startIndex
    while index < pattern.endIndex {
      let character = pattern[index]
      if character == "*" {
        let nextIndex = pattern.index(after: index)
        if nextIndex < pattern.endIndex, pattern[nextIndex] == "*" {
          result += ".*"
          index = pattern.index(after: nextIndex)
        } else {
          result += "[^/]*"
          index = nextIndex
        }
        continue
      }
      if character == "?" {
        result += "[^/]"
      } else {
        result += NSRegularExpression.escapedPattern(for: String(character))
      }
      index = pattern.index(after: index)
    }
    result += "$"
    return result
  }
}
