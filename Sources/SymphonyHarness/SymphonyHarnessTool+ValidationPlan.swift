import Foundation
import SymphonyShared

extension SymphonyHarnessTool {
  func makeValidationPlanExecutionContext(
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

  func runValidationPlanRequest(
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

  func prepareXcodeExecutionContext(_ executionContext: ExecutionContext) throws {
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

  func resetSimulatorForValidationRetry(
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

  func prepareSimulatorForValidationPlan(
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

  func validationBundleIdentifiers(
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

  func bundleIdentifiersDeclaredInProject(in workspace: WorkspaceContext) -> [String] {
    let projectRoot =
      workspace.xcodeProjectPath
      ?? workspace.projectRoot.appendingPathComponent("SymphonyApps.xcodeproj", isDirectory: true)
    let projectFile = projectRoot.appendingPathComponent("project.pbxproj", isDirectory: false)
    guard let contents = try? String(contentsOf: projectFile, encoding: .utf8) else {
      return []
    }

    guard let regex = try? NSRegularExpression(
      pattern: #"PRODUCT_BUNDLE_IDENTIFIER = ([A-Za-z0-9._-]+);"#
    ) else {
      return []
    }
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

  func isRetryableValidationLaunchFailure(_ output: String) -> Bool {
    output.contains("Application failed preflight checks")
      || output.contains("reason: Busy")
      || output.contains("BSErrorCodeDescription=Busy")
  }

  func checkedInTestPlans(in workspace: WorkspaceContext) -> [URL] {
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

  func makeValidationPlanMetadata(for url: URL) -> ValidationPlanMetadata {
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

}
