import Foundation

#if os(macOS)

extension XcodeValidationRunner {

  func rebootSimulatorDestinationIfNeeded(
    for destination: ValidationDestination,
    projectRoot: URL,
    logger: ValidationRunLogger
  ) throws {
    let restartCommands = ValidationCommandBuilder.simulatorRestartCommands(
      projectRoot: projectRoot,
      destination: destination
    )
    guard restartCommands.isEmpty == false else {
      return
    }

    logger.info("Rebooting simulator destination=\(destination.displayName)")
    for (index, command) in restartCommands.enumerated() {
      let result = try runCommand(
        label: "simctl \(command.arguments[1])",
        command: command,
        logger: logger
      )
      if result.exitStatus == 0 {
        continue
      }

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

  func executeScenario(
    _ scenario: ValidationScenario,
    projectRoot: URL,
    outputRoot: URL,
    artifactRetention: ValidationArtifactRetention,
    buildProfile: ValidationBuildProfile,
    logger: ValidationRunLogger,
    buildArtifactCache: inout [ValidationBuildCacheKey: CachedValidationBuildArtifact]
  ) throws -> ValidationScenarioOutcome {
    let maxAttempts = ValidationRetryPolicy.maxAttempts(for: scenario.destination)

    for attempt in 0..<maxAttempts {
      let attemptNumber = attempt + 1
      let attemptStartedAt = now()
      logger.info(
        """
        Scenario started \(scenario.logDescription) attempt=\(attemptNumber) max_attempts=\(maxAttempts)
        """
      )
      let outcome: ValidationScenarioOutcome
      do {
        outcome = try executeScenarioOnce(
          scenario,
          projectRoot: projectRoot,
          outputRoot: outputRoot,
          artifactRetention: artifactRetention,
          buildProfile: buildProfile,
          logger: logger,
          buildArtifactCache: &buildArtifactCache
        )
      } catch {
        logger.error(
          """
          Scenario threw \(scenario.logDescription) attempt=\(attemptNumber) error=\(error.localizedDescription)
          """
        )
        throw error
      }

      logger.info(
        """
        Scenario finished \(scenario.logDescription) attempt=\(attemptNumber) outcome=\(outcome.runRecord.outcome.rawValue) elapsed=\(formatElapsed(since: attemptStartedAt))
        """
      )

      let shouldRetry = ValidationRetryPolicy.shouldRetryScenario(
        destination: scenario.destination,
        summary: outcome.runRecord.summary,
        afterAttempt: attempt,
        maxAttempts: maxAttempts
      )
      if shouldRetry {
        logger.info(
          """
          Retrying scenario after transient simulator failure \(scenario.logDescription) attempt=\(attemptNumber)
          """
        )
        try quiesceSimulatorProcessesIfNeeded(
          subject: scenario.subject,
          for: scenario.destination,
          projectRoot: projectRoot,
          logger: logger
        )
        continue
      }

      return outcome
    }

    throw ValidationRunnerError("Validation scenario retry loop exhausted unexpectedly.")
  }

  func executeScenarioOnce(
    _ scenario: ValidationScenario,
    projectRoot: URL,
    outputRoot: URL,
    artifactRetention: ValidationArtifactRetention,
    buildProfile: ValidationBuildProfile,
    logger: ValidationRunLogger,
    buildArtifactCache: inout [ValidationBuildCacheKey: CachedValidationBuildArtifact]
  ) throws -> ValidationScenarioOutcome {
    let startedAt = now()
    let context = ValidationPathFactory.makeContext(
      outputRoot: outputRoot,
      phase: scenario.phase,
      destination: scenario.destination,
      plan: scenario.plan,
      buildProfile: buildProfile,
      runName: scenario.runName
    )
    try prepare(context: context, logger: logger)
    logger.debug(
      """
      Prepared scenario context \(scenario.logDescription) derived_data_path=\(context.derivedDataPath.path) result_bundle_path=\(context.resultBundlePath.path) export_root=\(context.attachmentExportPath.path)
      """
    )

    let buildPreparation = try prepareBuildArtifact(
      for: scenario,
      context: context,
      projectRoot: projectRoot,
      buildProfile: buildProfile,
      logger: logger,
      buildArtifactCache: &buildArtifactCache
    )
    guard case .ready(let buildArtifact) = buildPreparation else {
      let failureText: String
      switch buildPreparation {
      case .ready:
        failureText = "xcodebuild build-for-testing failed."
      case .failed(let text):
        failureText = text
      }
      let failedRun = makeSyntheticFailureRunRecord(
        scenario: scenario,
        context: context,
        startedAt: startedAt,
        endedAt: now(),
        failureText: failureText
      )
      return ValidationScenarioOutcome(runRecord: failedRun, mediaArtifacts: [], auditIssues: [])
    }

    try quiesceSimulatorProcessesIfNeeded(
      subject: scenario.subject,
      for: scenario.destination,
      projectRoot: projectRoot,
      logger: logger
    )
    defer {
      do {
        try quiesceSimulatorProcessesIfNeeded(
          subject: scenario.subject,
          for: scenario.destination,
          projectRoot: projectRoot,
          logger: logger
        )
      } catch {
        logger.warning(
          """
          Failed to quiesce simulator after scenario \(scenario.logDescription) error=\(error.localizedDescription)
          """
        )
      }
    }

    let videoURL = context.videosDirectory.appendingPathComponent(
      "\(scenario.destination.platformDirectoryName)-\(scenario.runName).mov",
      isDirectory: false
    )
    let recording = try startRecordingIfNeeded(
      for: scenario,
      videoURL: videoURL,
      projectRoot: projectRoot,
      logger: logger
    )
    defer { recording?.stop() }

    let testCommand = ValidationCommandBuilder.testWithoutBuildingCommand(
      projectRoot: projectRoot,
      subject: scenario.subject,
      plan: scenario.plan,
      xctestrunPath: buildArtifact.xctestrunPath,
      destination: scenario.destination,
      buildProfile: buildProfile,
      resultBundlePath: context.resultBundlePath,
      onlyTesting: scenario.onlyTesting,
      outputModeQuiet: true
    )
    logger.info(
      """
      Running tests \(scenario.logDescription) result_bundle_path=\(context.resultBundlePath.path) only_testing_count=\(scenario.onlyTesting.count)
      """
    )
    let testStartedAt = now()
    let testResult = try runCommand(
      label: "test-without-building",
      command: testCommand,
      logger: logger
    )
    logger.info(
      """
      Finished tests \(scenario.logDescription) exit_status=\(testResult.exitStatus) elapsed=\(formatElapsed(since: testStartedAt))
      """
    )

    var mediaArtifacts = [MediaArtifact]()
    if scenario.recordVideo, fileManager.fileExists(atPath: videoURL.path) {
      mediaArtifacts.append(
        MediaArtifact(
          platform: scenario.destination.platformDirectoryName,
          plan: scenario.plan.slug,
          test: scenario.defaultTestIdentifier,
          checkpoint: scenario.runName,
          surface: scenario.runName,
          orientation: "mixed",
          variant: "recording",
          artifactType: .video,
          file: videoURL.path,
          sourceResultBundle: context.resultBundlePath.path
        )
      )
    }

    if scenario.captureSimulatorScreenshot, let simulatorUDID = scenario.destination.simulatorUDID {
      let screenshotURL = context.screenshotsDirectory.appendingPathComponent(
        "surface=post-test-live-state__orientation=portrait__variant=device__artifact=screenshot.png"
      )
      let screenshotCommand = ValidationCommand(
        executable: "xcrun",
        arguments: [
          "simctl", "io", simulatorUDID, "screenshot", "--type=png", "--display=internal",
          screenshotURL.path,
        ],
        environment: [:],
        currentDirectory: projectRoot
      )
      let screenshotResult = try runCommand(
        label: "simctl screenshot",
        command: screenshotCommand,
        logger: logger
      )
      if screenshotResult.exitStatus == 0, fileManager.fileExists(atPath: screenshotURL.path) {
        mediaArtifacts.append(
          MediaArtifact(
            platform: scenario.destination.platformDirectoryName,
            plan: scenario.plan.slug,
            test: scenario.defaultTestIdentifier,
            checkpoint: "post-test-live-state",
            surface: "post-test-live-state",
            orientation: "portrait",
            variant: "device",
            artifactType: .screenshot,
            file: screenshotURL.path,
            sourceResultBundle: context.resultBundlePath.path
          )
        )
      }
    }

    let summary = try loadSummary(
      from: context.resultBundlePath,
      fallbackFailureText: testResult.combinedOutput,
      logger: logger
    )
    let runRecord = ValidationRunRecord(
      phase: scenario.phase,
      destination: scenario.destination,
      plan: scenario.plan,
      runName: scenario.runName,
      outcome: testResult.exitStatus == 0 ? .passed : .failed,
      resultBundlePath: context.resultBundlePath,
      summary: summary,
      startedAt: startedAt,
      endedAt: now()
    )

    var auditIssues = [AuditIssueRecord]()
    if scenario.exportAttachments, fileManager.fileExists(atPath: context.resultBundlePath.path) {
      let exportCommand = ValidationCommand(
        executable: "xcrun",
        arguments: [
          "xcresulttool", "export", "attachments",
          "--path", context.resultBundlePath.path,
          "--output-path", context.attachmentExportPath.path,
        ],
        environment: [:],
        currentDirectory: projectRoot
      )
      let exportResult = try runCommand(
        label: "xcresulttool export attachments",
        command: exportCommand,
        logger: logger
      )
      if exportResult.exitStatus == 0 {
        let exportManifestURL = context.attachmentExportPath.appendingPathComponent("manifest.json")
        if fileManager.fileExists(atPath: exportManifestURL.path) {
          let manifestData = try Data(contentsOf: exportManifestURL)
          let exportedArtifacts = try copyMediaArtifacts(
            manifestData: manifestData,
            from: context.attachmentExportPath,
            to: context.screenshotsDirectory,
            run: runRecord,
            logger: logger
          )
          mediaArtifacts.append(contentsOf: exportedArtifacts)
          auditIssues.append(
            contentsOf: try copyAuditIssueArtifacts(
              manifestData: manifestData,
              from: context.attachmentExportPath,
              to: context.auditDirectory,
              run: runRecord,
              logger: logger
            )
          )
          logger.info(
            """
            Copied exported artifacts \(scenario.logDescription) screenshots=\(exportedArtifacts.count) audit_issues=\(auditIssues.count)
            """
          )
          try cleanupExportArtifactsIfNeeded(
            at: context.attachmentExportPath,
            retention: artifactRetention,
            logger: logger
          )
        } else {
          logger.warning(
            """
            Attachment export manifest missing \(scenario.logDescription) export_root=\(context.attachmentExportPath.path)
            """
          )
        }
      } else {
        logger.warning(
          """
          Attachment export failed \(scenario.logDescription) output_excerpt=\(trimmedOutputExcerpt(from: exportResult.combinedOutput))
          """
        )
      }
    }

    return ValidationScenarioOutcome(
      runRecord: runRecord,
      mediaArtifacts: mediaArtifacts,
      auditIssues: auditIssues
    )
  }

  func prepare(context: ValidationExecutionContext, logger: ValidationRunLogger) throws {
    for url in [
      context.artifactRoot,
      context.derivedDataPath.deletingLastPathComponent(),
      context.resultBundlePath.deletingLastPathComponent(),
      context.attachmentExportPath.deletingLastPathComponent(),
      context.screenshotsDirectory,
      context.videosDirectory,
      context.auditDirectory,
    ] {
      try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }
    if fileManager.fileExists(atPath: context.attachmentExportPath.path) {
      logger.debug("Removing stale export_root=\(context.attachmentExportPath.path)")
      try fileManager.removeItem(at: context.attachmentExportPath)
    }
    if fileManager.fileExists(atPath: context.resultBundlePath.path) {
      logger.debug("Removing stale result_bundle_path=\(context.resultBundlePath.path)")
      try fileManager.removeItem(at: context.resultBundlePath)
    }
  }

  func prepareBuildArtifact(
    for scenario: ValidationScenario,
    context: ValidationExecutionContext,
    projectRoot: URL,
    buildProfile: ValidationBuildProfile,
    logger: ValidationRunLogger,
    buildArtifactCache: inout [ValidationBuildCacheKey: CachedValidationBuildArtifact]
  ) throws -> BuildPreparationResult {
    let key = ValidationBuildCacheKey(
      destination: scenario.destination,
      plan: scenario.plan,
      buildProfile: buildProfile
    )
    if let cachedArtifact = buildArtifactCache[key] {
      logger.info(
        """
        Reusing build artifact destination=\(scenario.destination.platformDirectoryName) plan=\(scenario.plan.slug) build_profile=\(buildProfile.rawValue)
        """
      )
      logger.debug(
        """
        Reusing build artifact derived_data_path=\(cachedArtifact.derivedDataPath.path) xctestrun_path=\(cachedArtifact.xctestrunPath.path)
        """
      )
      return .ready(cachedArtifact)
    }

    logger.info(
      """
      Building test artifact destination=\(scenario.destination.platformDirectoryName) plan=\(scenario.plan.slug) build_profile=\(buildProfile.rawValue)
      """
    )
    logger.debug("derived_data_path=\(context.derivedDataPath.path)")
    let buildCommand = ValidationCommandBuilder.buildForTestingCommand(
      projectRoot: projectRoot,
      subject: scenario.subject,
      plan: scenario.plan,
      destination: scenario.destination,
      buildProfile: buildProfile,
      derivedDataPath: context.derivedDataPath,
      outputModeQuiet: true
    )
    let buildStartedAt = now()
    let buildResult = try runCommand(
      label: "build-for-testing",
      command: buildCommand,
      logger: logger
    )
    guard buildResult.exitStatus == 0 else {
      logger.error(
        """
        Build-for-testing failed destination=\(scenario.destination.platformDirectoryName) plan=\(scenario.plan.slug) build_profile=\(buildProfile.rawValue) output_excerpt=\(trimmedOutputExcerpt(from: buildResult.combinedOutput))
        """
      )
      return .failed(
        buildResult.combinedOutput.isEmpty
          ? "xcodebuild build-for-testing failed."
          : buildResult.combinedOutput
      )
    }

    let buildArtifact = CachedValidationBuildArtifact(
      derivedDataPath: context.derivedDataPath,
      xctestrunPath: try locateXCTestRun(in: context.derivedDataPath)
    )
    buildArtifactCache[key] = buildArtifact
    logger.info(
      """
      Built test artifact destination=\(scenario.destination.platformDirectoryName) plan=\(scenario.plan.slug) build_profile=\(buildProfile.rawValue) elapsed=\(formatElapsed(since: buildStartedAt))
      """
    )
    logger.debug(
      """
      xctestrun_path=\(buildArtifact.xctestrunPath.path) derived_data_path=\(buildArtifact.derivedDataPath.path)
      """
    )
    return .ready(buildArtifact)
  }

}

#endif
