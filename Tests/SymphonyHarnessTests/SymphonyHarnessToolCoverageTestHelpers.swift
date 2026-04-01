import Foundation
import Testing

@testable import SymphonyHarness

struct DecodedSharedRunIndex: Decodable {
  let anomalies: [ArtifactAnomaly]
}

struct ThrowingDoctorService: DoctorServicing {
  let error: Error

  func makeReport(from request: DoctorCommandRequest) throws -> DiagnosticsReport {
    _ = request
    throw error
  }

  func render(report: DiagnosticsReport, json: Bool, quiet: Bool) throws -> String {
    _ = report
    _ = json
    _ = quiet
    return "unreachable"
  }
}


final class RoutedProcessRunner: ProcessRunning, @unchecked Sendable {
  private let handler:
    @Sendable (String, [String], [String: String], URL?, ProcessObservation?) throws ->
      CommandResult
  private let lock = NSLock()
  private(set) var startedDetachedExecutions = [
    (executablePath: String, environment: [String: String], output: URL)
  ]()

  init(
    handler:
      @escaping @Sendable (String, [String], [String: String], URL?, ProcessObservation?) throws ->
      CommandResult
  ) {
    self.handler = handler
  }

  func run(
    command: String, arguments: [String], environment: [String: String], currentDirectory: URL?,
    observation: ProcessObservation?
  ) throws -> CommandResult {
    try handler(command, arguments, environment, currentDirectory, observation)
  }

  func startDetached(
    executablePath: String, arguments: [String], environment: [String: String],
    currentDirectory: URL?, output: URL
  ) throws -> Int32 {
    lock.lock()
    startedDetachedExecutions.append((executablePath, environment, output))
    lock.unlock()
    return 4242
  }
}

final class InvocationCounterBox: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0

  func increment() -> Int {
    lock.lock()
    value += 1
    let currentValue = value
    lock.unlock()
    return currentValue
  }
}

final class StringIntBox: @unchecked Sendable {
  private let lock = NSLock()
  private var values = [String: Int]()

  func increment(for key: String) -> Int {
    lock.lock()
    values[key, default: 0] += 1
    let currentValue = values[key, default: 0]
    lock.unlock()
    return currentValue
  }

  func value(for key: String) -> Int? {
    lock.lock()
    let currentValue = values[key]
    lock.unlock()
    return currentValue
  }
}

final class InvocationConcurrencyBox: @unchecked Sendable {
  private let lock = NSLock()
  private let readySemaphore = DispatchSemaphore(value: 0)
  private var activeInvocations = 0
  private var startedInvocations = 0
  private(set) var maxConcurrentInvocations = 0

  func enter() {
    lock.lock()
    activeInvocations += 1
    maxConcurrentInvocations = max(maxConcurrentInvocations, activeInvocations)
    lock.unlock()
  }

  func enterSynchronizingUntilStarted(expectedCount: Int) {
    lock.lock()
    activeInvocations += 1
    startedInvocations += 1
    maxConcurrentInvocations = max(maxConcurrentInvocations, activeInvocations)
    let started = startedInvocations
    if started == expectedCount {
      for _ in 1..<expectedCount {
        readySemaphore.signal()
      }
    }
    lock.unlock()

    if started < expectedCount {
      _ = readySemaphore.wait(timeout: .now() + 0.2)
    }
  }

  func leave() {
    lock.lock()
    activeInvocations -= 1
    lock.unlock()
  }
}

final class RecordingWorkspaceDiscovery: WorkspaceDiscovering, @unchecked Sendable {
  private let lock = NSLock()
  private(set) var discoveredFrom = [URL]()
  let workspace: WorkspaceContext

  init(workspace: WorkspaceContext) {
    self.workspace = workspace
  }

  func discover(from startDirectory: URL) throws -> WorkspaceContext {
    lock.lock()
    discoveredFrom.append(startDirectory)
    lock.unlock()
    return workspace
  }
}

final class HarnessPackageInspectionOverwriteProcessRunner: ProcessRunning,
  @unchecked Sendable
{
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
    self.packageCoverageData = try? Data(contentsOf: URL(fileURLWithPath: packageCoveragePath))
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

func loadCoverageReport(fromSharedSummaryPath summaryPath: String, subject: String) throws
  -> CoverageReport
{
  let coverageURL = URL(fileURLWithPath: summaryPath)
    .deletingLastPathComponent()
    .appendingPathComponent("subjects/\(subject)/coverage.json")
  return try JSONDecoder().decode(CoverageReport.self, from: Data(contentsOf: coverageURL))
}

func makeCoverageTool(
  workspace: WorkspaceContext, runner: RoutedProcessRunner,
  statusSink: @escaping @Sendable (String) -> Void
) -> SymphonyHarnessTool {
  SymphonyHarnessTool(
    workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
    executionContextBuilder: ExecutionContextBuilder(),
    simulatorResolver: SimulatorResolver(
      catalog: StubSimulatorCatalog(devices: []), processRunner: runner),
    processRunner: runner,
    artifactManager: ArtifactManager(processRunner: runner),
    endpointOverrideStore: EndpointOverrideStore(),
    doctorService: StubDoctorService(
      report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []),
      rendered: "ok"),
    toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(
      capabilities: .fullyAvailableForTests),
    productLocator: ProductLocator(processRunner: runner),
    commitHarness: CommitHarness(
      processRunner: runner,
      clientCoverageLoader: { _ in
        CoverageReport(
          coveredLines: 1, executableLines: 1, lineCoverage: 1, includeTestTargets: false,
          excludedTargets: [], targets: [])
      },
      serverCoverageLoader: { _ in
        CoverageReport(
          coveredLines: 1, executableLines: 1, lineCoverage: 1, includeTestTargets: false,
          excludedTargets: [], targets: [])
      }),
    gitHookInstaller: GitHookInstaller(processRunner: runner),
    statusSink: statusSink
  )
}
