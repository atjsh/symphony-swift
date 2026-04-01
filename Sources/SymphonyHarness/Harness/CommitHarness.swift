import Foundation

public struct CommitHarnessExecution: Sendable {
  public let report: HarnessReport
  public let packageInspectionFiles: [CoverageInspectionFileReport]
  public let clientInspection: CoverageInspectionReport?
  public let serverInspection: CoverageInspectionReport?

  public init(
    report: HarnessReport,
    packageInspectionFiles: [CoverageInspectionFileReport],
    clientInspection: CoverageInspectionReport?,
    serverInspection: CoverageInspectionReport?
  ) {
    self.report = report
    self.packageInspectionFiles = packageInspectionFiles
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

  func run(workspace: WorkspaceContext, request: HarnessCommandRequest) throws
    -> HarnessReport
  {
    let execution = try execute(workspace: workspace, request: request)
    let report = execution.report

    guard report.meetsCoverageThreshold else {
      throw SymphonyHarnessCommandFailure(
        message: """
          Commit harness failed because one or more required coverage suites are below the required threshold.
          \(coverageReporter.renderHuman(report: report))
          """
      )
    }

    return report
  }

  func execute(workspace: WorkspaceContext, request: HarnessCommandRequest) throws
    -> CommitHarnessExecution
  {
    guard request.minimumCoveragePercent >= 0, request.minimumCoveragePercent <= 100 else {
      throw SymphonyHarnessError(
        code: "invalid_coverage_threshold",
        message: "The minimum coverage threshold must be between 0 and 100.")
    }

    let testsInvocation = ShellQuoting.render(
      command: "swift", arguments: ["test", "--enable-code-coverage"])
    let coveragePathInvocation = ShellQuoting.render(
      command: "swift", arguments: ["test", "--show-code-coverage-path"])
    let packageCoveragePath = try Self.resolveSwiftPMCoveragePath(
      processRunner: processRunner,
      projectRoot: workspace.projectRoot
    )
    try Self.clearExistingCoverageExport(at: packageCoveragePath)

    statusSink("[harness] running commit harness tests")
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
      throw SymphonyHarnessCommandFailure(
        message: "Commit harness failed because `swift test --enable-code-coverage` did not pass.")
    }

    let coverageReport = try coverageReporter.loadReport(
      at: packageCoveragePath,
      projectRoot: workspace.projectRoot
    )
    let capabilities = try toolchainCapabilitiesResolver.resolve()
    let packageInspectionFiles =
      (try? Self.inspectPackageCoverageFiles(
        report: coverageReport,
        projectRoot: workspace.projectRoot,
        processRunner: processRunner,
        llvmCovCommand: capabilities.llvmCovCommand
      )) ?? []
    let threshold = request.minimumCoveragePercent / 100
    let rawPackageFileViolations = coverageReporter.makePackageFileViolations(
      report: coverageReport, minimumLineCoverage: threshold)
    let packageFileViolations = Self.applyInspectionFiles(
      packageInspectionFiles,
      to: rawPackageFileViolations,
      processRunner: processRunner,
      xcrunAvailable: capabilities.xcrunAvailable
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
      packageInspectionFiles: packageInspectionFiles,
      clientInspection: clientExecution?.inspection,
      serverInspection: serverExecution.inspection
    )
  }

  public func renderHuman(report: HarnessReport) -> String {
    coverageReporter.renderHuman(report: report)
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
      throw SymphonyHarnessError(
        code: "git_hooks_install_failed",
        message: result.combinedOutput.isEmpty
          ? "Failed to configure core.hooksPath." : result.combinedOutput
      )
    }

    return workspace.projectRoot.appendingPathComponent(".githooks", isDirectory: true).path
  }
}
