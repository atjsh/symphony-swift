import Foundation
import SymphonyShared

extension SymphonyHarnessTool {
  func buildXcode(
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

  func buildSwiftPM(
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

  func testXcode(
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
    try simulatorResolver.boot(resolved: destination)

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

  func testSwiftPM(
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

}
