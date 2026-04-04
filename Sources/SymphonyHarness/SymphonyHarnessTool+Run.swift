import Foundation
import SymphonyShared

extension SymphonyHarnessTool {
  func runXcode(
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

  func runSwiftPM(
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
      arguments: ["build", "--scratch-path", scratchPath, "--product", productName],
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
        arguments: ["build", "--scratch-path", scratchPath, "--show-bin-path"],
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

}
