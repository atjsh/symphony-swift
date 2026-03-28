import Foundation
import SymphonyShared

public final class SymphonyHarnessTool {
  private let workspaceDiscovery: WorkspaceDiscovering
  private let executionContextBuilder: ExecutionContextBuilder
  private let simulatorResolver: SimulatorResolver
  private let processRunner: ProcessRunning
  private let artifactManager: ArtifactManager
  private let endpointOverrideStore: EndpointOverrideStore
  private let doctorService: DoctorServicing
  private let toolchainCapabilitiesResolver: ToolchainCapabilitiesResolving
  private let productLocator: ProductLocator
  private let commitHarness: CommitHarness
  private let gitHookInstaller: GitHookInstaller
  private let statusSink: @Sendable (String) -> Void

  public init(
    workspaceDiscovery: WorkspaceDiscovering = WorkspaceDiscovery(),
    executionContextBuilder: ExecutionContextBuilder = ExecutionContextBuilder(),
    simulatorResolver: SimulatorResolver = SimulatorResolver(),
    processRunner: ProcessRunning = SystemProcessRunner(),
    artifactManager: ArtifactManager = ArtifactManager(),
    endpointOverrideStore: EndpointOverrideStore = EndpointOverrideStore(),
    doctorService: DoctorServicing? = nil,
    toolchainCapabilitiesResolver: ToolchainCapabilitiesResolving? = nil,
    productLocator: ProductLocator = ProductLocator(),
    commitHarness: CommitHarness? = nil,
    gitHookInstaller: GitHookInstaller? = nil,
    statusSink: @escaping @Sendable (String) -> Void = { message in
      FileHandle.standardError.write(Data((message + "\n").utf8))
    }
  ) {
    self.workspaceDiscovery = workspaceDiscovery
    self.executionContextBuilder = executionContextBuilder
    self.simulatorResolver = simulatorResolver
    self.processRunner = processRunner
    self.artifactManager = artifactManager
    self.endpointOverrideStore = endpointOverrideStore
    let resolvedToolchainCapabilitiesResolver =
      toolchainCapabilitiesResolver
      ?? ProcessToolchainCapabilitiesResolver(processRunner: processRunner)
    self.toolchainCapabilitiesResolver = resolvedToolchainCapabilitiesResolver
    self.doctorService =
      doctorService
      ?? DoctorService(
        workspaceDiscovery: workspaceDiscovery,
        processRunner: processRunner,
        toolchainCapabilitiesResolver: resolvedToolchainCapabilitiesResolver
      )
    self.productLocator = productLocator
    self.statusSink = statusSink
    self.commitHarness =
      commitHarness
      ?? CommitHarness(
        processRunner: processRunner,
        statusSink: statusSink,
        toolchainCapabilitiesResolver: resolvedToolchainCapabilitiesResolver
      )
    self.gitHookInstaller = gitHookInstaller ?? GitHookInstaller(processRunner: processRunner)
  }

  func build(_ request: BuildCommandRequest) throws -> String {
    let workspace = try workspaceDiscovery.discover(from: request.currentDirectory)
    let worker = try WorkerScope(id: request.workerID)
    let selector = SchemeSelector(
      product: request.product, scheme: request.scheme, platform: request.platform)
    let executionContext = try executionContextBuilder.make(
      workspace: workspace, worker: worker, command: .build, runID: selector.runIdentifier)
    switch selector.product.defaultBackend {
    case .xcode:
      if !request.dryRun {
        try ensureXcodeSupport(for: selector.platform)
      }
      let destination = try xcodeDestination(
        platform: selector.platform, simulator: request.simulator, dryRun: request.dryRun)
      return try buildXcode(
        request: request,
        workspace: workspace,
        selector: selector,
        destination: destination,
        executionContext: executionContext
      )
    case .swiftPM:
      let destination = try simulatorResolver.resolve(
        destinationSelector(platform: selector.platform, simulator: request.simulator))
      return try buildSwiftPM(
        request: request,
        workspace: workspace,
        selector: selector,
        destination: destination,
        executionContext: executionContext
      )
    }
  }

  func test(_ request: TestCommandRequest) throws -> String {
    let workspace = try workspaceDiscovery.discover(from: request.currentDirectory)
    let worker = try WorkerScope(id: request.workerID)
    let selector = SchemeSelector(
      product: request.product, scheme: request.scheme, platform: request.platform)
    let executionContext = try executionContextBuilder.make(
      workspace: workspace, worker: worker, command: .test, runID: selector.runIdentifier)
    switch selector.product.defaultBackend {
    case .xcode:
      if !request.dryRun {
        try ensureXcodeSupport(for: selector.platform)
      }
      let destination = try xcodeDestination(
        platform: selector.platform, simulator: request.simulator, dryRun: request.dryRun)
      return try testXcode(
        request: request,
        workspace: workspace,
        selector: selector,
        destination: destination,
        executionContext: executionContext
      )
    case .swiftPM:
      let destination = try simulatorResolver.resolve(
        destinationSelector(platform: selector.platform, simulator: request.simulator))
      return try testSwiftPM(
        request: request,
        workspace: workspace,
        selector: selector,
        destination: destination,
        executionContext: executionContext
      )
    }
  }

  func run(_ request: RunCommandRequest) throws -> String {
    let workspace = try workspaceDiscovery.discover(from: request.currentDirectory)
    let worker = try WorkerScope(id: request.workerID)
    let selector = SchemeSelector(
      product: request.product, scheme: request.scheme, platform: request.platform)
    let executionContext = try executionContextBuilder.make(
      workspace: workspace, worker: worker, command: .run, runID: selector.runIdentifier)
    switch selector.product.defaultBackend {
    case .xcode:
      if !request.dryRun {
        try ensureXcodeSupport(for: selector.platform)
      }
      let destination = try xcodeDestination(
        platform: selector.platform, simulator: request.simulator, dryRun: request.dryRun)
      return try runXcode(
        request: request,
        workspace: workspace,
        selector: selector,
        destination: destination,
        executionContext: executionContext
      )
    case .swiftPM:
      let destination = try simulatorResolver.resolve(
        destinationSelector(platform: selector.platform, simulator: request.simulator))
      return try runSwiftPM(
        request: request,
        workspace: workspace,
        selector: selector,
        destination: destination,
        executionContext: executionContext
      )
    }
  }

  private func buildXcode(
    request: BuildCommandRequest,
    workspace: WorkspaceContext,
    selector: SchemeSelector,
    destination: ResolvedDestination,
    executionContext: ExecutionContext
  ) throws -> String {
    let xcodeRequest = XcodeCommandRequest(
      action: request.buildForTesting ? .buildForTesting : .build,
      scheme: selector.scheme,
      destination: destination,
      derivedDataPath: executionContext.derivedDataPath,
      resultBundlePath: executionContext.resultBundlePath,
      outputMode: request.outputMode,
      environment: [:],
      workspacePath: workspace.xcodeWorkspacePath,
      projectPath: workspace.xcodeProjectPath
    )

    if request.dryRun {
      return try xcodeRequest.renderedCommandLine()
    }

    try prepareXcodeExecutionContext(executionContext)

    let startedAt = Date()
    let reporter = XcodeOutputReporter(mode: request.outputMode, sink: statusSink)
    defer { reporter.finish() }
    let result = try processRunner.run(
      command: "xcodebuild",
      arguments: try xcodeRequest.renderedArguments(),
      environment: [:],
      currentDirectory: workspace.projectRoot,
      observation: reporter.makeObservation(label: "xcodebuild build")
    )
    let endedAt = Date()
    let record = try artifactManager.recordXcodeExecution(
      workspace: workspace,
      executionContext: executionContext,
      command: .build,
      product: request.product,
      scheme: selector.scheme,
      destination: destination,
      invocation: try xcodeRequest.renderedCommandLine(),
      exitStatus: result.exitStatus,
      combinedOutput: result.combinedOutput,
      startedAt: startedAt,
      endedAt: endedAt,
      subjectName: request.subjectName
    )

    guard result.exitStatus == 0 else {
      throw SymphonyHarnessCommandFailure(
        message: "xcodebuild \(request.buildForTesting ? "build-for-testing" : "build") failed.",
        summaryPath: record.run.summaryPath)
    }
    return record.run.summaryPath.path
  }

  private func buildSwiftPM(
    request: BuildCommandRequest,
    workspace: WorkspaceContext,
    selector: SchemeSelector,
    destination: ResolvedDestination,
    executionContext: ExecutionContext
  ) throws -> String {
    let productName = request.swiftPMProduct ?? request.product.defaultSwiftPMProduct!
    let invocation = renderSwiftBuildCommandLine(productName: productName)

    if request.dryRun {
      return invocation
    }

    let startedAt = Date()
    let result = try processRunner.run(
      command: "swift",
      arguments: ["build", "--product", productName],
      environment: [:],
      currentDirectory: workspace.projectRoot,
      observation: nil
    )
    let endedAt = Date()
    let record = try artifactManager.recordSwiftPMExecution(
      workspace: workspace,
      executionContext: executionContext,
      command: .build,
      product: request.product,
      scheme: selector.scheme,
      destination: destination,
      invocation: invocation,
      exitStatus: result.exitStatus,
      combinedOutput: result.combinedOutput,
      startedAt: startedAt,
      endedAt: endedAt,
      subjectName: request.subjectName
    )

    guard result.exitStatus == 0 else {
      throw SymphonyHarnessCommandFailure(
        message: "swift build failed.", summaryPath: record.run.summaryPath)
    }
    return record.run.summaryPath.path
  }

  private func testXcode(
    request: TestCommandRequest,
    workspace: WorkspaceContext,
    selector: SchemeSelector,
    destination: ResolvedDestination,
    executionContext: ExecutionContext
  ) throws -> String {
    let xcodeRequest = XcodeCommandRequest(
      action: .test,
      scheme: selector.scheme,
      destination: destination,
      derivedDataPath: executionContext.derivedDataPath,
      resultBundlePath: executionContext.resultBundlePath,
      enableCodeCoverage: true,
      outputMode: request.outputMode,
      environment: [:],
      workspacePath: workspace.xcodeWorkspacePath,
      projectPath: workspace.xcodeProjectPath,
      onlyTesting: request.onlyTesting,
      skipTesting: request.skipTesting
    )
    let coverageReporter = CoverageReporter(processRunner: processRunner)
    let coverageCommand = coverageReporter.renderedCommandLine(
      resultBundlePath: executionContext.resultBundlePath)

    if request.dryRun {
      return [
        try xcodeRequest.renderedCommandLine(),
        coverageCommand,
      ].joined(separator: "\n")
    }

    try prepareXcodeExecutionContext(executionContext)

    let startedAt = Date()
    let reporter = XcodeOutputReporter(mode: request.outputMode, sink: statusSink)
    defer { reporter.finish() }
    let result = try processRunner.run(
      command: "xcodebuild",
      arguments: try xcodeRequest.renderedArguments(),
      environment: [:],
      currentDirectory: workspace.projectRoot,
      observation: reporter.makeObservation(label: "xcodebuild test")
    )
    let endedAt = Date()

    var coverageAnomalies = [ArtifactAnomaly]()
    if result.exitStatus == 0 {
      do {
        let exportedArtifacts = try coverageReporter.export(
          resultBundlePath: executionContext.resultBundlePath,
          artifactRoot: executionContext.artifactRoot,
          product: request.product,
          includeTestTargets: false,
          showFiles: true
        )
        _ = try displayedCoverageArtifacts(
          from: exportedArtifacts,
          showFiles: true,
          artifactRoot: executionContext.artifactRoot
        )

        let inspection = try XcodeCoverageInspector(processRunner: processRunner).inspect(
          resultBundlePath: executionContext.resultBundlePath,
          candidates: inspectionCandidates(from: exportedArtifacts.report),
          includeFunctions: true,
          includeMissingLines: true
        )
        let normalizedInspection = CoverageInspectionReport(
          backend: .xcode,
          product: request.product,
          generatedAt: DateFormatting.iso8601(endedAt),
          files: inspection.files
        )
        let rawInspection = CoverageInspectionRawReport(
          backend: .xcode,
          product: request.product,
          commands: inspection.rawCommands
        )
        try writeCoverageInspectionArtifacts(
          artifactRoot: executionContext.artifactRoot,
          normalizedReport: normalizedInspection,
          rawReport: rawInspection
        )
      } catch let error as SymphonyHarnessError {
        coverageAnomalies.append(
          ArtifactAnomaly(code: error.code, message: error.message, phase: "coverage"))
      } catch {
        coverageAnomalies.append(
          ArtifactAnomaly(
            code: "coverage_export_failed", message: error.localizedDescription, phase: "coverage")
        )
      }
    }

    let record = try artifactManager.recordXcodeExecution(
      workspace: workspace,
      executionContext: executionContext,
      command: .test,
      product: request.product,
      scheme: selector.scheme,
      destination: destination,
      invocation: [
        try xcodeRequest.renderedCommandLine(),
        coverageCommand,
      ].joined(separator: "\n"),
      exitStatus: result.exitStatus,
      combinedOutput: result.combinedOutput,
      startedAt: startedAt,
      endedAt: endedAt,
      subjectName: request.subjectName,
      extraAnomalies: coverageAnomalies
    )

    guard result.exitStatus == 0 else {
      throw SymphonyHarnessCommandFailure(
        message: "xcodebuild test failed.", summaryPath: record.run.summaryPath)
    }
    return record.run.artifactRoot.path
  }

  private func testSwiftPM(
    request: TestCommandRequest,
    workspace: WorkspaceContext,
    selector: SchemeSelector,
    destination: ResolvedDestination,
    executionContext: ExecutionContext
  ) throws -> String {
    let testFilter = request.swiftPMTestFilter ?? request.product.defaultSwiftPMTestFilter!
    let coverageCommand = renderSwiftTestCommandLine(filter: testFilter, enableCodeCoverage: true)
    let coveragePathCommand = SwiftPMCoverageReporter().renderedCoveragePathCommandLine()

    if request.dryRun {
      return [coverageCommand, coveragePathCommand].joined(separator: "\n")
    }

    let startedAt = Date()
    let result = try processRunner.run(
      command: "swift",
      arguments: ["test", "--enable-code-coverage", "--filter", testFilter],
      environment: [:],
      currentDirectory: workspace.projectRoot,
      observation: nil
    )

    var coverageAnomalies = [ArtifactAnomaly]()
    var coveragePathOutput = ""
    if result.exitStatus == 0 {
      do {
        let coveragePathResult = try processRunner.run(
          command: "swift",
          arguments: ["test", "--show-code-coverage-path"],
          environment: [:],
          currentDirectory: workspace.projectRoot,
          observation: nil
        )
        coveragePathOutput = coveragePathResult.combinedOutput
        guard coveragePathResult.exitStatus == 0 else {
          throw SymphonyHarnessError(
            code: "swiftpm_coverage_path_failed",
            message: coveragePathResult.combinedOutput.isEmpty
              ? "SwiftPM did not return a coverage JSON path." : coveragePathResult.combinedOutput
          )
        }

        let rawPath = coveragePathResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawPath.isEmpty else {
          throw SymphonyHarnessError(
            code: "missing_swiftpm_coverage_path",
            message: "SwiftPM returned an empty coverage JSON path.")
        }

        let coverageScope: SwiftPMCoverageScope
        if
          let subjectName = request.subjectName,
          let subjectScope = SwiftPMCoverageScope.subjectOwned(for: subjectName)
        {
          coverageScope = subjectScope
        } else {
          coverageScope = .serverAggregate
        }
        let exportedArtifacts = try SwiftPMCoverageReporter().exportCoverage(
          coverageJSONPath: URL(fileURLWithPath: rawPath),
          projectRoot: workspace.projectRoot,
          artifactRoot: executionContext.artifactRoot,
          scope: coverageScope,
          showFiles: true
        )
        _ = try displayedCoverageArtifacts(
          from: exportedArtifacts,
          showFiles: true,
          artifactRoot: executionContext.artifactRoot
        )

        let inspection = try SwiftPMCoverageInspector(
          processRunner: processRunner,
          llvmCovCommand: try toolchainCapabilitiesResolver.resolve().llvmCovCommand
        ).inspect(
          coverageJSONPath: URL(fileURLWithPath: rawPath),
          projectRoot: workspace.projectRoot,
          candidates: inspectionCandidates(from: exportedArtifacts.report),
          includeFunctions: true,
          includeMissingLines: true
        )
        let normalizedInspection = CoverageInspectionReport(
          backend: .swiftPM,
          product: request.product,
          generatedAt: DateFormatting.iso8601(Date()),
          files: inspection.files
        )
        let rawInspection = CoverageInspectionRawReport(
          backend: .swiftPM,
          product: request.product,
          commands: inspection.rawCommands
        )
        try writeCoverageInspectionArtifacts(
          artifactRoot: executionContext.artifactRoot,
          normalizedReport: normalizedInspection,
          rawReport: rawInspection
        )
      } catch let error as SymphonyHarnessError {
        coverageAnomalies.append(
          ArtifactAnomaly(code: error.code, message: error.message, phase: "coverage"))
      } catch {
        coverageAnomalies.append(
          ArtifactAnomaly(
            code: "coverage_export_failed", message: error.localizedDescription, phase: "coverage"))
      }
    }

    let endedAt = Date()
    let record = try artifactManager.recordSwiftPMExecution(
      workspace: workspace,
      executionContext: executionContext,
      command: .test,
      product: request.product,
      scheme: selector.scheme,
      destination: destination,
      invocation: [coverageCommand, coveragePathCommand].joined(separator: "\n"),
      exitStatus: result.exitStatus,
      combinedOutput: [result.combinedOutput, coveragePathOutput].filter { !$0.isEmpty }.joined(
        separator: "\n"),
      startedAt: startedAt,
      endedAt: endedAt,
      subjectName: request.subjectName,
      extraAnomalies: coverageAnomalies
    )

    guard result.exitStatus == 0 else {
      throw SymphonyHarnessCommandFailure(
        message: "swift test failed.", summaryPath: record.run.summaryPath)
    }
    return record.run.artifactRoot.path
  }

  private func runXcode(
    request: RunCommandRequest,
    workspace: WorkspaceContext,
    selector: SchemeSelector,
    destination: ResolvedDestination,
    executionContext: ExecutionContext
  ) throws -> String {
    let xcodeRequest = XcodeCommandRequest(
      action: .build,
      scheme: selector.scheme,
      destination: destination,
      derivedDataPath: executionContext.derivedDataPath,
      resultBundlePath: executionContext.resultBundlePath,
      outputMode: request.outputMode,
      environment: [:],
      workspacePath: workspace.xcodeWorkspacePath,
      projectPath: workspace.xcodeProjectPath
    )

    let endpoint = try endpointOverrideStore.resolve(
      workspace: workspace,
      serverURL: request.serverURL,
      scheme: request.serverScheme,
      host: request.host,
      port: request.port
    )
    let launchConfiguration = LaunchConfiguration(
      target: .client,
      scheme: selector.scheme,
      destination: destination,
      endpoint: endpoint,
      environment: request.environment
    )

    if request.dryRun {
      return try renderXcodeRunSequence(
        xcodeRequest: xcodeRequest,
        configuration: launchConfiguration,
        productDetails: nil
      )
    }

    try prepareXcodeExecutionContext(executionContext)

    var commandOutput = [String]()
    var resolvedProductDetails: ProductDetails?
    let startedAt = Date()
    let reporter = XcodeOutputReporter(mode: request.outputMode, sink: statusSink)
    defer { reporter.finish() }
    let buildResult = try processRunner.run(
      command: "xcodebuild",
      arguments: try xcodeRequest.renderedArguments(),
      environment: [:],
      currentDirectory: workspace.projectRoot,
      observation: reporter.makeObservation(label: "xcodebuild run build step")
    )
    commandOutput.append(buildResult.combinedOutput)
    var anomalies = [ArtifactAnomaly]()

    if buildResult.exitStatus == 0 {
      try simulatorResolver.boot(resolved: destination)
      let details = try productLocator.locateProduct(
        workspace: workspace,
        scheme: selector.scheme,
        destination: destination,
        derivedDataPath: executionContext.derivedDataPath
      )
      resolvedProductDetails = details
      guard let bundleIdentifier = details.bundleIdentifier,
        let simulatorUDID = destination.simulatorUDID
      else {
        throw SymphonyHarnessError(
          code: "missing_launch_metadata",
          message:
            "The client launch is missing the simulator destination or product bundle identifier.")
      }
      let install = try processRunner.run(
        command: "xcrun",
        arguments: ["simctl", "install", simulatorUDID, details.productURL.path],
        environment: [:],
        currentDirectory: workspace.projectRoot,
        observation: ProcessObservation(label: "simctl install")
      )
      commandOutput.append(install.combinedOutput)
      if install.exitStatus != 0 {
        anomalies.append(
          ArtifactAnomaly(
            code: "simulator_install_failed",
            message: install.combinedOutput.isEmpty
              ? "Failed to install the app in the simulator." : install.combinedOutput,
            phase: "launch"))
      } else {
        let launchEnvironment = simctlEnvironment(
          endpoint: endpoint, overrides: request.environment)
        let launch = try processRunner.run(
          command: "xcrun",
          arguments: ["simctl", "launch", simulatorUDID, bundleIdentifier],
          environment: launchEnvironment,
          currentDirectory: workspace.projectRoot,
          observation: ProcessObservation(label: "simctl launch")
        )
        commandOutput.append(launch.combinedOutput)
        if launch.exitStatus != 0 {
          anomalies.append(
            ArtifactAnomaly(
              code: "simulator_launch_failed",
              message: launch.combinedOutput.isEmpty
                ? "Failed to launch the app in the simulator." : launch.combinedOutput,
              phase: "launch"))
        }
      }
    }

    let endedAt = Date()
    let combinedOutput = commandOutput.filter { !$0.isEmpty }.joined(separator: "\n")
    let record = try artifactManager.recordXcodeExecution(
      workspace: workspace,
      executionContext: executionContext,
      command: .run,
      product: request.product,
      scheme: selector.scheme,
      destination: destination,
      invocation: try renderXcodeRunSequence(
        xcodeRequest: xcodeRequest,
        configuration: launchConfiguration,
        productDetails: resolvedProductDetails
      ),
      exitStatus: buildResult.exitStatus == 0 && anomalies.isEmpty
        ? 0 : (buildResult.exitStatus == 0 ? 1 : buildResult.exitStatus),
      combinedOutput: combinedOutput,
      startedAt: startedAt,
      endedAt: endedAt,
      subjectName: request.subjectName,
      extraAnomalies: anomalies
    )

    guard buildResult.exitStatus == 0 else {
      throw SymphonyHarnessCommandFailure(
        message: "The run build step failed.", summaryPath: record.run.summaryPath)
    }
    if !anomalies.isEmpty {
      throw SymphonyHarnessCommandFailure(
        message: "The launch step failed.", summaryPath: record.run.summaryPath)
    }
    return record.run.summaryPath.path
  }

  private func runSwiftPM(
    request: RunCommandRequest,
    workspace: WorkspaceContext,
    selector: SchemeSelector,
    destination: ResolvedDestination,
    executionContext: ExecutionContext
  ) throws -> String {
    let productName = request.swiftPMProduct ?? request.product.defaultSwiftPMProduct!

    if request.dryRun {
      return renderSwiftPMRunSequence(productName: productName, binPath: nil)
    }

    let startedAt = Date()
    let buildResult = try processRunner.run(
      command: "swift",
      arguments: ["build", "--product", productName],
      environment: [:],
      currentDirectory: workspace.projectRoot,
      observation: nil
    )

    var combinedOutput = [buildResult.combinedOutput].filter { !$0.isEmpty }
    var executablePath: String?
    var exitStatus = buildResult.exitStatus
    if buildResult.exitStatus == 0 {
      let binPathResult = try processRunner.run(
        command: "swift",
        arguments: ["build", "--show-bin-path"],
        environment: [:],
        currentDirectory: workspace.projectRoot,
        observation: nil
      )
      if !binPathResult.combinedOutput.isEmpty {
        combinedOutput.append(binPathResult.combinedOutput)
      }
      if binPathResult.exitStatus == 0 {
        let rawBinPath = binPathResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rawBinPath.isEmpty {
          executablePath = URL(fileURLWithPath: rawBinPath).appendingPathComponent(productName).path
          let processLog = executionContext.artifactRoot.appendingPathComponent(
            "process-stdout-stderr.txt")
          let pid = try processRunner.startDetached(
            executablePath: executablePath!,
            arguments: [],
            environment: request.environment,
            currentDirectory: workspace.projectRoot,
            output: processLog
          )
          combinedOutput.append("launched server pid=\(pid) executable=\(executablePath!)")
        } else {
          exitStatus = 1
        }
      } else {
        exitStatus = binPathResult.exitStatus
      }
    }

    let endedAt = Date()
    let record = try artifactManager.recordSwiftPMExecution(
      workspace: workspace,
      executionContext: executionContext,
      command: .run,
      product: request.product,
      scheme: selector.scheme,
      destination: destination,
      invocation: renderSwiftPMRunSequence(productName: productName, binPath: {
        if let executablePath {
          return URL(fileURLWithPath: executablePath).deletingLastPathComponent().path
        }
        return nil
      }()),
      exitStatus: exitStatus,
      combinedOutput: combinedOutput.joined(separator: "\n"),
      startedAt: startedAt,
      endedAt: endedAt,
      subjectName: request.subjectName
    )

    guard buildResult.exitStatus == 0 else {
      throw SymphonyHarnessCommandFailure(
        message: "The run build step failed.", summaryPath: record.run.summaryPath)
    }
    guard exitStatus == 0 else {
      throw SymphonyHarnessCommandFailure(
        message: "The launch step failed.", summaryPath: record.run.summaryPath)
    }
    return record.run.summaryPath.path
  }

  func artifacts(_ request: ArtifactsCommandRequest) throws -> String {
    let workspace = try workspaceDiscovery.discover(from: request.currentDirectory)
    return try artifactManager.resolveArtifacts(workspace: workspace, request: request)
  }

  public func doctor(_ request: DoctorCommandRequest) throws -> String {
    let report = try doctorService.makeReport(from: request)
    if request.strict {
      if !report.issues.isEmpty {
        throw SymphonyHarnessCommandFailure(
          message: try doctorService.render(
            report: report, json: request.json, quiet: request.quiet))
      }
    } else if !report.isHealthy {
      throw SymphonyHarnessCommandFailure(
        message: try doctorService.render(report: report, json: request.json, quiet: request.quiet))
    }
    return try doctorService.render(report: report, json: request.json, quiet: request.quiet)
  }

  func harness(_ request: HarnessCommandRequest) throws -> String {
    let workspace = try workspaceDiscovery.discover(from: request.currentDirectory)
    let startedAt = Date()
    let execution = try commitHarness.execute(workspace: workspace, request: request)
    let generatedAt = DateFormatting.iso8601(Date())
    let worker = try WorkerScope(id: 0)
    let executionContext = try executionContextBuilder.make(
      workspace: workspace,
      worker: worker,
      command: .harness,
      runID: "commit-harness"
    )

    let packageInspection = HarnessCoverageInspectionArtifact(
      suite: "package",
      backend: .swiftPM,
      generatedAt: generatedAt,
      files: execution.packageInspectionFiles
    )
    let clientInspection = HarnessCoverageInspectionArtifact(
      suite: "client",
      backend: ProductKind.client.defaultBackend,
      generatedAt: generatedAt,
      files: execution.clientInspection?.files ?? [],
      skippedReason: execution.report.clientCoverageSkipReason
    )
    let serverInspection = HarnessCoverageInspectionArtifact(
      suite: "server",
      backend: ProductKind.server.defaultBackend,
      generatedAt: generatedAt,
      files: execution.serverInspection?.files ?? []
    )

    try writeHarnessInspectionArtifacts(
      packageInspection: packageInspection,
      clientInspection: clientInspection,
      serverInspection: serverInspection,
      artifactRoot: executionContext.artifactRoot
    )

    let reportJSON = try encodePrettyJSON(execution.report)
    let summaryText = commitHarness.renderHuman(report: execution.report)
    let endedAt = Date()
    let record = try artifactManager.recordHarnessExecution(
      workspace: workspace,
      executionContext: executionContext,
      invocation: renderedHarnessCommandLine(request: request),
      exitStatus: execution.report.meetsCoverageThreshold ? 0 : 1,
      summaryJSON: reportJSON,
      summaryText: summaryText,
      startedAt: startedAt,
      endedAt: endedAt
    )

    guard execution.report.meetsCoverageThreshold else {
      throw SymphonyHarnessCommandFailure(
        message: compactHarnessFailureMessage(
          report: execution.report, artifactRoot: record.run.artifactRoot),
        summaryPath: record.run.summaryPath
      )
    }

    return request.json ? reportJSON : summaryText
  }

  func hooksInstall(_ request: HooksInstallRequest) throws -> String {
    let workspace = try workspaceDiscovery.discover(from: request.currentDirectory)
    return try gitHookInstaller.install(workspace: workspace)
  }

  func simList(currentDirectory: URL) throws -> String {
    _ = try workspaceDiscovery.discover(from: currentDirectory)
    try ensureXcodeSupport(for: .iosSimulator)
    return try SimctlSimulatorCatalog(processRunner: processRunner).availableDevices().map {
      "\($0.name) (\($0.udid))"
    }.joined(separator: "\n")
  }

  func simBoot(_ request: SimBootRequest) throws -> String {
    _ = try workspaceDiscovery.discover(from: request.currentDirectory)
    try ensureXcodeSupport(for: .iosSimulator)
    let destination = try simulatorResolver.resolve(
      destinationSelector(platform: .iosSimulator, simulator: request.simulator))
    try simulatorResolver.boot(resolved: destination)
    return destination.displayName
  }

  func simSetServer(_ request: SimSetServerRequest) throws -> String {
    let workspace = try workspaceDiscovery.discover(from: request.currentDirectory)
    let endpoint = try endpointOverrideStore.resolve(
      workspace: workspace, serverURL: request.serverURL, scheme: request.scheme,
      host: request.host, port: request.port)
    let path = try endpointOverrideStore.save(endpoint, in: workspace)
    return path.path
  }

  func simClearServer(currentDirectory: URL) throws -> String {
    let workspace = try workspaceDiscovery.discover(from: currentDirectory)
    let path = endpointOverrideStore.storeURL(in: workspace)
    try endpointOverrideStore.clear(in: workspace)
    return path.path
  }

  private func renderSwiftBuildCommandLine(productName: String) -> String {
    ShellQuoting.render(command: "swift", arguments: ["build", "--product", productName])
  }

  private func renderSwiftTestCommandLine(filter: String, enableCodeCoverage: Bool) -> String {
    var arguments = ["test"]
    if enableCodeCoverage { arguments.append("--enable-code-coverage") }
    arguments += ["--filter", filter]
    return ShellQuoting.render(command: "swift", arguments: arguments)
  }

  private func renderSwiftPMRunSequence(productName: String, binPath: String?) -> String {
    let resolvedBinPath = binPath.map { "\($0)/\(productName)" } ?? "<built-product>/\(productName)"
    return [
      renderSwiftBuildCommandLine(productName: productName),
      ShellQuoting.render(command: "swift", arguments: ["build", "--show-bin-path"]),
      ShellQuoting.render(command: resolvedBinPath, arguments: []),
    ].joined(separator: "\n")
  }

  private func writeHarnessInspectionArtifacts(
    packageInspection: HarnessCoverageInspectionArtifact,
    clientInspection: HarnessCoverageInspectionArtifact,
    serverInspection: HarnessCoverageInspectionArtifact,
    artifactRoot: URL
  ) throws {
    try FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)
    try (encodePrettyJSON(packageInspection) + "\n").write(
      to: artifactRoot.appendingPathComponent("package-inspection.json"),
      atomically: true,
      encoding: .utf8
    )
    try (renderHarnessInspectionHuman(artifact: packageInspection) + "\n").write(
      to: artifactRoot.appendingPathComponent("package-inspection.txt"),
      atomically: true,
      encoding: .utf8
    )
    try (encodePrettyJSON(clientInspection) + "\n").write(
      to: artifactRoot.appendingPathComponent("client-inspection.json"),
      atomically: true,
      encoding: .utf8
    )
    try (renderHarnessInspectionHuman(artifact: clientInspection) + "\n").write(
      to: artifactRoot.appendingPathComponent("client-inspection.txt"),
      atomically: true,
      encoding: .utf8
    )
    try (encodePrettyJSON(serverInspection) + "\n").write(
      to: artifactRoot.appendingPathComponent("server-inspection.json"),
      atomically: true,
      encoding: .utf8
    )
    try (renderHarnessInspectionHuman(artifact: serverInspection) + "\n").write(
      to: artifactRoot.appendingPathComponent("server-inspection.txt"),
      atomically: true,
      encoding: .utf8
    )
  }

  private func displayedCoverageArtifacts(
    from artifacts: CoverageArtifacts,
    showFiles: Bool,
    artifactRoot: URL
  ) throws -> CoverageArtifacts {
    let report = showFiles ? artifacts.report : strippedCoverageReport(artifacts.report)
    let jsonOutput = try encodePrettyJSON(report)
    let textOutput = CoverageReporter().renderHuman(report: report)
    try (jsonOutput + "\n").write(
      to: artifactRoot.appendingPathComponent("coverage.json"), atomically: true, encoding: .utf8)
    try (textOutput + "\n").write(
      to: artifactRoot.appendingPathComponent("coverage.txt"), atomically: true, encoding: .utf8)
    return CoverageArtifacts(
      report: report,
      jsonPath: artifactRoot.appendingPathComponent("coverage.json"),
      textPath: artifactRoot.appendingPathComponent("coverage.txt"),
      jsonOutput: jsonOutput,
      textOutput: textOutput
    )
  }

  private func writeCoverageInspectionArtifacts(
    artifactRoot: URL,
    normalizedReport: CoverageInspectionReport,
    rawReport: CoverageInspectionRawReport
  ) throws {
    let normalizedJSON = try encodePrettyJSON(normalizedReport)
    let normalizedText = renderInspectionHuman(report: normalizedReport)
    try (normalizedJSON + "\n").write(
      to: artifactRoot.appendingPathComponent("coverage-inspection.json"),
      atomically: true,
      encoding: .utf8
    )
    try (normalizedText + "\n").write(
      to: artifactRoot.appendingPathComponent("coverage-inspection.txt"),
      atomically: true,
      encoding: .utf8
    )

    let rawJSON = try encodePrettyJSON(rawReport)
    let rawText = renderRawInspectionHuman(report: rawReport)
    try (rawJSON + "\n").write(
      to: artifactRoot.appendingPathComponent("coverage-inspection-raw.json"),
      atomically: true,
      encoding: .utf8
    )
    try (rawText + "\n").write(
      to: artifactRoot.appendingPathComponent("coverage-inspection-raw.txt"),
      atomically: true,
      encoding: .utf8
    )
  }

  private func renderedHarnessCommandLine(request: HarnessCommandRequest) -> String {
    var arguments = [
      "harness", "--minimum-coverage",
      String(
        format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), request.minimumCoveragePercent),
    ]
    if request.json {
      arguments.append("--json")
    }
    if request.outputMode != .filtered {
      arguments += ["--output-mode", request.outputMode.rawValue]
    }
    return ShellQuoting.render(command: "harness", arguments: arguments)
  }

  private func compactHarnessFailureMessage(report: HarnessReport, artifactRoot: URL) -> String {
    let preview = report.violations.prefix(3).flatMap { violation -> [String] in
      let percentage = String(
        format: "%.2f%%", locale: Locale(identifier: "en_US_POSIX"), violation.lineCoverage * 100)
      var result = [
        "\(violation.suite) \(violation.kind) \(violation.name) \(percentage) (\(violation.coveredLines)/\(violation.executableLines))"
      ]
      if let missingLineRanges = violation.missingLineRanges, !missingLineRanges.isEmpty {
        result.append("  missing_lines \(renderMissingLineRanges(missingLineRanges))")
      }
      if let functions = violation.uncoveredFunctions, !functions.isEmpty {
        for function in functions {
          result.append("  function \(function)")
        }
      }
      return result
    }
    let previewLines = preview.isEmpty ? [] : preview
    return
      ([
        "Commit harness failed because one or more required coverage suites are below the required threshold."
      ] + previewLines + [
        "Harness artifacts: \(artifactRoot.path)"
      ]).joined(separator: "\n")
  }

  private func ensureXcodeSupport(for platform: PlatformKind) throws {
    let capabilities = try toolchainCapabilitiesResolver.resolve()
    guard capabilities.supportsXcodeCommands else {
      throw SymphonyHarnessCommandFailure(message: Self.noXcodeMessage)
    }
    if platform == .iosSimulator, !capabilities.supportsSimulatorCommands {
      throw SymphonyHarnessCommandFailure(message: Self.noXcodeMessage)
    }
  }

  private func xcodeDestination(platform: PlatformKind, simulator: String?, dryRun: Bool) throws
    -> ResolvedDestination
  {
    if dryRun {
      let capabilities = try toolchainCapabilitiesResolver.resolve()
      if !capabilities.supportsXcodeCommands
        || (platform == .iosSimulator && !capabilities.supportsSimulatorCommands)
      {
        return assumedDryRunDestination(platform: platform, simulator: simulator)
      }
    }
    return try simulatorResolver.resolve(
      destinationSelector(platform: platform, simulator: simulator))
  }

  private func assumedDryRunDestination(platform: PlatformKind, simulator: String?)
    -> ResolvedDestination
  {
    switch platform {
    case .macos:
      return ResolvedDestination(
        platform: .macos,
        displayName: "macOS",
        simulatorName: nil,
        simulatorUDID: nil,
        xcodeDestination: expectedHostMacOSDestination()
      )
    case .iosSimulator:
      if let simulator, looksLikeUDID(simulator) {
        return ResolvedDestination(
          platform: .iosSimulator,
          displayName: simulator,
          simulatorName: nil,
          simulatorUDID: simulator,
          xcodeDestination: "platform=iOS Simulator,id=\(simulator)"
        )
      }
      let simulatorName = simulator ?? "iPhone 17"
      return ResolvedDestination(
        platform: .iosSimulator,
        displayName: simulatorName,
        simulatorName: simulatorName,
        simulatorUDID: nil,
        xcodeDestination: "platform=iOS Simulator,name=\(simulatorName)"
      )
    }
  }

  private func destinationSelector(platform: PlatformKind, simulator: String?)
    -> DestinationSelector
  {
    if platform == .iosSimulator, let simulator, looksLikeUDID(simulator) {
      return DestinationSelector(platform: platform, simulatorName: nil, simulatorUDID: simulator)
    }
    return DestinationSelector(platform: platform, simulatorName: simulator, simulatorUDID: nil)
  }

  private func looksLikeUDID(_ value: String) -> Bool {
    value.wholeMatch(of: /^[A-Fa-f0-9-]{36}$/) != nil
  }

  private func expectedHostMacOSDestination() -> String {
    #if arch(arm64)
      "platform=macOS,arch=arm64"
    #elseif arch(x86_64)
      "platform=macOS,arch=x86_64"
    #else
      "platform=macOS"
    #endif
  }

  private func renderXcodeRunSequence(
    xcodeRequest: XcodeCommandRequest,
    configuration: LaunchConfiguration,
    productDetails: ProductDetails?
  ) throws -> String {
    var commands = [try xcodeRequest.renderedCommandLine()]

    if let simulatorUDID = configuration.destination.simulatorUDID {
      commands.append(
        ShellQuoting.render(
          command: "xcrun", arguments: ["simctl", "bootstatus", simulatorUDID, "-b"]))
      if let productDetails, let bundleIdentifier = productDetails.bundleIdentifier {
        commands.append(
          ShellQuoting.render(
            command: "xcrun",
            arguments: ["simctl", "install", simulatorUDID, productDetails.productURL.path]))
        let launchEnvironment = simctlEnvironment(
          endpoint: configuration.endpoint, overrides: configuration.environment)
        let prefix =
          launchEnvironment
          .sorted(by: { $0.key < $1.key })
          .map { "\($0.key)=\(ShellQuoting.quote($0.value))" }
          .joined(separator: " ")
        let launch = ShellQuoting.render(
          command: "xcrun", arguments: ["simctl", "launch", simulatorUDID, bundleIdentifier])
        commands.append("\(prefix) \(launch)")
      } else {
        commands.append("xcrun simctl install \(simulatorUDID) <app>")
        commands.append("xcrun simctl launch \(simulatorUDID) <bundle-id>")
      }
    }

    return commands.joined(separator: "\n")
  }

  private func simctlEnvironment(endpoint: RuntimeEndpoint, overrides: [String: String]) -> [String:
    String]
  {
    var merged = endpointOverrideStore.clientEnvironment(for: endpoint)
    for (key, value) in overrides {
      merged[key] = value
    }

    var prefixed = [String: String]()
    for (key, value) in merged {
      prefixed["SIMCTL_CHILD_\(key)"] = value
    }
    return prefixed
  }

}

extension SymphonyHarnessTool {
  public func execute(_ request: ExecutionRequest, currentDirectory: URL) throws -> String {
    switch request.command {
    case .build:
      return try executeSubjectRequest(request, startDirectory: currentDirectory)
    case .test:
      return try executeSubjectRequest(request, startDirectory: currentDirectory)
    case .run:
      return try executeSubjectRequest(request, startDirectory: currentDirectory)
    case .validate:
      return try executeSubjectRequest(request, startDirectory: currentDirectory)
    case .doctor:
      throw unsupportedSubjectBridgeError(for: request)
    }
  }

  public func build(_ request: ExecutionRequest) throws -> String {
    try executeSubjectRequest(request, startDirectory: currentWorkingDirectory())
  }

  public func test(_ request: ExecutionRequest) throws -> String {
    try executeSubjectRequest(request, startDirectory: currentWorkingDirectory())
  }

  public func run(_ request: ExecutionRequest) throws -> String {
    try executeSubjectRequest(request, startDirectory: currentWorkingDirectory())
  }

  public func validate(_ request: ExecutionRequest) throws -> String {
    try executeSubjectRequest(request, startDirectory: currentWorkingDirectory())
  }

  private func currentWorkingDirectory() -> URL {
    URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
  }

  private func executeSubjectRequest(_ request: ExecutionRequest, startDirectory: URL) throws -> String {
    guard request.command != .doctor else {
      throw unsupportedSubjectBridgeError(for: request)
    }

    let workspace = try workspaceDiscovery.discover(from: startDirectory)
    let capabilities = try toolchainCapabilitiesResolver.resolve()
    let startedAt = Date()
    let plan = try makeExecutionPlan(
      for: request,
      workspace: workspace,
      capabilities: capabilities,
      startedAt: startedAt
    )
    let summaryPath = plan.sharedRunRoot.appendingPathComponent("summary.txt")
    let sharedRunID = plan.sharedRunRoot.lastPathComponent

    try prepareSharedRunRoot(at: plan.sharedRunRoot)

    let subjectResults = try executePlannedSubjectRuns(
      plan: plan,
      request: request,
      workspace: workspace,
      sharedRunID: sharedRunID
    )
    var aggregateAnomalies = [ArtifactAnomaly]()
    var extraSummaryLines = [String]()
    var firstFailureMessage: String?

    for (index, scheduledRun) in plan.subjectRuns.enumerated() {
      let subjectResult = subjectResults[index]
      aggregateAnomalies.append(
        contentsOf: subjectResult.artifactSet.anomalies.map {
          $0.subject == nil
            ? ArtifactAnomaly(
              code: $0.code,
              message: $0.message,
              phase: $0.phase,
              subject: scheduledRun.subject.name
            ) : $0
        }
      )
      if firstFailureMessage == nil, subjectResult.outcome == .failure {
        firstFailureMessage = "\(request.command.rawValue) failed for \(scheduledRun.subject.name)."
      }
    }

    if isDefaultRepositoryValidate(request) {
      let policyOutcome = try executeRepositoryValidationPolicies(
        request: request,
        workspace: workspace,
        capabilities: capabilities,
        subjectResults: subjectResults
      )
      aggregateAnomalies.append(contentsOf: policyOutcome.anomalies)
      extraSummaryLines.append(contentsOf: policyOutcome.summaryLines)
      if firstFailureMessage == nil {
        firstFailureMessage = policyOutcome.failureMessage
      }
    }

    let endedAt = Date()
    let sharedSummary = SharedRunSummary(
      command: request.command,
      runID: plan.sharedRunRoot.lastPathComponent,
      startedAt: startedAt,
      endedAt: endedAt,
      subjects: plan.subjectRuns.map(\.subject.name),
      subjectResults: subjectResults,
      anomalies: aggregateAnomalies
    )
    try writeSharedRunArtifacts(
      plan: plan,
      request: request,
      summary: sharedSummary,
      startedAt: startedAt,
      endedAt: endedAt,
      extraSummaryLines: extraSummaryLines
    )

    if let firstFailureMessage {
      throw SymphonyHarnessCommandFailure(message: firstFailureMessage, summaryPath: summaryPath)
    }
    return summaryPath.path
  }

  private func executePlannedSubjectRuns(
    plan: ExecutionPlan,
    request: ExecutionRequest,
    workspace: WorkspaceContext,
    sharedRunID: String
  ) throws -> [SubjectRunResult] {
    guard plan.subjectRuns.count > 1, request.command != .validate else {
      return try plan.subjectRuns.enumerated().map { index, scheduledRun in
        try executeScheduledSubjectRun(
          scheduledRun,
          for: request,
          workspace: workspace,
          sharedRunRoot: plan.sharedRunRoot,
          sharedRunID: sharedRunID,
          workerID: index
        )
      }
    }

    let concurrentQueue = DispatchQueue(
      label: "symphony.harness.subject-runs",
      attributes: .concurrent
    )
    let exclusiveQueue = DispatchQueue(label: "symphony.harness.subject-runs.exclusive")
    let group = DispatchGroup()
    let collector = ScheduledRunCollector(count: plan.subjectRuns.count)

    for (index, scheduledRun) in plan.subjectRuns.enumerated() {
      group.enter()
      let queue = scheduledRun.requiresExclusiveDestination ? exclusiveQueue : concurrentQueue
      queue.async { [self] in
        defer { group.leave() }
        let result = try! executeScheduledSubjectRun(
          scheduledRun,
          for: request,
          workspace: workspace,
          sharedRunRoot: plan.sharedRunRoot,
          sharedRunID: sharedRunID,
          workerID: index
        )
        collector.store(result: result, at: index)
      }
    }

    group.wait()

    return try collector.orderedResults()
  }

  private func makeExecutionPlan(
    for request: ExecutionRequest,
    workspace: WorkspaceContext,
    capabilities: ToolchainCapabilities,
    startedAt: Date
  ) throws -> ExecutionPlan {
    let productionSubjects = try request.subjects.map(resolveHarnessSubject(named:))
    let explicitTestSubjects = try request.explicitTestSubjects.map(resolveHarnessSubject(named:))

    for subject in productionSubjects where subject.kind == .test || subject.kind == .uiTest {
      throw unsupportedSubjectBridgeError(forSubject: subject.name)
    }
    for subject in explicitTestSubjects where subject.kind != .test && subject.kind != .uiTest {
      throw unsupportedSubjectBridgeError(forSubject: subject.name)
    }

    let plannedSubjects: [HarnessSubject]
    let defaultedSubjects: [String]

    if request.command == .build {
      guard explicitTestSubjects.isEmpty, !productionSubjects.isEmpty else {
        throw unsupportedSubjectBridgeError(for: request)
      }
      plannedSubjects = uniqueSubjects(productionSubjects)
      defaultedSubjects = []
    } else if request.command == .run {
      guard explicitTestSubjects.isEmpty, productionSubjects.count == 1 else {
        throw unsupportedSubjectBridgeError(for: request)
      }
      plannedSubjects = productionSubjects
      defaultedSubjects = []
    } else {
      if productionSubjects.isEmpty, explicitTestSubjects.isEmpty {
        let defaults = defaultTestProductionSubjects(capabilities: capabilities)
        plannedSubjects = defaults
        defaultedSubjects = defaults.map(\.name)
      } else {
        plannedSubjects = uniqueSubjects(productionSubjects + explicitTestSubjects)
        defaultedSubjects = []
      }
    }
    let validationPolicies: [ValidationPolicy]
    if request.command == .validate {
      validationPolicies = isDefaultRepositoryValidate(request)
        ? [.coverage, .artifacts, .environment, .xcodeTestPlans, .accessibility]
        : [.coverage, .artifacts, .environment]
    } else {
      validationPolicies = []
    }
    let runID = makeSharedRunID(command: request.command, date: startedAt)
    let sharedRunRoot = workspace.buildStateRoot.appendingPathComponent(
      "runs/\(runID)",
      isDirectory: true
    )

    let subjectRuns = plannedSubjects.map { subject in
      ScheduledSubjectRun(
        subject: subject,
        command: request.command,
        schedulerLane: schedulerLane(for: subject),
        requiresExclusiveDestination: subject.requiresExclusiveDestination,
        capabilityOutcome: capabilityOutcome(
          for: subject,
          command: request.command,
          capabilities: capabilities
        )
      )
    }

    return ExecutionPlan(
      subjectRuns: subjectRuns,
      sharedRunRoot: sharedRunRoot,
      defaultedSubjects: defaultedSubjects,
      validationPolicies: validationPolicies
    )
  }

  private func executeScheduledSubjectRun(
    _ scheduledRun: ScheduledSubjectRun,
    for request: ExecutionRequest,
    workspace: WorkspaceContext,
    sharedRunRoot: URL,
    sharedRunID: String,
    workerID: Int
  ) throws -> SubjectRunResult {
    let subject = scheduledRun.subject
    let subjectRoot = sharedRunRoot.appendingPathComponent(
      "subjects/\(subject.name)",
      isDirectory: true
    )

    guard scheduledRun.capabilityOutcome.status == .supported else {
      let skippedOutcome: SubjectRunOutcome =
        scheduledRun.capabilityOutcome.status == .skipped ? .skipped : .unsupported
      var skippedReason = Self.noXcodeMessage
      if let reason = scheduledRun.capabilityOutcome.reason {
        skippedReason = reason
      }
      let artifactSet = try writeSkippedSubjectArtifacts(
        subject: subject,
        command: request.command,
        subjectRoot: subjectRoot,
        outcome: skippedOutcome,
        reason: skippedReason
      )
      return SubjectRunResult(
        subject: subject.name,
        outcome: skippedOutcome,
        artifactSet: artifactSet
      )
    }

    if isDefaultRepositoryValidate(request), subject.name == "SymphonySwiftUIApp" {
      return try executeDefaultAppValidationSuite(
        subject: subject,
        request: request,
        workspace: workspace,
        subjectRoot: subjectRoot,
        sharedRunID: sharedRunID,
        workerID: workerID
      )
    }

    let selection = try selection(for: scheduledRun)
    let executionContext = try makeSubjectExecutionContext(
      workspace: workspace,
      subject: subject,
      command: request.command,
      sharedRunID: sharedRunID,
      workerID: workerID
    )

    do {
      if scheduledRun.command == .build {
        try executeBuildSelection(
          selection,
          request: request,
          workspace: workspace,
          executionContext: executionContext
        )
      } else if scheduledRun.command == .run {
        try executeRunSelection(
          selection,
          request: request,
          workspace: workspace,
          executionContext: executionContext
        )
      } else {
        try executeTestSelection(
          selection,
          request: request,
          workspace: workspace,
          executionContext: executionContext
        )
      }
    } catch let error as SymphonyHarnessCommandFailure {
      let artifactSet = try loadSubjectArtifactSet(subject: subject.name, subjectRoot: subjectRoot)
      _ = error
      return SubjectRunResult(subject: subject.name, outcome: .failure, artifactSet: artifactSet)
    } catch {
      let artifactSet = try writeFailedSubjectArtifacts(
        subject: subject,
        command: request.command,
        subjectRoot: subjectRoot,
        reason: error.localizedDescription
      )
      return SubjectRunResult(subject: subject.name, outcome: .failure, artifactSet: artifactSet)
    }

    let artifactSet = try loadSubjectArtifactSet(subject: subject.name, subjectRoot: subjectRoot)
    return SubjectRunResult(subject: subject.name, outcome: .success, artifactSet: artifactSet)
  }

  private func selection(for scheduledRun: ScheduledSubjectRun) throws -> SubjectExecutionSelection {
    if scheduledRun.command == .build {
      return try buildSelection(for: scheduledRun.subject)
    }
    if scheduledRun.command == .run {
      return try runSelection(for: scheduledRun.subject)
    }
    return try testSelection(
      for: scheduledRun.subject,
      productionSubject: scheduledRun.subject.kind == .test || scheduledRun.subject.kind == .uiTest
        ? nil : scheduledRun.subject
    )
  }

  private func executeBuildSelection(
    _ selection: SubjectExecutionSelection,
    request: ExecutionRequest,
    workspace: WorkspaceContext,
    executionContext: ExecutionContext
  ) throws {
    let selector = SchemeSelector(product: selection.legacyProduct, scheme: selection.scheme, platform: nil)
    switch selection.legacyProduct.defaultBackend {
    case .swiftPM:
      let destination = try simulatorResolver.resolve(
        destinationSelector(platform: selector.platform, simulator: nil)
      )
      _ = try buildSwiftPM(
        request: BuildCommandRequest(
          product: selection.legacyProduct,
          scheme: selection.scheme,
          swiftPMProduct: selection.swiftPMProduct,
          platform: nil,
          simulator: nil,
          workerID: executionContext.worker.id,
          dryRun: false,
          buildForTesting: false,
          outputMode: request.outputMode,
          subjectName: selection.subjectName,
          currentDirectory: workspace.projectRoot
        ),
        workspace: workspace,
        selector: selector,
        destination: destination,
        executionContext: executionContext
      )
    case .xcode:
      try ensureXcodeSupport(for: selector.platform)
      let destination = try xcodeDestination(platform: selector.platform, simulator: nil, dryRun: false)
      _ = try buildXcode(
        request: BuildCommandRequest(
          product: selection.legacyProduct,
          scheme: selection.scheme,
          swiftPMProduct: nil,
          platform: nil,
          simulator: nil,
          workerID: executionContext.worker.id,
          dryRun: false,
          buildForTesting: false,
          outputMode: request.outputMode,
          subjectName: selection.subjectName,
          currentDirectory: workspace.projectRoot
        ),
        workspace: workspace,
        selector: selector,
        destination: destination,
        executionContext: executionContext
      )
    }
  }

  private func executeTestSelection(
    _ selection: SubjectExecutionSelection,
    request: ExecutionRequest,
    workspace: WorkspaceContext,
    executionContext: ExecutionContext
  ) throws {
    let selector = SchemeSelector(product: selection.legacyProduct, scheme: selection.scheme, platform: nil)
    switch selection.legacyProduct.defaultBackend {
    case .swiftPM:
      let destination = try simulatorResolver.resolve(
        destinationSelector(platform: selector.platform, simulator: nil)
      )
      _ = try testSwiftPM(
        request: TestCommandRequest(
          product: selection.legacyProduct,
          scheme: selection.scheme,
          swiftPMTestFilter: selection.swiftPMTestFilter,
          platform: nil,
          simulator: nil,
          workerID: executionContext.worker.id,
          dryRun: false,
          onlyTesting: selection.onlyTesting,
          skipTesting: [],
          outputMode: request.outputMode,
          subjectName: selection.subjectName,
          currentDirectory: workspace.projectRoot
        ),
        workspace: workspace,
        selector: selector,
        destination: destination,
        executionContext: executionContext
      )
    case .xcode:
      try ensureXcodeSupport(for: selector.platform)
      let destination = try xcodeDestination(platform: selector.platform, simulator: nil, dryRun: false)
      _ = try testXcode(
        request: TestCommandRequest(
          product: selection.legacyProduct,
          scheme: selection.scheme,
          swiftPMTestFilter: nil,
          platform: nil,
          simulator: nil,
          workerID: executionContext.worker.id,
          dryRun: false,
          onlyTesting: selection.onlyTesting,
          skipTesting: [],
          outputMode: request.outputMode,
          subjectName: selection.subjectName,
          currentDirectory: workspace.projectRoot
        ),
        workspace: workspace,
        selector: selector,
        destination: destination,
        executionContext: executionContext
      )
    }
  }

  private func executeRunSelection(
    _ selection: SubjectExecutionSelection,
    request: ExecutionRequest,
    workspace: WorkspaceContext,
    executionContext: ExecutionContext
  ) throws {
    let selector = SchemeSelector(product: selection.legacyProduct, scheme: selection.scheme, platform: nil)
    let endpointOverrides = endpointOverrides(from: request.environment)
    let passthroughEnvironment = request.environment.filter { key, _ in
      ![
        "SYMPHONY_SERVER_URL",
        "SYMPHONY_SERVER_SCHEME",
        "SYMPHONY_SERVER_HOST",
        "SYMPHONY_SERVER_PORT",
      ].contains(key)
    }

    switch selection.legacyProduct.defaultBackend {
    case .swiftPM:
      let destination = try simulatorResolver.resolve(
        destinationSelector(platform: selector.platform, simulator: nil)
      )
      _ = try runSwiftPM(
        request: RunCommandRequest(
          product: selection.legacyProduct,
          scheme: selection.scheme,
          swiftPMProduct: selection.swiftPMProduct,
          platform: nil,
          simulator: nil,
          workerID: executionContext.worker.id,
          dryRun: false,
          serverURL: endpointOverrides.serverURL,
          serverScheme: endpointOverrides.scheme,
          host: endpointOverrides.host,
          port: endpointOverrides.port,
          environment: passthroughEnvironment,
          outputMode: request.outputMode,
          subjectName: selection.subjectName,
          currentDirectory: workspace.projectRoot
        ),
        workspace: workspace,
        selector: selector,
        destination: destination,
        executionContext: executionContext
      )
    case .xcode:
      try ensureXcodeSupport(for: selector.platform)
      let destination = try xcodeDestination(platform: selector.platform, simulator: nil, dryRun: false)
      _ = try runXcode(
        request: RunCommandRequest(
          product: selection.legacyProduct,
          scheme: selection.scheme,
          swiftPMProduct: nil,
          platform: nil,
          simulator: nil,
          workerID: executionContext.worker.id,
          dryRun: false,
          serverURL: endpointOverrides.serverURL,
          serverScheme: endpointOverrides.scheme,
          host: endpointOverrides.host,
          port: endpointOverrides.port,
          environment: passthroughEnvironment,
          outputMode: request.outputMode,
          subjectName: selection.subjectName,
          currentDirectory: workspace.projectRoot
        ),
        workspace: workspace,
        selector: selector,
        destination: destination,
        executionContext: executionContext
      )
    }
  }

  private func prepareSharedRunRoot(at sharedRunRoot: URL) throws {
    let fileManager = FileManager.default
    try fileManager.createDirectory(
      at: sharedRunRoot.appendingPathComponent("subjects", isDirectory: true),
      withIntermediateDirectories: true
    )
  }

  private func makeSubjectExecutionContext(
    workspace: WorkspaceContext,
    subject: HarnessSubject,
    command: HarnessCommand,
    sharedRunID: String,
    workerID: Int
  ) throws -> ExecutionContext {
    let worker = try WorkerScope(id: workerID)
    let buildCommand = buildCommandFamily(for: command)
    let timestamp = DateFormatting.runTimestamp(for: Date())
    let subjectSlug = ShellQuoting.slugify(subject.name)
    return ExecutionContext(
      worker: worker,
      timestamp: timestamp,
      runID: "\(sharedRunID)-\(subjectSlug)",
      artifactRoot: workspace.buildStateRoot.appendingPathComponent(
        "runs/\(sharedRunID)/subjects/\(subject.name)",
        isDirectory: true
      ),
      derivedDataPath: workspace.buildStateRoot.appendingPathComponent(
        "derived-data/\(subject.name)",
        isDirectory: true
      ),
      resultBundlePath: workspace.buildStateRoot.appendingPathComponent(
        "results/\(subject.name)/\(buildCommand.rawValue)-\(sharedRunID).xcresult",
        isDirectory: true
      ),
      logPath: workspace.buildStateRoot.appendingPathComponent(
        "logs/\(subject.name)/\(buildCommand.rawValue)-\(sharedRunID).log",
        isDirectory: false
      ),
      runtimeRoot: workspace.buildStateRoot.appendingPathComponent(
        "runtime/\(subject.name)",
        isDirectory: true
      )
    )
  }

  private func writeSharedRunArtifacts(
    plan: ExecutionPlan,
    request: ExecutionRequest,
    summary: SharedRunSummary,
    startedAt: Date,
    endedAt: Date,
    extraSummaryLines: [String]
  ) throws {
    let createdAt = DateFormatting.iso8601(endedAt)
    let summaryPath = plan.sharedRunRoot.appendingPathComponent("summary.txt")
    let summaryJSONPath = plan.sharedRunRoot.appendingPathComponent("summary.json")
    let indexPath = plan.sharedRunRoot.appendingPathComponent("index.json")
    let subjectEntries = summary.subjectResults.map { result in
      ArtifactIndexEntry(
        name: result.subject,
        relativePath: "subjects/\(result.subject)",
        kind: "directory",
        createdAt: createdAt
      )
    }
    let index = SharedRunIndex(
      command: request.command,
      runID: summary.runID,
      startedAt: DateFormatting.iso8601(startedAt),
      endedAt: DateFormatting.iso8601(endedAt),
      entries: [
        ArtifactIndexEntry(
          name: "summary.txt",
          relativePath: "summary.txt",
          kind: "file",
          createdAt: createdAt
        ),
        ArtifactIndexEntry(
          name: "summary.json",
          relativePath: "summary.json",
          kind: "file",
          createdAt: createdAt
        ),
        ArtifactIndexEntry(
          name: "index.json",
          relativePath: "index.json",
          kind: "file",
          createdAt: createdAt
        ),
        ArtifactIndexEntry(
          name: "subjects",
          relativePath: "subjects",
          kind: "directory",
          createdAt: createdAt
        ),
      ] + subjectEntries,
      anomalies: summary.anomalies
    )

    let validationPolicyText =
      plan.validationPolicies.isEmpty
      ? "validation_policies: none"
      : "validation_policies: \(plan.validationPolicies.map(\.rawValue).joined(separator: ", "))"
    let aggregateAnomalyCodes = summary.anomalies.map { anomaly -> String in
      if let subject = anomaly.subject {
        return "\(subject):\(anomaly.code)"
      }
      return anomaly.code
    }
    let aggregateAnomaliesText =
      aggregateAnomalyCodes.isEmpty
      ? "aggregate_anomalies: none"
      : "aggregate_anomalies: \(aggregateAnomalyCodes.joined(separator: ", "))"

    let summaryLines =
      [
        "command: \(request.command.rawValue)",
        "requested_subjects: \((request.subjects + request.explicitTestSubjects).joined(separator: ", "))",
        "defaulted_subjects: \(plan.defaultedSubjects.joined(separator: ", "))",
        "started_at: \(DateFormatting.iso8601(startedAt))",
        "ended_at: \(DateFormatting.iso8601(endedAt))",
        "aggregate_outcome: \(aggregateOutcome(from: summary.subjectResults, anomalies: summary.anomalies))",
        "shared_run_root: \(plan.sharedRunRoot.path)",
        validationPolicyText,
      ]
      + summary.subjectResults.map {
        "subject_artifact_root \($0.subject): \($0.artifactSet.artifactRoot.path)"
      }
      + extraSummaryLines
      + [aggregateAnomaliesText]

    try summaryLines.joined(separator: "\n").write(
      to: summaryPath,
      atomically: true,
      encoding: .utf8
    )
    try (encodePrettyJSON(summary) + "\n").write(
      to: summaryJSONPath,
      atomically: true,
      encoding: .utf8
    )
    try (encodePrettyJSON(index) + "\n").write(
      to: indexPath,
      atomically: true,
      encoding: .utf8
    )
    try artifactManager.updateLatestLink(
      familyRoot: plan.sharedRunRoot.deletingLastPathComponent(),
      target: plan.sharedRunRoot
    )
  }

  private func loadSubjectArtifactSet(subject: String, subjectRoot: URL) throws -> SubjectArtifactSet {
    let coverageTextPath = subjectRoot.appendingPathComponent("coverage.txt")
    let coverageJSONPath = subjectRoot.appendingPathComponent("coverage.json")
    let resultBundlePath = subjectRoot.appendingPathComponent("result.xcresult", isDirectory: true)
    let logPath = subjectRoot.appendingPathComponent("process-stdout-stderr.txt")
    let indexPath = subjectRoot.appendingPathComponent("index.json")
    let anomalies: [ArtifactAnomaly]
    if let artifactIndex = try? artifactManager.loadArtifactIndexIfPresent(at: indexPath) {
      anomalies = artifactIndex.anomalies
    } else {
      var decodedAnomalies = [ArtifactAnomaly]()
      if let data = try? Data(contentsOf: indexPath) {
        if let decodedIndex = try? JSONDecoder().decode(SharedRunIndex.self, from: data) {
          decodedAnomalies = decodedIndex.anomalies
        }
      }
      anomalies = decodedAnomalies
    }

    return SubjectArtifactSet(
      subject: subject,
      artifactRoot: subjectRoot,
      summaryPath: subjectRoot.appendingPathComponent("summary.txt"),
      indexPath: indexPath,
      coverageTextPath: FileManager.default.fileExists(atPath: coverageTextPath.path)
        ? coverageTextPath : nil,
      coverageJSONPath: FileManager.default.fileExists(atPath: coverageJSONPath.path)
        ? coverageJSONPath : nil,
      resultBundlePath: FileManager.default.fileExists(atPath: resultBundlePath.path)
        ? resultBundlePath : nil,
      logPath: logPath,
      anomalies: anomalies
    )
  }

  private func writeSkippedSubjectArtifacts(
    subject: HarnessSubject,
    command: HarnessCommand,
    subjectRoot: URL,
    outcome: SubjectRunOutcome,
    reason: String
  ) throws -> SubjectArtifactSet {
    try writeSyntheticSubjectArtifacts(
      subject: subject,
      command: command,
      subjectRoot: subjectRoot,
      outcome: outcome,
      reason: reason,
      anomalyCode: outcome == .unsupported ? "unsupported_subject_execution" : "skipped_subject_execution"
    )
  }

  private func writeFailedSubjectArtifacts(
    subject: HarnessSubject,
    command: HarnessCommand,
    subjectRoot: URL,
    reason: String
  ) throws -> SubjectArtifactSet {
    try writeSyntheticSubjectArtifacts(
      subject: subject,
      command: command,
      subjectRoot: subjectRoot,
      outcome: .failure,
      reason: reason,
      anomalyCode: "subject_execution_failed"
    )
  }

  private func writeSyntheticSubjectArtifacts(
    subject: HarnessSubject,
    command: HarnessCommand,
    subjectRoot: URL,
    outcome: SubjectRunOutcome,
    reason: String,
    anomalyCode: String
  ) throws -> SubjectArtifactSet {
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: subjectRoot, withIntermediateDirectories: true)

    let anomaly = ArtifactAnomaly(
      code: anomalyCode,
      message: reason,
      phase: command.rawValue,
      subject: subject.name
    )
    let createdAt = DateFormatting.iso8601(Date())
    let processLogPath = subjectRoot.appendingPathComponent("process-stdout-stderr.txt")
    let summaryPath = subjectRoot.appendingPathComponent("summary.txt")
    let summaryJSONPath = subjectRoot.appendingPathComponent("summary.json")
    let indexPath = subjectRoot.appendingPathComponent("index.json")

    try reason.write(to: processLogPath, atomically: true, encoding: .utf8)
    try [
      "command: \(command.rawValue)",
      "subject: \(subject.name)",
      "outcome: \(outcome.rawValue)",
      "artifact_root: \(subjectRoot.path)",
      "reason: \(reason)",
    ].joined(separator: "\n").write(
      to: summaryPath,
      atomically: true,
      encoding: .utf8
    )
    try (encodePrettyJSON(
      SyntheticSubjectSummary(
        command: command,
        subject: subject.name,
        outcome: outcome,
        artifactRoot: subjectRoot.path,
        reason: reason
      )
    ) + "\n").write(
      to: summaryJSONPath,
      atomically: true,
      encoding: .utf8
    )
    try (encodePrettyJSON(
      SharedRunIndex(
        command: command,
        runID: subject.name,
        startedAt: createdAt,
        endedAt: createdAt,
        entries: [
          ArtifactIndexEntry(
            name: "summary.txt",
            relativePath: "summary.txt",
            kind: "file",
            createdAt: createdAt
          ),
          ArtifactIndexEntry(
            name: "summary.json",
            relativePath: "summary.json",
            kind: "file",
            createdAt: createdAt
          ),
          ArtifactIndexEntry(
            name: "index.json",
            relativePath: "index.json",
            kind: "file",
            createdAt: createdAt
          ),
          ArtifactIndexEntry(
            name: "process-stdout-stderr.txt",
            relativePath: "process-stdout-stderr.txt",
            kind: "file",
            createdAt: createdAt
          ),
        ],
        anomalies: [anomaly]
      )
    ) + "\n").write(
      to: indexPath,
      atomically: true,
      encoding: .utf8
    )

    return SubjectArtifactSet(
      subject: subject.name,
      artifactRoot: subjectRoot,
      summaryPath: summaryPath,
      indexPath: indexPath,
      coverageTextPath: nil,
      coverageJSONPath: nil,
      resultBundlePath: nil,
      logPath: processLogPath,
      anomalies: [anomaly]
    )
  }

  private func executeRepositoryValidationPolicies(
    request: ExecutionRequest,
    workspace: WorkspaceContext,
    capabilities: ToolchainCapabilities,
    subjectResults: [SubjectRunResult]
  ) throws -> RepositoryValidationOutcome {
    var summaryLines = [String]()
    var anomalies = [ArtifactAnomaly]()
    var failureMessage: String?

    do {
      let report = try doctorService.makeReport(
        from: DoctorCommandRequest(
          strict: false,
          json: false,
          quiet: true,
          currentDirectory: workspace.projectRoot
        )
      )
      var errorIssues = [DiagnosticIssue]()
      for issue in report.issues where issue.severity == .error {
        errorIssues.append(issue)
      }
      if !errorIssues.isEmpty {
        var renderedIssues = [String]()
        for issue in errorIssues {
          renderedIssues.append("[\(issue.code)] \(issue.message)")
        }
        let issueText = renderedIssues.joined(separator: "; ")
        summaryLines.append("validation_policy_result environment: failure")
        summaryLines.append("validation_policy_detail environment: \(issueText)")
        anomalies.append(
          ArtifactAnomaly(
            code: "environment_policy_failed",
            message: issueText,
            phase: "validate-policy"
          )
        )
        if failureMessage == nil {
          failureMessage = "validate failed for repository environment policies."
        }
      } else {
        summaryLines.append("validation_policy_result environment: success")
      }
    } catch {
      summaryLines.append("validation_policy_result environment: failure")
      summaryLines.append("validation_policy_detail environment: \(error.localizedDescription)")
      anomalies.append(
        ArtifactAnomaly(
          code: "environment_policy_failed",
          message: error.localizedDescription,
          phase: "validate-policy"
        )
      )
      if failureMessage == nil {
        failureMessage = "validate failed for repository environment policies."
      }
    }

    do {
      let execution = try commitHarness.execute(
        workspace: workspace,
        request: HarnessCommandRequest(
          minimumCoveragePercent: 100,
          json: false,
          outputMode: request.outputMode,
          currentDirectory: workspace.projectRoot
        )
      )
      if execution.report.meetsCoverageThreshold {
        summaryLines.append("validation_policy_result coverage: success")
      } else {
        summaryLines.append("validation_policy_result coverage: failure")
        anomalies.append(
          ArtifactAnomaly(
            code: "coverage_policy_failed",
            message: commitHarness.renderHuman(report: execution.report),
            phase: "validate-policy"
          )
        )
        if failureMessage == nil {
          failureMessage = "validate failed for repository coverage policies."
        }
      }
    } catch {
      summaryLines.append("validation_policy_result coverage: failure")
      anomalies.append(
        ArtifactAnomaly(
          code: "coverage_policy_failed",
          message: error.localizedDescription,
          phase: "validate-policy"
        )
      )
      if failureMessage == nil {
        failureMessage = "validate failed for repository coverage policies."
      }
    }

    let artifactPolicyOutcome = Self.artifactValidationPolicyOutcome(for: subjectResults)
    summaryLines.append(contentsOf: artifactPolicyOutcome.summaryLines)
    anomalies.append(contentsOf: artifactPolicyOutcome.anomalies)
    if failureMessage == nil {
      failureMessage = artifactPolicyOutcome.failureMessage
    }

    if capabilities.supportsSimulatorCommands {
      let appPolicyOutcome = Self.defaultAppValidationPolicyOutcome(
        subjectResults: subjectResults,
        supportsSimulatorCommands: true,
        buildStateRoot: workspace.buildStateRoot
      )
      summaryLines.append(contentsOf: appPolicyOutcome.summaryLines)
      anomalies.append(contentsOf: appPolicyOutcome.anomalies)
      if failureMessage == nil {
        failureMessage = appPolicyOutcome.failureMessage
      }
    } else {
      let appPolicyOutcome = Self.defaultAppValidationPolicyOutcome(
        subjectResults: subjectResults,
        supportsSimulatorCommands: false,
        buildStateRoot: workspace.buildStateRoot
      )
      summaryLines.append(contentsOf: appPolicyOutcome.summaryLines)
      anomalies.append(contentsOf: appPolicyOutcome.anomalies)
    }

    return RepositoryValidationOutcome(
      summaryLines: summaryLines,
      anomalies: anomalies,
      failureMessage: failureMessage
    )
  }

  private func executeDefaultAppValidationSuite(
    subject: HarnessSubject,
    request: ExecutionRequest,
    workspace: WorkspaceContext,
    subjectRoot: URL,
    sharedRunID: String,
    workerID: Int
  ) throws -> SubjectRunResult {
    do {
      var testPlans = [ValidationPlanMetadata]()
      for testPlanURL in checkedInTestPlans(in: workspace) {
        testPlans.append(makeValidationPlanMetadata(for: testPlanURL))
      }
      guard !testPlans.isEmpty else {
        let artifactSet = try writeFailedSubjectArtifacts(
          subject: subject,
          command: .validate,
          subjectRoot: subjectRoot,
          reason: "No checked-in .xctestplan files were found for default app validation."
        )
        return SubjectRunResult(subject: subject.name, outcome: .failure, artifactSet: artifactSet)
      }

      let destinations = try simulatorResolver.approvedValidationDestinations()
      let fileManager = FileManager.default
      try fileManager.createDirectory(at: subjectRoot, withIntermediateDirectories: true)

      var planResults = [ValidationPlanResult]()
      var combinedLogs = [String]()
      var subjectAnomalies = [ArtifactAnomaly]()
      var createdEntries = [ArtifactIndexEntry]()

      for testPlanURL in testPlans {
        let testPlan = testPlanURL.name
        for destination in destinations {
          var destinationLabel = destination.displayName
          if let simulatorName = destination.simulatorName {
            destinationLabel = simulatorName
          }
          let planSlug = ShellQuoting.slugify("\(testPlan)-\(destinationLabel)")
          let planRoot = subjectRoot.appendingPathComponent("plans/\(planSlug)", isDirectory: true)
          let executionContext = try makeValidationPlanExecutionContext(
            workspace: workspace,
            subject: subject,
            testPlan: testPlan,
            destination: destination,
            sharedRunID: sharedRunID,
            workerID: workerID,
            artifactRoot: planRoot
          )
          let xcodeRequest = XcodeCommandRequest(
            action: .test,
            scheme: subject.name,
            destination: destination,
            derivedDataPath: executionContext.derivedDataPath,
            resultBundlePath: executionContext.resultBundlePath,
            enableCodeCoverage: false,
            outputMode: request.outputMode,
            environment: [:],
            workspacePath: workspace.xcodeWorkspacePath,
            projectPath: workspace.xcodeProjectPath,
            testPlan: testPlan
          )
          let startedAt = Date()
          let result = try runValidationPlanRequest(
            xcodeRequest,
            request: request,
            workspace: workspace,
            scheme: subject.name,
            testPlan: testPlan,
            destination: destination,
            executionContext: executionContext
          )
          let endedAt = Date()
          let record = try artifactManager.recordXcodeExecution(
            workspace: workspace,
            executionContext: executionContext,
            command: .test,
            product: .client,
            scheme: subject.name,
            destination: destination,
            invocation: try xcodeRequest.renderedCommandLine(),
            exitStatus: result.exitStatus,
            combinedOutput: result.combinedOutput,
            startedAt: startedAt,
            endedAt: endedAt,
            subjectName: subject.name
          )
          var anomalies = [ArtifactAnomaly]()
          if let artifactIndex = try artifactManager.loadArtifactIndexIfPresent(at: record.run.indexPath) {
            anomalies = artifactIndex.anomalies
          }
          subjectAnomalies.append(contentsOf: anomalies)
          let planOutcome: SubjectRunOutcome = result.exitStatus == 0 ? .success : .failure
          planResults.append(
            ValidationPlanResult(
              plan: testPlan,
              destination: destination.displayName,
              outcome: planOutcome,
              artifactRoot: planRoot.path,
              includesAccessibilityCoverage: testPlanURL.includesAccessibilityCoverage
            )
          )
          combinedLogs.append(
            "plan \(testPlan) destination \(destination.displayName) outcome \(planOutcome.rawValue) summary \(record.run.summaryPath.path)"
          )
          createdEntries.append(
            ArtifactIndexEntry(
              name: planSlug,
              relativePath: "plans/\(planSlug)",
              kind: "directory",
              createdAt: DateFormatting.iso8601(endedAt)
            )
          )
        }
      }

      let processLogPath = subjectRoot.appendingPathComponent("process-stdout-stderr.txt")
      let summaryPath = subjectRoot.appendingPathComponent("summary.txt")
      let summaryJSONPath = subjectRoot.appendingPathComponent("summary.json")
      let indexPath = subjectRoot.appendingPathComponent("index.json")
      let createdAt = DateFormatting.iso8601(Date())
      var hasPlanFailure = false
      var includesAccessibilityCoverage = false
      var hasAccessibilityCoverageFailure = false
      for planResult in planResults {
        if planResult.outcome == .failure {
          hasPlanFailure = true
        }
        if planResult.includesAccessibilityCoverage {
          includesAccessibilityCoverage = true
          if planResult.outcome == .failure {
            hasAccessibilityCoverageFailure = true
          }
        }
      }
      if hasPlanFailure {
        subjectAnomalies.append(
          ArtifactAnomaly(
            code: "xcode_test_plan_execution_failed",
            message: "One or more required Xcode validation plans failed.",
            phase: "validate"
          )
        )
      }
      if !includesAccessibilityCoverage {
        subjectAnomalies.append(
          ArtifactAnomaly(
            code: "missing_accessibility_validation_plan",
            message: "No checked-in validation plan covered the required UI accessibility suite.",
            phase: "validate"
          )
        )
      } else if hasAccessibilityCoverageFailure {
        subjectAnomalies.append(
          ArtifactAnomaly(
            code: "accessibility_validation_plan_failed",
            message: "One or more required accessibility validation plans failed.",
            phase: "validate"
          )
        )
      }
      let outcome: SubjectRunOutcome
      var hasValidationFailure = false
      for anomaly in subjectAnomalies {
        if anomaly.code == "xcode_test_plan_execution_failed"
          || anomaly.code == "missing_accessibility_validation_plan"
          || anomaly.code == "accessibility_validation_plan_failed"
        {
          hasValidationFailure = true
          break
        }
      }
      if hasValidationFailure {
        outcome = .failure
      } else {
        outcome = .success
      }
      let subjectSummary = AggregatedValidationSubjectSummary(
        command: .validate,
        subject: subject.name,
        outcome: outcome,
        plans: planResults,
        artifactRoot: subjectRoot.path
      )

      try fileManager.createDirectory(
        at: subjectRoot.appendingPathComponent("plans", isDirectory: true),
        withIntermediateDirectories: true
      )
      try combinedLogs.joined(separator: "\n").write(
        to: processLogPath,
        atomically: true,
        encoding: .utf8
      )
      var summaryLines = [
        "command: validate",
        "subject: \(subject.name)",
        "outcome: \(outcome.rawValue)",
        "artifact_root: \(subjectRoot.path)",
      ]
      for planResult in planResults {
        summaryLines.append(
          "plan \(planResult.plan) destination \(planResult.destination) outcome \(planResult.outcome.rawValue)"
        )
      }
      try summaryLines.joined(separator: "\n").write(
        to: summaryPath,
        atomically: true,
        encoding: .utf8
      )
      try (encodePrettyJSON(subjectSummary) + "\n").write(
        to: summaryJSONPath,
        atomically: true,
        encoding: .utf8
      )
      try (encodePrettyJSON(
        SharedRunIndex(
          command: .validate,
          runID: subject.name,
          startedAt: createdAt,
          endedAt: createdAt,
          entries: [
            ArtifactIndexEntry(
              name: "summary.txt",
              relativePath: "summary.txt",
              kind: "file",
              createdAt: createdAt
            ),
            ArtifactIndexEntry(
              name: "summary.json",
              relativePath: "summary.json",
              kind: "file",
              createdAt: createdAt
            ),
            ArtifactIndexEntry(
              name: "index.json",
              relativePath: "index.json",
              kind: "file",
              createdAt: createdAt
            ),
            ArtifactIndexEntry(
              name: "process-stdout-stderr.txt",
              relativePath: "process-stdout-stderr.txt",
              kind: "file",
              createdAt: createdAt
            ),
            ArtifactIndexEntry(
              name: "plans",
              relativePath: "plans",
              kind: "directory",
              createdAt: createdAt
            ),
          ] + createdEntries,
          anomalies: subjectAnomalies
        )
      ) + "\n").write(
        to: indexPath,
        atomically: true,
        encoding: .utf8
      )

      let artifactSet = try loadSubjectArtifactSet(subject: subject.name, subjectRoot: subjectRoot)
      return SubjectRunResult(subject: subject.name, outcome: outcome, artifactSet: artifactSet)
    } catch {
      let artifactSet = try writeFailedSubjectArtifacts(
        subject: subject,
        command: .validate,
        subjectRoot: subjectRoot,
        reason: error.localizedDescription
      )
      return SubjectRunResult(subject: subject.name, outcome: .failure, artifactSet: artifactSet)
    }
  }

  private func makeValidationPlanExecutionContext(
    workspace: WorkspaceContext,
    subject: HarnessSubject,
    testPlan: String,
    destination: ResolvedDestination,
    sharedRunID: String,
    workerID: Int,
    artifactRoot: URL
  ) throws -> ExecutionContext {
    let worker = try WorkerScope(id: workerID)
    var destinationLabel = destination.displayName
    if let simulatorName = destination.simulatorName {
      destinationLabel = simulatorName
    }
    let destinationSlug = ShellQuoting.slugify("\(testPlan)-\(destinationLabel)")
    let planSlug = ShellQuoting.slugify(testPlan)
    return ExecutionContext(
      worker: worker,
      timestamp: DateFormatting.runTimestamp(for: Date()),
      runID: "\(sharedRunID)-\(destinationSlug)",
      artifactRoot: artifactRoot,
      derivedDataPath: workspace.buildStateRoot.appendingPathComponent(
        "derived-data/\(subject.name)/\(planSlug)",
        isDirectory: true
      ),
      resultBundlePath: workspace.buildStateRoot.appendingPathComponent(
        "results/\(subject.name)/\(destinationSlug).xcresult",
        isDirectory: true
      ),
      logPath: workspace.buildStateRoot.appendingPathComponent(
        "logs/\(subject.name)/\(destinationSlug).log",
        isDirectory: false
      ),
      runtimeRoot: workspace.buildStateRoot.appendingPathComponent(
        "runtime/\(subject.name)",
        isDirectory: true
      )
    )
  }

  private func runValidationPlanRequest(
    _ xcodeRequest: XcodeCommandRequest,
    request: ExecutionRequest,
    workspace: WorkspaceContext,
    scheme: String,
    testPlan: String,
    destination: ResolvedDestination,
    executionContext: ExecutionContext
  ) throws -> CommandResult {
    func executeValidationAttempt(resetBeforeRun: Bool) throws -> CommandResult {
      try prepareXcodeExecutionContext(executionContext)
      if resetBeforeRun {
        resetSimulatorForValidationRetry(workspace: workspace, destination: destination)
      }
      try prepareSimulatorForValidationPlan(
        workspace: workspace,
        scheme: scheme,
        destination: destination,
        executionContext: executionContext
      )

      let reporter = XcodeOutputReporter(mode: request.outputMode, sink: statusSink)
      defer { reporter.finish() }
      return try processRunner.run(
        command: "xcodebuild",
        arguments: try xcodeRequest.renderedArguments(),
        environment: [:],
        currentDirectory: workspace.projectRoot,
        observation: reporter.makeObservation(label: "xcodebuild validate \(testPlan)")
      )
    }

    let firstResult = try executeValidationAttempt(resetBeforeRun: false)
    if firstResult.exitStatus == 0
      || !isRetryableValidationLaunchFailure(firstResult.combinedOutput)
    {
      return firstResult
    }

    statusSink(
      "[harness] retrying xcodebuild validate \(testPlan) on \(destination.displayName) after simulator preflight busy failure"
    )
    return try executeValidationAttempt(resetBeforeRun: true)
  }

  private func prepareXcodeExecutionContext(_ executionContext: ExecutionContext) throws {
    let fileManager = FileManager.default
    try fileManager.createDirectory(
      at: executionContext.resultBundlePath.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try fileManager.createDirectory(
      at: executionContext.logPath.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try fileManager.createDirectory(
      at: executionContext.derivedDataPath,
      withIntermediateDirectories: true
    )

    if fileManager.fileExists(atPath: executionContext.resultBundlePath.path) {
      try fileManager.removeItem(at: executionContext.resultBundlePath)
    }
  }

  private func resetSimulatorForValidationRetry(
    workspace: WorkspaceContext,
    destination: ResolvedDestination
  ) {
    if let simulatorUDID = destination.simulatorUDID {
      _ = try? processRunner.run(
        command: "xcrun",
        arguments: ["simctl", "shutdown", simulatorUDID],
        environment: [:],
        currentDirectory: workspace.projectRoot,
        observation: ProcessObservation(label: "simctl shutdown validation simulator")
      )
    }
  }

  private func prepareSimulatorForValidationPlan(
    workspace: WorkspaceContext,
    scheme: String,
    destination: ResolvedDestination,
    executionContext: ExecutionContext
  ) throws {
    if let simulatorUDID = destination.simulatorUDID {
      let bundleIdentifiers = validationBundleIdentifiers(
        in: workspace,
        scheme: scheme,
        destination: destination,
        derivedDataPath: executionContext.derivedDataPath
      )
      guard !bundleIdentifiers.isEmpty else {
        return
      }

      for bundleIdentifier in bundleIdentifiers {
        _ = try processRunner.run(
          command: "xcrun",
          arguments: ["simctl", "terminate", simulatorUDID, bundleIdentifier],
          environment: [:],
          currentDirectory: workspace.projectRoot,
          observation: ProcessObservation(label: "simctl terminate validation app")
        )
        _ = try processRunner.run(
          command: "xcrun",
          arguments: ["simctl", "uninstall", simulatorUDID, bundleIdentifier],
          environment: [:],
          currentDirectory: workspace.projectRoot,
          observation: ProcessObservation(label: "simctl uninstall validation app")
        )
      }
    }
  }

  private func validationBundleIdentifiers(
    in workspace: WorkspaceContext,
    scheme: String,
    destination: ResolvedDestination,
    derivedDataPath: URL
  ) -> [String] {
    var bundleIdentifiers = Set(bundleIdentifiersDeclaredInProject(in: workspace))

    if
      let productDetails = try? productLocator.locateProduct(
        workspace: workspace,
        scheme: scheme,
        destination: destination,
        derivedDataPath: derivedDataPath
      ),
      let bundleIdentifier = productDetails.bundleIdentifier,
      !bundleIdentifier.isEmpty
    {
      bundleIdentifiers.insert(bundleIdentifier)
    }

    for bundleIdentifier in bundleIdentifiers where bundleIdentifier.hasSuffix(".tests")
      || bundleIdentifier.hasSuffix(".uitests")
    {
      bundleIdentifiers.insert("\(bundleIdentifier).xctrunner")
    }

    return bundleIdentifiers.sorted()
  }

  private func bundleIdentifiersDeclaredInProject(in workspace: WorkspaceContext) -> [String] {
    let projectRoot =
      workspace.xcodeProjectPath
      ?? workspace.projectRoot.appendingPathComponent("SymphonyApps.xcodeproj", isDirectory: true)
    let projectFile = projectRoot.appendingPathComponent("project.pbxproj", isDirectory: false)
    guard let contents = try? String(contentsOf: projectFile, encoding: .utf8) else {
      return []
    }

    let regex = try! NSRegularExpression(
      pattern: #"PRODUCT_BUNDLE_IDENTIFIER = ([A-Za-z0-9._-]+);"#
    )
    let contentsRange = NSRange(contents.startIndex..., in: contents)
    let matches = regex.matches(in: contents, range: contentsRange)
    var identifiers = [String]()
    for match in matches {
      if let range = Range(match.range(at: 1), in: contents) {
        identifiers.append(String(contents[range]))
      }
    }

    return Array(Set(identifiers)).sorted()
  }

  private func isRetryableValidationLaunchFailure(_ output: String) -> Bool {
    output.contains("Application failed preflight checks")
      || output.contains("reason: Busy")
      || output.contains("BSErrorCodeDescription=Busy")
  }

  private func checkedInTestPlans(in workspace: WorkspaceContext) -> [URL] {
    let projectRoot =
      workspace.xcodeProjectPath
      ?? workspace.projectRoot.appendingPathComponent("SymphonyApps.xcodeproj", isDirectory: true)
    let root = projectRoot.appendingPathComponent("xcshareddata/xctestplans", isDirectory: true)
    guard let urls = try? FileManager.default.contentsOfDirectory(
      at: root,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    ) else {
      return []
    }
    return urls.filter { $0.pathExtension == "xctestplan" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
  }

  private func makeValidationPlanMetadata(for url: URL) -> ValidationPlanMetadata {
    let fallbackTargetNames = [url.deletingPathExtension().lastPathComponent]
    let planTargetNames =
      (try? Data(contentsOf: url))
      .flatMap { data in
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
      }
      .flatMap { root -> [String]? in
        let targets = root["testTargets"] as? [[String: Any]] ?? []
        let names = targets.compactMap { target -> String? in
          (target["target"] as? [String: Any])?["name"] as? String
        }
        return names.isEmpty ? nil : names
      } ?? fallbackTargetNames
    let lowercasedNames = planTargetNames.map { $0.lowercased() }
    return ValidationPlanMetadata(
      name: url.deletingPathExtension().lastPathComponent,
      includesAccessibilityCoverage: lowercasedNames.contains { $0.contains("uitests") }
    )
  }

  private func defaultTestProductionSubjects(capabilities: ToolchainCapabilities) -> [HarnessSubject] {
    HarnessSubjects.production.filter { subject in
      !subject.requiresXcode || capabilityOutcome(for: subject, command: .test, capabilities: capabilities).status == .supported
    }
  }

  private func capabilityOutcome(
    for subject: HarnessSubject,
    command _: HarnessCommand,
    capabilities: ToolchainCapabilities
  ) -> CapabilityOutcome {
    guard subject.requiresXcode else {
      return CapabilityOutcome(status: .supported)
    }
    guard capabilities.supportsSimulatorCommands else {
      return CapabilityOutcome(status: .unsupported, reason: Self.noXcodeMessage)
    }
    return CapabilityOutcome(status: .supported)
  }

  private func schedulerLane(for subject: HarnessSubject) -> String {
    if subject.requiresExclusiveDestination {
      return "xcode-exclusive"
    }
    return "\(subject.buildSystem.rawValue)-default"
  }

  private func uniqueSubjects(_ subjects: [HarnessSubject]) -> [HarnessSubject] {
    var seen = Set<String>()
    return subjects.filter { subject in
      seen.insert(subject.name).inserted
    }
  }

  private func buildCommandFamily(for command: HarnessCommand) -> BuildCommandFamily {
    if command == .build {
      return .build
    }
    if command == .run {
      return .run
    }
    return .test
  }

  private func makeSharedRunID(command: HarnessCommand, date: Date) -> String {
    "\(DateFormatting.runTimestamp(for: date))-\(command.rawValue)-\(UUID().uuidString.lowercased())"
  }

  private func aggregateOutcome(from subjectResults: [SubjectRunResult], anomalies: [ArtifactAnomaly]) -> String {
    let hardFailureCodes: Set<String> = [
      "coverage_policy_failed",
      "environment_policy_failed",
      "artifact_policy_failed",
      "xcode_test_plans_failed",
      "accessibility_validation_failed",
    ]
    if subjectResults.contains(where: { $0.outcome == .failure }) {
      return "failure"
    }
    if anomalies.contains(where: { hardFailureCodes.contains($0.code) }) {
      return "failure"
    }
    if subjectResults.contains(where: { $0.outcome == .unsupported || $0.outcome == .skipped }) {
      return "partial"
    }
    if anomalies.contains(where: { $0.code.hasPrefix("skipped_") }) {
      return "partial"
    }
    return "success"
  }

  private func isDefaultRepositoryValidate(_ request: ExecutionRequest) -> Bool {
    request.command == .validate
      && request.subjects.isEmpty
      && request.explicitTestSubjects.isEmpty
  }

  private func buildSelection(for subject: HarnessSubject) throws -> SubjectExecutionSelection {
    switch subject.buildSystem {
    case .swiftpm:
      return SubjectExecutionSelection(
        legacyProduct: .server,
        subjectName: subject.name,
        scheme: subject.name,
        swiftPMProduct: swiftPMProduct(for: subject),
        swiftPMTestFilter: nil,
        onlyTesting: []
      )
    case .xcode:
      return SubjectExecutionSelection(
        legacyProduct: .client,
        subjectName: subject.name,
        scheme: subject.name,
        swiftPMProduct: nil,
        swiftPMTestFilter: nil,
        onlyTesting: []
      )
    }
  }

  private func testSelection(
    for subject: HarnessSubject,
    productionSubject: HarnessSubject?
  ) throws -> SubjectExecutionSelection {
    switch subject.buildSystem {
    case .swiftpm:
      let filter: String
      if subject.kind == .test || subject.kind == .uiTest {
        filter = subject.name
      } else {
        var defaultFilter = subject.name
        if let defaultTestCompanion = subject.defaultTestCompanion {
          defaultFilter = defaultTestCompanion
        }
        filter = defaultFilter
      }
      return SubjectExecutionSelection(
        legacyProduct: .server,
        subjectName: subject.name,
        scheme: productionSubject?.name ?? subject.name,
        swiftPMProduct: nil,
        swiftPMTestFilter: filter,
        onlyTesting: []
      )

    case .xcode:
      let scheme = productionSubject?.name ?? "SymphonySwiftUIApp"
      let onlyTesting: [String]
      if subject.kind == .test || subject.kind == .uiTest {
        onlyTesting = [subject.name]
      } else {
        var selectedTests = [String]()
        if let defaultTestCompanion = subject.defaultTestCompanion {
          selectedTests = [defaultTestCompanion]
        }
        onlyTesting = selectedTests
      }
      return SubjectExecutionSelection(
        legacyProduct: .client,
        subjectName: subject.name,
        scheme: scheme,
        swiftPMProduct: nil,
        swiftPMTestFilter: nil,
        onlyTesting: onlyTesting
      )
    }
  }

  private func runSelection(for subject: HarnessSubject) throws -> SubjectExecutionSelection {
    guard HarnessSubjects.runnableSubjectNames.contains(subject.name) else {
      throw unsupportedSubjectBridgeError(forSubject: subject.name)
    }

    switch subject.buildSystem {
    case .swiftpm:
      return SubjectExecutionSelection(
        legacyProduct: .server,
        subjectName: subject.name,
        scheme: subject.name,
        swiftPMProduct: swiftPMProduct(for: subject),
        swiftPMTestFilter: nil,
        onlyTesting: []
      )
    case .xcode:
      return SubjectExecutionSelection(
        legacyProduct: .client,
        subjectName: subject.name,
        scheme: subject.name,
        swiftPMProduct: nil,
        swiftPMTestFilter: nil,
        onlyTesting: []
      )
    }
  }

  private func resolveHarnessSubject(named name: String) throws -> HarnessSubject {
    guard let subject = HarnessSubjects.subject(named: name) else {
      throw unsupportedSubjectBridgeError(forSubject: name)
    }
    return subject
  }

  private func swiftPMProduct(for subject: HarnessSubject) -> String {
    switch subject.name {
    case "SymphonyServerCLI":
      return "symphony-server"
    case "SymphonyHarnessCLI":
      return "harness"
    default:
      return subject.name
    }
  }

  private func endpointOverrides(from environment: [String: String]) -> (
    serverURL: String?, scheme: String?, host: String?, port: Int?
  ) {
    let port: Int?
    if let rawPort = environment["SYMPHONY_SERVER_PORT"] {
      port = Int(rawPort)
    } else {
      port = nil
    }
    return (
      serverURL: environment["SYMPHONY_SERVER_URL"],
      scheme: environment["SYMPHONY_SERVER_SCHEME"],
      host: environment["SYMPHONY_SERVER_HOST"],
      port: port
    )
  }

  static func artifactValidationPolicyOutcome(
    for subjectResults: [SubjectRunResult]
  ) -> (summaryLines: [String], anomalies: [ArtifactAnomaly], failureMessage: String?) {
    let fileManager = FileManager.default
    let artifactPolicyFailed = subjectResults.contains { result in
      !fileManager.fileExists(atPath: result.artifactSet.summaryPath.path)
        || !fileManager.fileExists(atPath: result.artifactSet.indexPath.path)
        || !fileManager.fileExists(atPath: result.artifactSet.logPath.path)
    }
    guard artifactPolicyFailed else {
      return (["validation_policy_result artifacts: success"], [], nil)
    }
    return (
      ["validation_policy_result artifacts: failure"],
      [
        ArtifactAnomaly(
          code: "artifact_policy_failed",
          message: "One or more subject runs did not materialize the required canonical artifact files.",
          phase: "validate-policy"
        )
      ],
      "validate failed for repository artifact policies."
    )
  }

  static func defaultAppValidationPolicyOutcome(
    subjectResults: [SubjectRunResult],
    supportsSimulatorCommands: Bool,
    buildStateRoot: URL
  ) -> (summaryLines: [String], anomalies: [ArtifactAnomaly], failureMessage: String?) {
    guard supportsSimulatorCommands else {
      return (
        [
          "validation_policy_result xcodeTestPlans: skipped",
          "validation_policy_result accessibility: skipped",
        ],
        [
          ArtifactAnomaly(
            code: "skipped_xcode_test_plans",
            message: Self.noXcodeMessage,
            phase: "validate-policy"
          ),
          ArtifactAnomaly(
            code: "skipped_accessibility_validation",
            message: Self.noXcodeMessage,
            phase: "validate-policy"
          ),
        ],
        nil
      )
    }

    var appResult: SubjectRunResult?
    for subjectResult in subjectResults where subjectResult.subject == "SymphonySwiftUIApp" {
      appResult = subjectResult
      break
    }
    if appResult == nil {
      appResult = SubjectRunResult(
        subject: "SymphonySwiftUIApp",
        outcome: .failure,
        artifactSet: SubjectArtifactSet(
          subject: "SymphonySwiftUIApp",
          artifactRoot: buildStateRoot,
          summaryPath: buildStateRoot.appendingPathComponent("missing-summary.txt"),
          indexPath: buildStateRoot.appendingPathComponent("missing-index.json"),
          coverageTextPath: nil,
          coverageJSONPath: nil,
          resultBundlePath: nil,
          logPath: buildStateRoot.appendingPathComponent("missing-log.txt"),
          anomalies: []
        )
      )
    }
    let resolvedAppResult = appResult!
    var accessibilityPlanFailed = false
    var xcodePlanFailed = false
    for anomaly in resolvedAppResult.artifactSet.anomalies {
      if anomaly.code == "accessibility_validation_plan_failed"
        || anomaly.code == "missing_accessibility_validation_plan"
      {
        accessibilityPlanFailed = true
      }
      if anomaly.code == "xcode_test_plan_execution_failed" {
        xcodePlanFailed = true
      }
    }
    if resolvedAppResult.outcome == .failure && !accessibilityPlanFailed {
      xcodePlanFailed = true
    }
    if resolvedAppResult.outcome == .success {
      return (
        [
          "validation_policy_result xcodeTestPlans: success",
          "validation_policy_result accessibility: success",
        ],
        [],
        nil
      )
    }

    var summaryLines = [String]()
    var anomalies = [ArtifactAnomaly]()
    var failureMessage: String?
    if xcodePlanFailed {
      summaryLines.append("validation_policy_result xcodeTestPlans: failure")
      anomalies.append(
        ArtifactAnomaly(
          code: "xcode_test_plans_failed",
          message: "The default app validation plan set failed.",
          phase: "validate-policy"
        )
      )
      failureMessage = "validate failed for required app validation plans."
    } else {
      summaryLines.append("validation_policy_result xcodeTestPlans: success")
    }
    if accessibilityPlanFailed {
      summaryLines.append("validation_policy_result accessibility: failure")
      anomalies.append(
        ArtifactAnomaly(
          code: "accessibility_validation_failed",
          message: "The required accessibility validation suite failed.",
          phase: "validate-policy"
        )
      )
      if failureMessage == nil {
        failureMessage = "validate failed for required accessibility validation."
      }
    } else {
      summaryLines.append("validation_policy_result accessibility: success")
    }
    return (summaryLines, anomalies, failureMessage)
  }

  private func unsupportedSubjectBridgeError(for request: ExecutionRequest) -> SymphonyHarnessError {
    let requestedSubjects = request.subjects + request.explicitTestSubjects
    return unsupportedSubjectBridgeError(forSubject: requestedSubjects.joined(separator: ", "))
  }

  private func unsupportedSubjectBridgeError(forSubject subject: String) -> SymphonyHarnessError {
    SymphonyHarnessError(
      code: "subject_bridge_unavailable",
      message:
        "ExecutionRequest does not support the requested subject selection for \(subject). Use the canonical subject and command combinations or the dedicated doctor API."
    )
  }

fileprivate static let noXcodeMessage =
    "not supported because the current environment has no Xcode available; Editing those sources is not encouraged"
}

extension SymphonyHarnessTool: @unchecked Sendable {}

private struct SubjectExecutionSelection {
  let legacyProduct: ProductKind
  let subjectName: String
  let scheme: String
  let swiftPMProduct: String?
  let swiftPMTestFilter: String?
  let onlyTesting: [String]
}

private struct SharedRunIndex: Codable, Hashable, Sendable {
  let command: HarnessCommand
  let runID: String
  let startedAt: String
  let endedAt: String
  let entries: [ArtifactIndexEntry]
  let anomalies: [ArtifactAnomaly]
}

private struct SyntheticSubjectSummary: Codable, Hashable, Sendable {
  let command: HarnessCommand
  let subject: String
  let outcome: SubjectRunOutcome
  let artifactRoot: String
  let reason: String
}

private struct RepositoryValidationOutcome: Sendable {
  let summaryLines: [String]
  let anomalies: [ArtifactAnomaly]
  let failureMessage: String?
}

private struct ValidationPlanResult: Codable, Hashable, Sendable {
  let plan: String
  let destination: String
  let outcome: SubjectRunOutcome
  let artifactRoot: String
  let includesAccessibilityCoverage: Bool
}

private struct AggregatedValidationSubjectSummary: Codable, Hashable, Sendable {
  let command: HarnessCommand
  let subject: String
  let outcome: SubjectRunOutcome
  let plans: [ValidationPlanResult]
  let artifactRoot: String
}

private struct ValidationPlanMetadata: Hashable, Sendable {
  let name: String
  let includesAccessibilityCoverage: Bool
}

private final class ScheduledRunCollector: @unchecked Sendable {
  private let lock = NSLock()
  private var results: [SubjectRunResult?]

  init(count: Int) {
    self.results = Array(repeating: nil, count: count)
  }

  func store(result: SubjectRunResult, at index: Int) {
    lock.lock()
    results[index] = result
    lock.unlock()
  }

  func orderedResults() throws -> [SubjectRunResult] {
    lock.lock()
    defer { lock.unlock() }
    var orderedResults = [SubjectRunResult]()
    orderedResults.reserveCapacity(results.count)
    for result in results {
      if let result {
        orderedResults.append(result)
      }
    }
    return orderedResults
  }
}
