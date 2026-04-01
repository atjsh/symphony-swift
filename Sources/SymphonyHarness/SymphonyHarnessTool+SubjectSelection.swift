import Foundation
import SymphonyShared

extension SymphonyHarnessTool {
  func executeBuildSelection(
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

  func executeTestSelection(
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

  func executeRunSelection(
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

  func prepareSharedRunRoot(at sharedRunRoot: URL) throws {
    let fileManager = FileManager.default
    try fileManager.createDirectory(
      at: sharedRunRoot.appendingPathComponent("subjects", isDirectory: true),
      withIntermediateDirectories: true
    )
  }

  func makeSubjectExecutionContext(
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

}
