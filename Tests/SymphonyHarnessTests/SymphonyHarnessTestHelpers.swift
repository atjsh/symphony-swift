import Foundation
import Testing

@testable import SymphonyHarness

struct StubProcessRunner: ProcessRunning {
  private final class Storage: @unchecked Sendable {
    var cachedCoverageExports = [String: Data]()
  }

  static let success = CommandResult(exitStatus: 0, stdout: "", stderr: "")

  var results: [String: CommandResult] = [:]
  private let storage = Storage()
  private let lock = NSLock()

  init(results: [String: CommandResult] = [:]) {
    self.results = results
  }

  func run(
    command: String, arguments: [String], environment: [String: String], currentDirectory: URL?,
    observation: ProcessObservation?, timeout: TimeInterval?
  ) throws -> CommandResult {
    let key = ([command] + arguments).joined(separator: " ")
    let result = results[key] ?? Self.success()

    if command == "swift", arguments == ["test", "--scratch-path", ".build/swiftpm-cache", "--show-code-coverage-path"] {
      cacheCoverageExportSeed(from: result)
    } else if command == "swift", arguments == ["test", "--scratch-path", ".build/swiftpm-cache", "--enable-code-coverage"] {
      try restoreCachedCoverageExportsIfNeeded()
    }

    return result
  }

  func startDetached(
    executablePath: String, arguments: [String], environment: [String: String],
    currentDirectory: URL?, output: URL
  ) throws -> Int32 {
    1234
  }

  static func failure(_ stderr: String) -> CommandResult {
    CommandResult(exitStatus: 1, stdout: "", stderr: stderr)
  }

  static func success(_ stdout: String = "") -> CommandResult {
    CommandResult(exitStatus: 0, stdout: stdout, stderr: "")
  }

  private func cacheCoverageExportSeed(from result: CommandResult) {
    guard result.exitStatus == 0 else {
      return
    }

    let rawPath = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !rawPath.isEmpty else {
      return
    }

    let coverageURL = URL(fileURLWithPath: rawPath)
    guard let data = try? Data(contentsOf: coverageURL) else {
      return
    }

    lock.lock()
    storage.cachedCoverageExports[coverageURL.path] = data
    lock.unlock()
  }

  private func restoreCachedCoverageExportsIfNeeded() throws {
    lock.lock()
    let cachedCoverageExports = storage.cachedCoverageExports
    lock.unlock()

    for (path, data) in cachedCoverageExports {
      let coverageURL = URL(fileURLWithPath: path)
      guard !FileManager.default.fileExists(atPath: coverageURL.path) else {
        continue
      }

      try FileManager.default.createDirectory(
        at: coverageURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try data.write(to: coverageURL)
    }
  }
}

final class StalePackageCoverageProcessRunner: ProcessRunning, @unchecked Sendable {
  private let lock = NSLock()
  private let repoRoot: URL
  private let coveragePath: URL
  private var staleCoverageBeforeSwiftTestRun: Bool?

  init(repoRoot: URL, coveragePath: URL) {
    self.repoRoot = repoRoot
    self.coveragePath = coveragePath
  }

  func run(
    command: String, arguments: [String], environment: [String: String], currentDirectory: URL?,
    observation: ProcessObservation?, timeout: TimeInterval?
  ) throws -> CommandResult {
    if command == "swift", arguments == ["test", "--scratch-path", ".build/swiftpm-cache", "--show-code-coverage-path"] {
      return StubProcessRunner.success(coveragePath.path + "\n")
    }

    if command == "swift", arguments == ["test", "--scratch-path", ".build/swiftpm-cache", "--enable-code-coverage"] {
      lock.lock()
      staleCoverageBeforeSwiftTestRun = FileManager.default.fileExists(atPath: coveragePath.path)
      lock.unlock()

      try #"""
      {
        "data": [
          {
            "files": [
              {
                "filename": "__REPO__/Sources/Foo.swift",
                "summary": { "lines": { "count": 100, "covered": 100 } }
              }
            ]
          }
        ]
      }
      """#
      .replacingOccurrences(of: "__REPO__", with: repoRoot.path)
      .write(to: coveragePath, atomically: true, encoding: .utf8)
      return StubProcessRunner.success("tests passed\n")
    }

    return StubProcessRunner.success()
  }

  func startDetached(
    executablePath: String, arguments: [String], environment: [String: String],
    currentDirectory: URL?, output: URL
  ) throws -> Int32 {
    1234
  }

  var sawStaleCoverageBeforeSwiftTestRun: Bool? {
    lock.lock()
    defer { lock.unlock() }
    return staleCoverageBeforeSwiftTestRun
  }
}

final class RecordingProcessRunner: ProcessRunning, @unchecked Sendable {
  private let lock = NSLock()
  private var storage = [String]()

  func run(
    command: String, arguments: [String], environment: [String: String], currentDirectory: URL?,
    observation: ProcessObservation?, timeout: TimeInterval?
  ) throws -> CommandResult {
    lock.lock()
    storage.append(([command] + arguments).joined(separator: " "))
    lock.unlock()
    return StubProcessRunner.success()
  }

  func startDetached(
    executablePath: String, arguments: [String], environment: [String: String],
    currentDirectory: URL?, output: URL
  ) throws -> Int32 {
    1234
  }

  var commands: [String] {
    lock.lock()
    defer { lock.unlock() }
    return storage
  }
}

final class GoEnryMaterializationProcessRunner: ProcessRunning, @unchecked Sendable {
  private let lock = NSLock()
  private var storage = [String]()
  private var goBuildArchitecturesStorage = [String]()
  private var lipoOutputPathStorage: String?
  private var lipoInputPathsStorage = [String]()
  private let results: [String: CommandResult]

  init(results: [String: CommandResult]) {
    self.results = results
  }

  func run(
    command: String,
    arguments: [String],
    environment: [String: String],
    currentDirectory: URL?,
    observation: ProcessObservation?, timeout: TimeInterval?
  ) throws -> CommandResult {
    _ = environment
    _ = currentDirectory
    _ = observation

    let key = ([command] + arguments).joined(separator: " ")
    lock.lock()
    storage.append(key)
    lock.unlock()

    if command == "go",
      arguments.count == 5,
      arguments[0] == "build",
      arguments[1] == "-buildmode=c-archive"
    {
      guard
        let outputIndex = arguments.firstIndex(of: "-o"),
        arguments.indices.contains(outputIndex + 1),
        let goArch = environment["GOARCH"]
      else {
        Issue.record("Expected go build invocation to provide GOARCH and -o output path.")
        return StubProcessRunner.failure("malformed go build invocation")
      }

      let archivePath = URL(fileURLWithPath: arguments[outputIndex + 1])
      let headerPath = archivePath.deletingPathExtension().appendingPathExtension("h")
      try FileManager.default.createDirectory(
        at: archivePath.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try Data("archive-\(goArch)".utf8).write(to: archivePath)
      try "header-\(goArch)".write(to: headerPath, atomically: true, encoding: .utf8)

      lock.lock()
      goBuildArchitecturesStorage.append(goArch)
      lock.unlock()
      return StubProcessRunner.success()
    }

    if command == "/usr/bin/env",
      arguments.count >= 5,
      arguments[0] == "lipo",
      arguments[1] == "-create",
      let outputIndex = arguments.firstIndex(of: "-output"),
      arguments.indices.contains(outputIndex + 1)
    {
      let outputPath = arguments[outputIndex + 1]
      let inputPaths = Array(arguments[2..<outputIndex])
      let outputURL = URL(fileURLWithPath: outputPath)
      try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try Data("universal-archive".utf8).write(to: outputURL)

      lock.lock()
      lipoOutputPathStorage = outputPath
      lipoInputPathsStorage = inputPaths
      lock.unlock()
      return StubProcessRunner.success()
    }

    return results[key] ?? StubProcessRunner.success()
  }

  func startDetached(
    executablePath: String,
    arguments: [String],
    environment: [String: String],
    currentDirectory: URL?,
    output: URL
  ) throws -> Int32 {
    _ = executablePath
    _ = arguments
    _ = environment
    _ = currentDirectory
    _ = output
    return 1234
  }

  var commands: [String] {
    lock.lock()
    defer { lock.unlock() }
    return storage
  }

  var goBuildArchitectures: [String] {
    lock.lock()
    defer { lock.unlock() }
    return goBuildArchitecturesStorage
  }

  var lipoOutputPath: String? {
    lock.lock()
    defer { lock.unlock() }
    return lipoOutputPathStorage
  }

  var lipoInputPaths: [String] {
    lock.lock()
    defer { lock.unlock() }
    return lipoInputPathsStorage
  }
}

final class SignalBox: @unchecked Sendable {
  private let lock = NSLock()
  private var storage = [String]()

  func append(_ value: String) {
    lock.lock()
    storage.append(value)
    lock.unlock()
  }

  var values: [String] {
    lock.lock()
    defer { lock.unlock() }
    return storage
  }
}

struct StubSimulatorCatalog: SimulatorCataloging {
  let devices: [SimulatorDevice]

  func availableDevices() throws -> [SimulatorDevice] {
    devices
  }
}

struct StubWorkspaceDiscovery: WorkspaceDiscovering {
  let workspace: WorkspaceContext

  func discover(from startDirectory: URL) throws -> WorkspaceContext {
    workspace
  }
}

struct StubDoctorService: DoctorServicing {
  let report: DiagnosticsReport
  let rendered: String

  func makeReport(from request: DoctorCommandRequest) throws -> DiagnosticsReport {
    report
  }

  func render(report: DiagnosticsReport, json: Bool, quiet: Bool) throws -> String {
    rendered
  }
}

struct StubToolchainCapabilitiesResolver: ToolchainCapabilitiesResolving {
  let capabilities: ToolchainCapabilities

  func resolve() throws -> ToolchainCapabilities {
    capabilities
  }
}

extension ToolchainCapabilities {
  static let fullyAvailableForTests = ToolchainCapabilities(
    swiftAvailable: true,
    xcodebuildAvailable: true,
    xcrunAvailable: true,
    simctlAvailable: true,
    xcresulttoolAvailable: true,
    llvmCovCommand: .xcrun
  )

  static let noXcodeForTests = ToolchainCapabilities(
    swiftAvailable: true,
    xcodebuildAvailable: false,
    xcrunAvailable: false,
    simctlAvailable: false,
    xcresulttoolAvailable: false,
    llvmCovCommand: .direct
  )
}
