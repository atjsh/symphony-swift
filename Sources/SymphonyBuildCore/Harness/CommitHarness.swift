import Foundation

public struct CommitHarnessExecution: Sendable {
  public let report: HarnessReport
  public let clientInspection: CoverageInspectionReport?
  public let serverInspection: CoverageInspectionReport?

  public init(
    report: HarnessReport, clientInspection: CoverageInspectionReport?,
    serverInspection: CoverageInspectionReport?
  ) {
    self.report = report
    self.clientInspection = clientInspection
    self.serverInspection = serverInspection
  }
}

public struct CommitHarness {
  private let processRunner: ProcessRunning
  private let coverageReporter: PackageCoverageReporter
  private let statusSink: @Sendable (String) -> Void
  private let clientCoverageLoader: (@Sendable (WorkspaceContext) throws -> CoverageReport)?
  private let serverCoverageLoader: (@Sendable (WorkspaceContext) throws -> CoverageReport)?
  private let toolchainCapabilitiesResolver: ToolchainCapabilitiesResolving

  public init(
    processRunner: ProcessRunning = SystemProcessRunner(),
    coverageReporter: PackageCoverageReporter = PackageCoverageReporter(),
    statusSink: @escaping @Sendable (String) -> Void = { _ in },
    clientCoverageLoader: (@Sendable (WorkspaceContext) throws -> CoverageReport)? = nil,
    serverCoverageLoader: (@Sendable (WorkspaceContext) throws -> CoverageReport)? = nil,
    toolchainCapabilitiesResolver: ToolchainCapabilitiesResolving? = nil
  ) {
    self.processRunner = processRunner
    self.coverageReporter = coverageReporter
    self.statusSink = statusSink
    self.clientCoverageLoader = clientCoverageLoader
    self.serverCoverageLoader = serverCoverageLoader
    self.toolchainCapabilitiesResolver =
      toolchainCapabilitiesResolver
      ?? ProcessToolchainCapabilitiesResolver(processRunner: processRunner)
  }

  public func run(workspace: WorkspaceContext, request: HarnessCommandRequest) throws
    -> HarnessReport
  {
    let execution = try execute(workspace: workspace, request: request)
    let report = execution.report

    guard report.meetsCoverageThreshold else {
      throw SymphonyBuildCommandFailure(
        message: """
          Commit harness failed because one or more required coverage suites are below the required threshold.
          \(coverageReporter.renderHuman(report: report))
          """
      )
    }

    return report
  }

  public func execute(workspace: WorkspaceContext, request: HarnessCommandRequest) throws
    -> CommitHarnessExecution
  {
    guard request.minimumCoveragePercent >= 0, request.minimumCoveragePercent <= 100 else {
      throw SymphonyBuildError(
        code: "invalid_coverage_threshold",
        message: "The minimum coverage threshold must be between 0 and 100.")
    }

    let testsInvocation = ShellQuoting.render(
      command: "swift", arguments: ["test", "--enable-code-coverage"])
    let coveragePathInvocation = ShellQuoting.render(
      command: "swift", arguments: ["test", "--show-code-coverage-path"])

    statusSink("[symphony-build] running commit harness tests")
    let harnessReporter = XcodeOutputReporter(
      mode: request.outputMode, sink: statusSink, commandName: "swift test")
    defer { harnessReporter.finish() }
    let testResult = try processRunner.run(
      command: "swift",
      arguments: ["test", "--enable-code-coverage"],
      environment: [:],
      currentDirectory: workspace.projectRoot,
      observation: harnessReporter.makeObservation(label: "swift test")
    )
    guard testResult.exitStatus == 0 else {
      throw SymphonyBuildCommandFailure(
        message: "Commit harness failed because `swift test --enable-code-coverage` did not pass.")
    }

    let coveragePathResult = try processRunner.run(
      command: "swift",
      arguments: ["test", "--show-code-coverage-path"],
      environment: [:],
      currentDirectory: workspace.projectRoot,
      observation: nil
    )
    guard coveragePathResult.exitStatus == 0 else {
      throw SymphonyBuildCommandFailure(
        message: "Commit harness failed because SwiftPM did not return a coverage JSON path.")
    }

    let rawPath = coveragePathResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !rawPath.isEmpty else {
      throw SymphonyBuildError(
        code: "missing_package_coverage_path",
        message: "SwiftPM returned an empty coverage JSON path.")
    }

    let coverageReport = try coverageReporter.loadReport(
      at: URL(fileURLWithPath: rawPath),
      projectRoot: workspace.projectRoot
    )
    let clientCoverageInvocation = ShellQuoting.render(
      command: Self.currentExecutablePath(workingDirectory: workspace.projectRoot),
      arguments: Self.coverageSuiteArguments(
        product: "client", platform: "macos", outputMode: request.outputMode)
    )
    let serverCoverageInvocation = ShellQuoting.render(
      command: Self.currentExecutablePath(workingDirectory: workspace.projectRoot),
      arguments: Self.coverageSuiteArguments(
        product: "server", platform: nil, outputMode: request.outputMode)
    )
    let capabilities = try toolchainCapabilitiesResolver.resolve()
    let clientExecution: CoverageSuiteExecution?
    let clientCoverageInvocationForReport: String?
    let clientCoverageSkipReason: String?
    if let clientCoverageLoader {
      clientExecution = CoverageSuiteExecution(
        report: try clientCoverageLoader(workspace), inspection: nil)
      clientCoverageInvocationForReport = clientCoverageInvocation
      clientCoverageSkipReason = nil
    } else if !capabilities.supportsXcodeCommands {
      clientExecution = nil
      clientCoverageInvocationForReport = nil
      clientCoverageSkipReason = Self.noXcodeMessage
    } else {
      clientExecution = try Self.runCoverageSuiteExecution(
        processRunner: processRunner,
        executablePath: Self.currentExecutablePath(workingDirectory: workspace.projectRoot),
        arguments: Self.coverageSuiteArguments(
          product: "client", platform: "macos", outputMode: request.outputMode),
        currentDirectory: workspace.projectRoot,
        statusSink: statusSink
      )
      clientCoverageInvocationForReport = clientCoverageInvocation
      clientCoverageSkipReason = nil
    }
    let serverExecution: CoverageSuiteExecution
    if let serverCoverageLoader {
      serverExecution = CoverageSuiteExecution(
        report: try serverCoverageLoader(workspace), inspection: nil)
    } else {
      serverExecution = try Self.runCoverageSuiteExecution(
        processRunner: processRunner,
        executablePath: Self.currentExecutablePath(workingDirectory: workspace.projectRoot),
        arguments: Self.coverageSuiteArguments(
          product: "server", platform: nil, outputMode: request.outputMode),
        currentDirectory: workspace.projectRoot,
        statusSink: statusSink
      )
    }
    let clientCoverage = clientExecution?.report
    let serverCoverage = serverExecution.report
    let threshold = request.minimumCoveragePercent / 100
    let packageFileViolations = coverageReporter.makePackageFileViolations(
      report: coverageReport, minimumLineCoverage: threshold)
    let clientTargetViolations =
      clientCoverage.map {
        coverageReporter.makeTargetViolations(
          report: $0, suite: "client", minimumLineCoverage: threshold)
      } ?? []
    let clientFileViolations =
      clientCoverage.map {
        coverageReporter.makeFileViolations(
          report: $0, suite: "client", minimumLineCoverage: threshold)
      } ?? []
    let serverTargetViolations = coverageReporter.makeTargetViolations(
      report: serverCoverage, suite: "server", minimumLineCoverage: threshold)
    let serverFileViolations = coverageReporter.makeFileViolations(
      report: serverCoverage, suite: "server", minimumLineCoverage: threshold)

    let report = HarnessReport(
      minimumCoveragePercent: request.minimumCoveragePercent,
      testsInvocation: testsInvocation,
      coveragePathInvocation: coveragePathInvocation,
      packageCoverage: coverageReport,
      clientCoverageInvocation: clientCoverageInvocationForReport,
      clientCoverage: clientCoverage,
      clientCoverageSkipReason: clientCoverageSkipReason,
      serverCoverageInvocation: serverCoverageInvocation,
      serverCoverage: serverCoverage,
      packageFileViolations: packageFileViolations,
      clientTargetViolations: clientTargetViolations,
      clientFileViolations: clientFileViolations,
      serverTargetViolations: serverTargetViolations,
      serverFileViolations: serverFileViolations
    )

    return CommitHarnessExecution(
      report: report,
      clientInspection: clientExecution?.inspection,
      serverInspection: serverExecution.inspection
    )
  }

  public func renderHuman(report: HarnessReport) -> String {
    coverageReporter.renderHuman(report: report)
  }

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

  static func runCoverageSuiteExecution(
    processRunner: ProcessRunning,
    executablePath: String,
    arguments: [String],
    currentDirectory: URL,
    statusSink: @escaping @Sendable (String) -> Void
  ) throws -> CoverageSuiteExecution {
    let label = "symphony-build " + arguments.joined(separator: " ")
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
      throw SymphonyBuildCommandFailure(
        message:
          "Commit harness failed because `\(ShellQuoting.render(command: executablePath, arguments: arguments))` did not pass."
      )
    }

    let artifactRoot = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !artifactRoot.isEmpty else {
      throw SymphonyBuildError(
        code: "missing_test_artifact_root",
        message: "The test command did not return an artifact root path.")
    }
    let artifactRootURL = URL(fileURLWithPath: artifactRoot)

    let coverageJSONPath = artifactRootURL.appendingPathComponent("coverage.json")
    guard FileManager.default.fileExists(atPath: coverageJSONPath.path) else {
      throw SymphonyBuildError(
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
    var arguments = [
      "test",
      "--product", product,
    ]
    if let platform {
      arguments += ["--platform", platform]
    }
    if outputMode != .filtered {
      arguments.append(contentsOf: ["--xcode-output-mode", outputMode.rawValue])
    }
    return arguments
  }
}

extension CommitHarness {
  fileprivate static let noXcodeMessage =
    "not supported because the current environment has no Xcode available; Editing those sources is not encouraged"
}

struct CoverageSuiteExecution: Sendable {
  let report: CoverageReport
  let inspection: CoverageInspectionReport?
}

public struct GitHookInstaller {
  private let processRunner: ProcessRunning

  public init(processRunner: ProcessRunning = SystemProcessRunner()) {
    self.processRunner = processRunner
  }

  public func install(workspace: WorkspaceContext) throws -> String {
    let result = try processRunner.run(
      command: "git",
      arguments: ["config", "core.hooksPath", ".githooks"],
      environment: [:],
      currentDirectory: workspace.projectRoot,
      observation: nil
    )

    guard result.exitStatus == 0 else {
      throw SymphonyBuildError(
        code: "git_hooks_install_failed",
        message: result.combinedOutput.isEmpty
          ? "Failed to configure core.hooksPath." : result.combinedOutput
      )
    }

    return workspace.projectRoot.appendingPathComponent(".githooks", isDirectory: true).path
  }
}
