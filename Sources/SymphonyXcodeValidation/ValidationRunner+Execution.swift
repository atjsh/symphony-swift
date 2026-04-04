import Foundation

#if os(macOS)

extension XcodeValidationRunner {

  func withLanePermits(
    for lane: ValidationDestinationLane,
    scheduledScenario: ValidationScheduledScenario,
    laneState: inout ValidationLaneState,
    request: ValidationRequest,
    outputRoot: URL,
    artifactRetention: ValidationArtifactRetention,
    buildProfile: ValidationBuildProfile,
    buildStore: ValidationBuildArtifactStore,
    destinationLimiter: ValidationAsyncLimiter,
    simulatorLimiter: ValidationAsyncLimiter,
    postProcessingLimiter: ValidationAsyncLimiter,
    logger: ValidationRunLogger
  ) async throws -> ValidationQueuedScenarioOutcome {
    await destinationLimiter.acquire()
    logger.debug("Lane acquired lane=\(lane.id) scenario=\(scheduledScenario.scenario.logDescription)")

    if lane.isSimulator {
      await simulatorLimiter.acquire()
    }

    do {
      let outcome = try await executeScheduledScenario(
        scheduledScenario,
        laneState: &laneState,
        projectRoot: request.projectRoot,
        outputRoot: outputRoot,
        artifactRetention: artifactRetention,
        buildProfile: buildProfile,
        buildStore: buildStore,
        postProcessingLimiter: postProcessingLimiter,
        logger: logger
      )
      if lane.isSimulator {
        await simulatorLimiter.release()
      }
      logger.debug("Lane released lane=\(lane.id) scenario=\(scheduledScenario.scenario.logDescription)")
      await destinationLimiter.release()
      return outcome
    } catch {
      if lane.isSimulator {
        await simulatorLimiter.release()
      }
      logger.debug("Lane released lane=\(lane.id) scenario=\(scheduledScenario.scenario.logDescription)")
      await destinationLimiter.release()
      throw error
    }
  }

  func executeScheduledScenario(
    _ scheduledScenario: ValidationScheduledScenario,
    laneState: inout ValidationLaneState,
    projectRoot: URL,
    outputRoot: URL,
    artifactRetention: ValidationArtifactRetention,
    buildProfile: ValidationBuildProfile,
    buildStore: ValidationBuildArtifactStore,
    postProcessingLimiter: ValidationAsyncLimiter,
    logger: ValidationRunLogger
  ) async throws -> ValidationQueuedScenarioOutcome {
    let scenario = scheduledScenario.scenario
    let context = ValidationPathFactory.makeContext(
      outputRoot: outputRoot,
      phase: scenario.phase,
      destination: scenario.destination,
      plan: scenario.plan,
      buildProfile: buildProfile,
      runName: scenario.runName
    )

    let buildArtifact = await buildStore.prepareArtifact(
      for: scheduledScenario.buildKey,
      logger: logger
    ) { [self] in
      prepareSharedBuildArtifact(
        for: scheduledScenario,
        context: context,
        projectRoot: projectRoot,
        buildProfile: buildProfile,
        logger: logger
      )
    }

    for attempt in 0..<scheduledScenario.maxAttempts {
      let attemptNumber = attempt + 1
      let attemptStartedAt = now()
      logger.info(
        """
        Scenario started \(scenario.logDescription) lane=\(scheduledScenario.lane.id) attempt=\(attemptNumber) max_attempts=\(scheduledScenario.maxAttempts)
        """
      )

      let attemptOutcome: ValidationAttemptOutcome
      do {
        attemptOutcome = try executeScenarioAttempt(
          scheduledScenario,
          context: context,
          laneState: &laneState,
          buildArtifact: buildArtifact,
          projectRoot: projectRoot,
          logger: logger
        )
      } catch {
        logger.error(
          """
          Scenario threw \(scenario.logDescription) lane=\(scheduledScenario.lane.id) attempt=\(attemptNumber) error=\(error.localizedDescription)
          """
        )
        throw error
      }

      logger.info(
        """
        Scenario finished \(scenario.logDescription) lane=\(scheduledScenario.lane.id) attempt=\(attemptNumber) outcome=\(attemptOutcome.runRecord.outcome.rawValue) elapsed=\(formatElapsed(since: attemptStartedAt))
        """
      )

      let shouldRetry = ValidationRetryPolicy.shouldRetryScenario(
        destination: scenario.destination,
        summary: attemptOutcome.runRecord.summary,
        afterAttempt: attempt,
        maxAttempts: scheduledScenario.maxAttempts
      )
      if shouldRetry {
        logger.info(
          """
          Retrying scenario after transient simulator failure \(scenario.logDescription) lane=\(scheduledScenario.lane.id) attempt=\(attemptNumber)
          """
        )
        laneState.requiresRebootBeforeNextScenario = true
        continue
      }

      laneState.requiresRebootBeforeNextScenario = false
      let postProcessingTask = attemptOutcome.exportWork.map { exportWork in
        queuePostProcessing(
          exportWork,
          projectRoot: projectRoot,
          artifactRetention: artifactRetention,
          limiter: postProcessingLimiter,
          logger: logger
        )
      }

      return ValidationQueuedScenarioOutcome(
        indexedOutcome: ValidationIndexedScenarioOutcome(
          index: scheduledScenario.index,
          runRecord: attemptOutcome.runRecord,
          mediaArtifacts: attemptOutcome.immediateMediaArtifacts
        ),
        postProcessingTask: postProcessingTask
      )
    }

    throw ValidationRunnerError("Validation scenario retry loop exhausted unexpectedly.")
  }

  func executeScenarioAttempt(
    _ scheduledScenario: ValidationScheduledScenario,
    context: ValidationExecutionContext,
    laneState: inout ValidationLaneState,
    buildArtifact: BuildPreparationResult,
    projectRoot: URL,
    logger: ValidationRunLogger
  ) throws -> ValidationAttemptOutcome {
    let scenario = scheduledScenario.scenario
    let startedAt = now()
    try prepare(context: context, logger: logger)
    logger.debug(
      """
      Prepared scenario context \(scenario.logDescription) lane=\(scheduledScenario.lane.id) derived_data_path=\(context.derivedDataPath.path) result_bundle_path=\(context.resultBundlePath.path) export_root=\(context.attachmentExportPath.path)
      """
    )

    guard case .ready(let cachedBuildArtifact) = buildArtifact else {
      let failureText: String
      switch buildArtifact {
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
      return ValidationAttemptOutcome(
        runRecord: failedRun,
        immediateMediaArtifacts: [],
        exportWork: nil
      )
    }

    try terminateKnownSimulatorProcessesIfNeeded(
      subject: scenario.subject,
      for: scenario.destination,
      projectRoot: projectRoot,
      logger: logger
    )
    if scenario.destination.simulatorUDID != nil
      && (laneState.hasBooted == false || laneState.requiresRebootBeforeNextScenario)
    {
      try rebootSimulatorDestinationIfNeeded(
        for: scenario.destination,
        projectRoot: projectRoot,
        logger: logger
      )
      laneState.hasBooted = true
      laneState.requiresRebootBeforeNextScenario = false
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
      xctestrunPath: cachedBuildArtifact.xctestrunPath,
      destination: scenario.destination,
      buildProfile: scheduledScenario.buildKey.buildProfile,
      resultBundlePath: context.resultBundlePath,
      onlyTesting: scenario.onlyTesting,
      outputModeQuiet: true
    )
    logger.info(
      """
      Running tests \(scenario.logDescription) lane=\(scheduledScenario.lane.id) result_bundle_path=\(context.resultBundlePath.path) only_testing_count=\(scenario.onlyTesting.count)
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
      Finished tests \(scenario.logDescription) lane=\(scheduledScenario.lane.id) exit_status=\(testResult.exitStatus) elapsed=\(formatElapsed(since: testStartedAt))
      """
    )

    var immediateMediaArtifacts = [MediaArtifact]()
    if scenario.recordVideo, fileManager.fileExists(atPath: videoURL.path) {
      immediateMediaArtifacts.append(
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
        immediateMediaArtifacts.append(
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

    let exportWork =
      scenario.exportAttachments && fileManager.fileExists(atPath: context.resultBundlePath.path)
      ? ValidationExportWork(
        scheduledScenario: scheduledScenario,
        context: context,
        runRecord: runRecord
      )
      : nil

    return ValidationAttemptOutcome(
      runRecord: runRecord,
      immediateMediaArtifacts: immediateMediaArtifacts,
      exportWork: exportWork
    )
  }

}

#endif
