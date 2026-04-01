import Foundation

#if os(macOS)

extension XcodeValidationRunner {

  func cleanupExportArtifactsIfNeeded(
    at exportRoot: URL,
    retention: ValidationArtifactRetention,
    logger: ValidationRunLogger
  ) throws {
    guard retention == .canonicalOnly else {
      return
    }
    guard fileManager.fileExists(atPath: exportRoot.path) else {
      return
    }
    logger.debug("Deleting canonical-only export_root=\(exportRoot.path)")
    try fileManager.removeItem(at: exportRoot)
  }

  func cleanupEphemeralArtifacts(
    outputRoot: URL,
    retention: ValidationArtifactRetention,
    logger: ValidationRunLogger
  ) throws {
    if retention != .keepEverything {
      let buildCacheRoot = outputRoot
        .appendingPathComponent("intermediates", isDirectory: true)
        .appendingPathComponent("build-cache", isDirectory: true)
      if fileManager.fileExists(atPath: buildCacheRoot.path) {
        logger.debug("Deleting build_cache_root=\(buildCacheRoot.path)")
        try fileManager.removeItem(at: buildCacheRoot)
      }
    }

    if retention == .canonicalOnly {
      let exportsRoot = outputRoot.appendingPathComponent("exports", isDirectory: true)
      if fileManager.fileExists(atPath: exportsRoot.path) {
        logger.debug("Deleting exports_root=\(exportsRoot.path)")
        try fileManager.removeItem(at: exportsRoot)
      }
    }
  }

  func locateXCTestRun(in derivedDataPath: URL) throws -> URL {
    let enumerator = fileManager.enumerator(
      at: derivedDataPath,
      includingPropertiesForKeys: [.nameKey],
      options: [.skipsHiddenFiles]
    )
    var matches = [URL]()
    while let url = enumerator?.nextObject() as? URL {
      if url.pathExtension == "xctestrun" {
        matches.append(url)
      }
    }

    guard let xctestrunURL = matches.sorted(by: { $0.path < $1.path }).first else {
      throw ValidationRunnerError(
        "No .xctestrun file was produced under \(derivedDataPath.path)."
      )
    }
    return xctestrunURL
  }

  func loadSummary(
    from resultBundlePath: URL,
    fallbackFailureText: String,
    logger: ValidationRunLogger
  ) throws -> ValidationTestSummary {
    if fileManager.fileExists(atPath: resultBundlePath.path) == false {
      return makeRunnerFailureSummary(
        fallbackFailureText.isEmpty
          ? "No result bundle was produced."
          : fallbackFailureText
      )
    }

    var diagnostics = [String]()
    let summaryCommand = ValidationCommand(
      executable: "xcrun",
      arguments: [
        "xcresulttool", "get", "test-results", "summary",
        "--path", resultBundlePath.path,
        "--compact",
      ],
      environment: [:],
      currentDirectory: resultBundlePath.deletingLastPathComponent()
    )
    let summaryCommandResult = try runCommand(
      label: "xcresulttool get test-results summary",
      command: summaryCommand,
      logger: logger
    )
    if summaryCommandResult.exitStatus == 0 {
      do {
        return try parseSummaryPayload(from: Data(summaryCommandResult.stdout.utf8))
      } catch {
        logger.warning(
          """
          xcresult summary decode failed result_bundle_path=\(resultBundlePath.path) error=\(error.localizedDescription)
          """
        )
        diagnostics.append("xcresult summary decode failed: \(error.localizedDescription)")
      }
    } else {
      logger.warning(
        """
        xcresult summary export failed result_bundle_path=\(resultBundlePath.path) output_excerpt=\(trimmedOutputExcerpt(from: summaryCommandResult.combinedOutput))
        """
      )
      diagnostics.append(
        summaryCommandResult.combinedOutput.isEmpty
          ? "Failed to export xcresult summary."
          : summaryCommandResult.combinedOutput
      )
    }

    let testsCommand = ValidationCommand(
      executable: "xcrun",
      arguments: [
        "xcresulttool", "get", "test-results", "tests",
        "--path", resultBundlePath.path,
        "--compact",
      ],
      environment: [:],
      currentDirectory: resultBundlePath.deletingLastPathComponent()
    )
    let testsCommandResult = try runCommand(
      label: "xcresulttool get test-results tests",
      command: testsCommand,
      logger: logger
    )
    if testsCommandResult.exitStatus == 0 {
      do {
        return try XCResultTestsPayloadParser.makeSummary(from: Data(testsCommandResult.stdout.utf8))
      } catch {
        logger.warning(
          """
          xcresult tests decode failed result_bundle_path=\(resultBundlePath.path) error=\(error.localizedDescription)
          """
        )
        diagnostics.append("xcresult tests decode failed: \(error.localizedDescription)")
      }
    } else {
      logger.warning(
        """
        xcresult tests export failed result_bundle_path=\(resultBundlePath.path) output_excerpt=\(trimmedOutputExcerpt(from: testsCommandResult.combinedOutput))
        """
      )
      diagnostics.append(
        testsCommandResult.combinedOutput.isEmpty
          ? "Failed to export xcresult test tree."
          : testsCommandResult.combinedOutput
      )
    }

    if fallbackFailureText.isEmpty == false {
      diagnostics.append(fallbackFailureText)
    }

    return makeRunnerFailureSummary(
      diagnostics.joined(separator: "\n\n")
    )
  }

  func quiesceSimulatorProcessesIfNeeded(
    subject: ValidationSubject,
    for destination: ValidationDestination,
    projectRoot: URL,
    logger: ValidationRunLogger
  ) throws {
    let terminationCommands = ValidationCommandBuilder.simulatorTerminationCommands(
      projectRoot: projectRoot,
      destination: destination,
      bundleIdentifiers: subject.configuration.simulatorBundleIdentifiers
    )
    let restartCommands = ValidationCommandBuilder.simulatorRestartCommands(
      projectRoot: projectRoot,
      destination: destination
    )

    guard terminationCommands.isEmpty == false || restartCommands.isEmpty == false else {
      return
    }

    logger.debug("Quiescing simulator destination=\(destination.displayName)")
    for command in terminationCommands {
      do {
        let result = try runCommand(
          label: "simctl terminate",
          command: command,
          logger: logger
        )
        if result.exitStatus != 0 {
          logger.debug(
            """
            Simulator terminate returned non-zero destination=\(destination.displayName) output_excerpt=\(trimmedOutputExcerpt(from: result.combinedOutput))
            """
          )
        }
      } catch {
        logger.debug(
          """
          Simulator terminate threw destination=\(destination.displayName) error=\(error.localizedDescription)
          """
        )
      }
    }

    for (index, command) in restartCommands.enumerated() {
      let result = try runCommand(
        label: "simctl \(command.arguments[1])",
        command: command,
        logger: logger
      )
      if result.exitStatus == 0 {
        continue
      }

      // `simctl shutdown` is expected to fail when the device is already stopped.
      if index == 0 {
        logger.debug(
          """
          Simulator shutdown returned non-zero destination=\(destination.displayName) output_excerpt=\(trimmedOutputExcerpt(from: result.combinedOutput))
          """
        )
        continue
      }

      logger.error(
        """
        Failed to restart simulator destination=\(destination.displayName) step=\(command.arguments[1]) output_excerpt=\(trimmedOutputExcerpt(from: result.combinedOutput))
        """
      )
      throw ValidationRunnerError(
        result.combinedOutput.isEmpty
          ? "Failed to restart simulator \(destination.displayName)."
          : result.combinedOutput
      )
    }
  }

  func startRecordingIfNeeded(
    for scenario: ValidationScenario,
    videoURL: URL,
    projectRoot: URL,
    logger: ValidationRunLogger
  ) throws -> RunningValidationCommand? {
    guard scenario.recordVideo else {
      return nil
    }

    let command: ValidationCommand
    if let simulatorUDID = scenario.destination.simulatorUDID {
      command = ValidationCommand(
        executable: "xcrun",
        arguments: [
          "simctl", "io", simulatorUDID, "recordVideo",
          "--codec=h264", "--force", videoURL.path,
        ],
        environment: [:],
        currentDirectory: projectRoot
      )
    } else {
      command = ValidationCommand(
        executable: "screencapture",
        arguments: ["-v", "-D1", "-V300", videoURL.path],
        environment: [:],
        currentDirectory: projectRoot
      )
    }

    logger.debug("Starting recording command video_path=\(videoURL.path)")
    let runningCommand = try startCommand(
      label: "recording",
      command: command,
      logger: logger
    )
    Thread.sleep(forTimeInterval: 1)
    return runningCommand
  }

  func copyMediaArtifacts(
    manifestData: Data,
    from exportRoot: URL,
    to screenshotsDirectory: URL,
    run: ValidationRunRecord,
    logger: ValidationRunLogger
  ) throws -> [MediaArtifact] {
    let parsedArtifacts = try ValidationAttachmentCatalog.mediaArtifacts(
      manifestData: manifestData,
      exportRoot: exportRoot,
      run: run
    )

    return try parsedArtifacts.map { artifact in
      let sourceURL = URL(fileURLWithPath: artifact.file)
      let fileName = stableFileName(for: artifact, pathExtension: sourceURL.pathExtension)
      let destinationURL = screenshotsDirectory.appendingPathComponent(fileName)
      if fileManager.fileExists(atPath: destinationURL.path) {
        try fileManager.removeItem(at: destinationURL)
      }
      try fileManager.copyItem(at: sourceURL, to: destinationURL)
      logger.debug("Copied screenshot source=\(sourceURL.path) destination=\(destinationURL.path)")
      return MediaArtifact(
        platform: artifact.platform,
        plan: artifact.plan,
        test: artifact.test,
        checkpoint: artifact.checkpoint,
        surface: artifact.surface,
        orientation: artifact.orientation,
        variant: artifact.variant,
        artifactType: artifact.artifactType,
        file: destinationURL.path,
        sourceResultBundle: artifact.sourceResultBundle
      )
    }
  }

  func copyAuditIssueArtifacts(
    manifestData: Data,
    from exportRoot: URL,
    to auditDirectory: URL,
    run: ValidationRunRecord,
    logger: ValidationRunLogger
  ) throws -> [AuditIssueRecord] {
    let manifest = try JSONDecoder().decode([AttachmentAuditManifest].self, from: manifestData)
    var auditRecords = [AuditIssueRecord]()

    for testEntry in manifest {
      for attachment in testEntry.attachments where attachment.exportedFileName.lowercased().hasSuffix(".txt") {
        guard let checkpoint = checkpoint(from: attachment.suggestedHumanReadableName) else {
          continue
        }
        let sourceURL = exportRoot.appendingPathComponent(attachment.exportedFileName)
        guard fileManager.fileExists(atPath: sourceURL.path) else {
          continue
        }

        let message = try String(contentsOf: sourceURL, encoding: .utf8)
          .trimmingCharacters(in: .whitespacesAndNewlines)
        let fileName = sanitizedFileName(
          "\(run.destination.platformDirectoryName)-\(run.plan.slug)-\(run.runName)-\(attachment.exportedFileName)"
        )
        let destinationURL = auditDirectory.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: destinationURL.path) {
          try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        logger.debug("Copied audit artifact source=\(sourceURL.path) destination=\(destinationURL.path)")

        auditRecords.append(
          AuditIssueRecord(
            platform: run.destination.platformDirectoryName,
            plan: run.plan.slug,
            test: testEntry.testIdentifier,
            message: message,
            checkpoint: checkpoint,
            file: destinationURL.path,
            sourceResultBundle: run.resultBundlePath.path
          )
        )
      }
    }

    return auditRecords
  }

  func persist(summary: ValidationSummary, at outputRoot: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601

    try encoder.encode(summary)
      .write(to: outputRoot.appendingPathComponent("summary.json"))
    let manifest: RunManifest = summary.mediaArtifacts
    try encoder.encode(manifest)
      .write(to: outputRoot.appendingPathComponent("manifest.json"))
    try encoder.encode(summary.auditIssues)
      .write(to: outputRoot.appendingPathComponent("audit-summary.json"))

    let markdown = renderMarkdownSummary(summary)
    try markdown.write(
      to: outputRoot.appendingPathComponent("summary.md"),
      atomically: true,
      encoding: .utf8
    )
  }

}

#endif
