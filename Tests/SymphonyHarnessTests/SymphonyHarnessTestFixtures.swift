import Foundation
import Testing

@testable import SymphonyHarness

func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  try body(directory)
}

func withTemporaryRepositoryFixture(_ body: (URL) throws -> Void) throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(at: repoRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)
    try "# root package".write(
      to: repoRoot.appendingPathComponent("Package.swift"),
      atomically: true,
      encoding: .utf8
    )
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Symphony.xcworkspace"), withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("SymphonyApps.xcodeproj"),
      withIntermediateDirectories: true)
    try body(repoRoot)
  }
}

func makeToolForFixture(repoRoot: URL) -> SymphonyHarnessTool {
  let discovery = WorkspaceDiscovery(
    processRunner: StubProcessRunner(results: [
      "git rev-parse --show-toplevel": StubProcessRunner.success(repoRoot.path + "\n")
    ]))
  let simulators = StubSimulatorCatalog(
    devices: [
      SimulatorDevice(
        name: "iPhone 17", udid: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", state: "Shutdown",
        runtime: "iOS 18"),
      SimulatorDevice(
        name: "iPhone 17 Pro", udid: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB", state: "Shutdown",
        runtime: "iOS 18"),
      SimulatorDevice(
        name: "iPhone 17 Plus", udid: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC", state: "Shutdown",
        runtime: "iOS 18"),
    ]
  )
  return SymphonyHarnessTool(
    workspaceDiscovery: discovery,
    simulatorResolver: SimulatorResolver(catalog: simulators, processRunner: StubProcessRunner()),
    processRunner: StubProcessRunner()
  )
}

func currentRepositoryRoot() -> URL {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
}

func expectedHostMacOSDestination() -> String {
  #if arch(arm64)
    "platform=macOS,arch=arm64"
  #elseif arch(x86_64)
    "platform=macOS,arch=x86_64"
  #else
    "platform=macOS"
  #endif
}

final class HarnessInspectionProcessRunner: ProcessRunning, @unchecked Sendable {
  let packageCoveragePath: String
  let clientArtifactRoot: String
  let serverArtifactRoot: String
  let extraResults: [String: CommandResult]
  private let packageCoverageData: Data?

  init(
    packageCoveragePath: String, clientArtifactRoot: String, serverArtifactRoot: String,
    extraResults: [String: CommandResult]
  ) {
    self.packageCoveragePath = packageCoveragePath
    self.clientArtifactRoot = clientArtifactRoot
    self.serverArtifactRoot = serverArtifactRoot
    self.extraResults = extraResults
    self.packageCoverageData = try? Data(contentsOf: URL(fileURLWithPath: packageCoveragePath))
  }

  func run(
    command: String, arguments: [String], environment: [String: String], currentDirectory: URL?,
    observation: ProcessObservation?
  ) throws -> CommandResult {
    let rendered = ([command] + arguments).joined(separator: " ")
    if let result = extraResults[rendered] {
      return result
    }
    if command == "swift", arguments == ["test", "--enable-code-coverage"] {
      if let packageCoverageData,
        !FileManager.default.fileExists(atPath: packageCoveragePath)
      {
        let coverageURL = URL(fileURLWithPath: packageCoveragePath)
        try FileManager.default.createDirectory(
          at: coverageURL.deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
        try packageCoverageData.write(to: coverageURL)
      }
      return StubProcessRunner.success()
    }
    if command == "swift", arguments == ["test", "--show-code-coverage-path"] {
      return StubProcessRunner.success(packageCoveragePath + "\n")
    }
    if arguments.prefix(2) == ["test", "SymphonySwiftUIApp"] {
      return StubProcessRunner.success(clientArtifactRoot + "\n")
    }
    if arguments.prefix(2) == ["test", "SymphonyServer"] {
      return StubProcessRunner.success(serverArtifactRoot + "\n")
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
