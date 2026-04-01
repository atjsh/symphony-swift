import Foundation
import Testing

@testable import SymphonyHarness

struct CoverageCommandProcessRunner: ProcessRunning {
  let packageCoveragePath: String
  let coverageResult: CommandResult
  private let packageCoverageData: Data?

  init(packageCoveragePath: String, coverageResult: CommandResult) {
    self.packageCoveragePath = packageCoveragePath
    self.coverageResult = coverageResult
    self.packageCoverageData = capturePackageCoverageSeed(at: packageCoveragePath)
  }

  func run(
    command: String, arguments: [String], environment: [String: String], currentDirectory: URL?,
    observation: ProcessObservation?
  ) throws -> CommandResult {
    if command == "swift", arguments == ["test", "--enable-code-coverage"] {
      try restorePackageCoverageSeed(
        packageCoverageData,
        at: packageCoveragePath
      )
      observation?.onLine?(.stdout, "swift test passed")
      observation?.onStaleSignal?("[harness] swift test still running")
      return StubProcessRunner.success()
    }
    if command == "swift", arguments == ["test", "--show-code-coverage-path"] {
      return StubProcessRunner.success(packageCoveragePath + "\n")
    }
    if arguments.prefix(2) == ["test", "SymphonySwiftUIApp"]
      || arguments.prefix(2) == ["test", "SymphonyServer"]
    {
      observation?.onLine?(.stderr, "coverage stderr")
      return coverageResult
    }
    return StubProcessRunner.success()
  }

  func startDetached(
    executablePath: String, arguments: [String], environment: [String: String],
    currentDirectory: URL?, output: URL
  ) throws -> Int32 {
    0
  }
}

final class PackageInspectionOverwriteProcessRunner: ProcessRunning, @unchecked Sendable {
  private let packageCoveragePath: String
  private let packageCoverageData: Data?
  private let showArguments: [String]
  private let reportArguments: [String]
  private let lock = NSLock()
  private var artifactsWereRewritten = false

  init(
    packageCoveragePath: String,
    sourceFilePath: String,
    profdataPath: String,
    testBinaryPath: String
  ) {
    self.packageCoveragePath = packageCoveragePath
    self.packageCoverageData = capturePackageCoverageSeed(at: packageCoveragePath)
    self.showArguments = [
      "llvm-cov", "show",
      "-instr-profile", profdataPath,
      testBinaryPath,
      sourceFilePath,
    ]
    self.reportArguments = [
      "llvm-cov", "report",
      "--show-functions",
      "-instr-profile", profdataPath,
      testBinaryPath,
      sourceFilePath,
    ]
  }

  func markArtifactsRewritten() {
    lock.lock()
    artifactsWereRewritten = true
    lock.unlock()
  }

  func run(
    command: String, arguments: [String], environment: [String: String], currentDirectory: URL?,
    observation: ProcessObservation?
  ) throws -> CommandResult {
    if command == "swift", arguments == ["test", "--enable-code-coverage"] {
      try restorePackageCoverageSeed(packageCoverageData, at: packageCoveragePath)
      return StubProcessRunner.success()
    }
    if command == "swift", arguments == ["test", "--show-code-coverage-path"] {
      return StubProcessRunner.success(packageCoveragePath + "\n")
    }
    if command == "xcrun", arguments == showArguments {
      return StubProcessRunner.success(
        artifactsWereRewritten
          ? """
            1|      0|func bar() {
            2|      0|    overwritten()
            3|      0|    overwrittenAgain()
            4|      0|}
          """
          : """
            1|      1|func bar() {
            2|      0|    initial()
            3|      0|    initialAgain()
            4|      1|}
          """
      )
    }
    if command == "xcrun", arguments == reportArguments {
      return StubProcessRunner.success(
        artifactsWereRewritten
          ? """
          File '':
          Name                                     Regions    Miss   Cover     Lines    Miss   Cover  Branches    Miss   Cover
          --------------------------------------------------------------------------------------------------------------------------------
          overwritten()                               2       2   0.00%         4       4   0.00%         0       0   0.00%
          --------------------------------------------------------------------------------------------------------------------------------
          TOTAL                                        2       2   0.00%         4       4   0.00%         0       0   0.00%
          """
          : """
          File '':
          Name                                     Regions    Miss   Cover     Lines    Miss   Cover  Branches    Miss   Cover
          --------------------------------------------------------------------------------------------------------------------------------
          initial()                                   2       1  50.00%         4       2  50.00%         0       0   0.00%
          --------------------------------------------------------------------------------------------------------------------------------
          TOTAL                                        2       1  50.00%         4       2  50.00%         0       0   0.00%
          """
      )
    }
    return StubProcessRunner.success()
  }

  func startDetached(
    executablePath: String, arguments: [String], environment: [String: String],
    currentDirectory: URL?, output: URL
  ) throws -> Int32 {
    0
  }
}

final class HarnessOutputControlProcessRunner: ProcessRunning, @unchecked Sendable {
  let packageCoveragePath: String
  let artifactRoot: String
  private let packageCoverageData: Data?
  private let lock = NSLock()
  private var storage = [String]()

  init(packageCoveragePath: String, artifactRoot: String) {
    self.packageCoveragePath = packageCoveragePath
    self.artifactRoot = artifactRoot
    self.packageCoverageData = capturePackageCoverageSeed(at: packageCoveragePath)
  }

  var commands: [String] {
    lock.lock()
    defer { lock.unlock() }
    return storage
  }

  func run(
    command: String, arguments: [String], environment: [String: String], currentDirectory: URL?,
    observation: ProcessObservation?
  ) throws -> CommandResult {
    let rendered = ([command] + arguments).joined(separator: " ")
    lock.lock()
    storage.append(rendered)
    lock.unlock()

    if command == "swift", arguments == ["test", "--enable-code-coverage"] {
      try restorePackageCoverageSeed(packageCoverageData, at: packageCoveragePath)
      observation?.onLine?(.stdout, "Compiling NIOCore AsyncChannel.swift")
      observation?.onLine?(.stderr, "warning: important harness warning")
      return StubProcessRunner.success()
    }
    if command == "swift", arguments == ["test", "--show-code-coverage-path"] {
      return StubProcessRunner.success(packageCoveragePath + "\n")
    }
    if arguments.prefix(2) == ["test", "SymphonySwiftUIApp"]
      || arguments.prefix(2) == ["test", "SymphonyServer"]
    {
      return StubProcessRunner.success(artifactRoot + "\n")
    }
    return StubProcessRunner.success()
  }

  func startDetached(
    executablePath: String, arguments: [String], environment: [String: String],
    currentDirectory: URL?, output: URL
  ) throws -> Int32 {
    0
  }
}

final class ProtocolExtensionRunner: ProcessRunning, @unchecked Sendable {
  private(set) var lastObservationWasNil = false

  func run(
    command: String, arguments: [String], environment: [String: String], currentDirectory: URL?,
    observation: ProcessObservation?
  ) throws -> CommandResult {
    lastObservationWasNil = observation == nil
    return StubProcessRunner.success()
  }

  func startDetached(
    executablePath: String, arguments: [String], environment: [String: String],
    currentDirectory: URL?, output: URL
  ) throws -> Int32 {
    0
  }
}

struct ObservationCoverageRunner: ProcessRunning {
  let stdout: String
  let observe: @Sendable (ProcessObservation?) -> Void

  func run(
    command: String, arguments: [String], environment: [String: String], currentDirectory: URL?,
    observation: ProcessObservation?
  ) throws -> CommandResult {
    observe(observation)
    return StubProcessRunner.success(stdout)
  }

  func startDetached(
    executablePath: String, arguments: [String], environment: [String: String],
    currentDirectory: URL?, output: URL
  ) throws -> Int32 {
    0
  }
}

struct DualCoverageProcessRunner: ProcessRunning {
  let packageCoveragePath: String
  let artifactRoot: String
  private let packageCoverageData: Data?

  init(packageCoveragePath: String, artifactRoot: String) {
    self.packageCoveragePath = packageCoveragePath
    self.artifactRoot = artifactRoot
    self.packageCoverageData = capturePackageCoverageSeed(at: packageCoveragePath)
  }

  func run(
    command: String, arguments: [String], environment: [String: String], currentDirectory: URL?,
    observation: ProcessObservation?
  ) throws -> CommandResult {
    if command == "swift", arguments == ["test", "--enable-code-coverage"] {
      try restorePackageCoverageSeed(packageCoverageData, at: packageCoveragePath)
      return StubProcessRunner.success()
    }
    if command == "swift", arguments == ["test", "--show-code-coverage-path"] {
      return StubProcessRunner.success(packageCoveragePath + "\n")
    }
    if arguments.prefix(2) == ["test", "SymphonySwiftUIApp"]
      || arguments.prefix(2) == ["test", "SymphonyServer"]
    {
      return StubProcessRunner.success(artifactRoot + "\n")
    }
    return StubProcessRunner.success()
  }

  func startDetached(
    executablePath: String, arguments: [String], environment: [String: String],
    currentDirectory: URL?, output: URL
  ) throws -> Int32 {
    0
  }
}

struct ArtifactPathProcessRunner: ProcessRunning {
  let packageCoveragePath: String
  let artifactRoot: String
  private let packageCoverageData: Data?

  init(packageCoveragePath: String, artifactRoot: String) {
    self.packageCoveragePath = packageCoveragePath
    self.artifactRoot = artifactRoot
    self.packageCoverageData = capturePackageCoverageSeed(at: packageCoveragePath)
  }

  func run(
    command: String, arguments: [String], environment: [String: String], currentDirectory: URL?,
    observation: ProcessObservation?
  ) throws -> CommandResult {
    if command == "swift", arguments == ["test", "--enable-code-coverage"] {
      try restorePackageCoverageSeed(packageCoverageData, at: packageCoveragePath)
      return StubProcessRunner.success()
    }
    if command == "swift", arguments == ["test", "--show-code-coverage-path"] {
      return StubProcessRunner.success(packageCoveragePath + "\n")
    }
    if arguments.prefix(2) == ["test", "SymphonySwiftUIApp"]
      || arguments.prefix(2) == ["test", "SymphonyServer"]
    {
      return StubProcessRunner.success(artifactRoot + "\n")
    }
    return StubProcessRunner.success()
  }

  func startDetached(
    executablePath: String, arguments: [String], environment: [String: String],
    currentDirectory: URL?, output: URL
  ) throws -> Int32 {
    0
  }
}

private func capturePackageCoverageSeed(at path: String) -> Data? {
  try? Data(contentsOf: URL(fileURLWithPath: path))
}

private func restorePackageCoverageSeed(_ data: Data?, at path: String) throws {
  guard let data else {
    return
  }

  let coverageURL = URL(fileURLWithPath: path)
  guard !FileManager.default.fileExists(atPath: coverageURL.path) else {
    return
  }

  try FileManager.default.createDirectory(
    at: coverageURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )
  try data.write(to: coverageURL)
}
