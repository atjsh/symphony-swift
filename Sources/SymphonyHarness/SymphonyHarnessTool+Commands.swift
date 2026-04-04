import Foundation
import SymphonyShared

extension SymphonyHarnessTool {
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

  public func materializeGoEnry(_ request: GoEnryMaterializationRequest) throws -> String {
    let workspace = try workspaceDiscovery.discover(from: request.currentDirectory)
    let materialization = try goEnryMaterializer.materialize(workspace: workspace)
    return [
      "OK: materialized go-enry",
      "archive: \(materialization.archivePath.path)",
      "header: \(materialization.headerPath.path)",
      "invocation: \(materialization.invocation)",
    ].joined(separator: "\n")
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

  func renderSwiftBuildCommandLine(productName: String) -> String {
    ShellQuoting.render(
      command: "swift",
      arguments: ["build", "--scratch-path", scratchPath, "--product", productName])
  }

  func renderSwiftTestCommandLine(filter: String, enableCodeCoverage: Bool) -> String {
    var arguments = ["test", "--scratch-path", scratchPath]
    if enableCodeCoverage { arguments.append("--enable-code-coverage") }
    arguments += ["--filter", filter]
    return ShellQuoting.render(command: "swift", arguments: arguments)
  }

  func renderSwiftPMRunSequence(productName: String, binPath: String?) -> String {
    let resolvedBinPath = binPath.map { "\($0)/\(productName)" } ?? "<built-product>/\(productName)"
    return [
      renderSwiftBuildCommandLine(productName: productName),
      ShellQuoting.render(command: "swift", arguments: ["build", "--scratch-path", scratchPath, "--show-bin-path"]),
      ShellQuoting.render(command: resolvedBinPath, arguments: []),
    ].joined(separator: "\n")
  }

  func writeHarnessInspectionArtifacts(
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

  func displayedCoverageArtifacts(
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

  func writeCoverageInspectionArtifacts(
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

  func renderedHarnessCommandLine(request: HarnessCommandRequest) -> String {
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

  func compactHarnessFailureMessage(report: HarnessReport, artifactRoot: URL) -> String {
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

  func ensureXcodeSupport(for platform: PlatformKind) throws {
    let capabilities = try toolchainCapabilitiesResolver.resolve()
    guard capabilities.supportsXcodeCommands else {
      throw SymphonyHarnessCommandFailure(message: Self.noXcodeMessage)
    }
    if platform == .iosSimulator, !capabilities.supportsSimulatorCommands {
      throw SymphonyHarnessCommandFailure(message: Self.noXcodeMessage)
    }
  }

  func xcodeDestination(platform: PlatformKind, simulator: String?, dryRun: Bool) throws
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

  func assumedDryRunDestination(platform: PlatformKind, simulator: String?)
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

  func destinationSelector(platform: PlatformKind, simulator: String?)
    -> DestinationSelector
  {
    if platform == .iosSimulator, let simulator, looksLikeUDID(simulator) {
      return DestinationSelector(platform: platform, simulatorName: nil, simulatorUDID: simulator)
    }
    return DestinationSelector(platform: platform, simulatorName: simulator, simulatorUDID: nil)
  }

  func looksLikeUDID(_ value: String) -> Bool {
    value.wholeMatch(of: /^[A-Fa-f0-9-]{36}$/) != nil
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

  func renderXcodeRunSequence(
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

  func simctlEnvironment(endpoint: RuntimeEndpoint, overrides: [String: String]) -> [String:
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
