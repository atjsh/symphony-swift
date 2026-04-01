import Foundation

#if os(macOS)

extension XcodeValidationRunner {

  func startWarmBuildTasks(
    for scheduledScenarios: [ValidationScheduledScenario],
    projectRoot: URL,
    outputRoot: URL,
    buildProfile: ValidationBuildProfile,
    buildStore: ValidationBuildArtifactStore,
    logger: ValidationRunLogger
  ) -> [Task<Void, Never>] {
    scheduledScenarios.map { scheduledScenario in
      Task { [self] in
        let context = ValidationPathFactory.makeContext(
          outputRoot: outputRoot,
          phase: scheduledScenario.scenario.phase,
          destination: scheduledScenario.scenario.destination,
          plan: scheduledScenario.scenario.plan,
          buildProfile: buildProfile,
          runName: scheduledScenario.scenario.runName
        )
        logger.info(
          """
          Warm build scheduled destination=\(scheduledScenario.scenario.destination.platformDirectoryName) plan=\(scheduledScenario.scenario.plan.slug) build_profile=\(buildProfile.rawValue)
          """
        )
        let result = await buildStore.prepareArtifact(
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
        if case .failed(let failureText) = result {
          logger.warning(
            """
            Warm build failed destination=\(scheduledScenario.scenario.destination.platformDirectoryName) plan=\(scheduledScenario.scenario.plan.slug) build_profile=\(buildProfile.rawValue) failure=\(trimmedOutputExcerpt(from: failureText))
            """
          )
        }
      }
    }
  }

  func prepareSharedBuildArtifact(
    for scheduledScenario: ValidationScheduledScenario,
    context: ValidationExecutionContext,
    projectRoot: URL,
    buildProfile: ValidationBuildProfile,
    logger: ValidationRunLogger
  ) -> BuildPreparationResult {
    do {
      try fileManager.createDirectory(
        at: context.derivedDataPath.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      logger.info(
        """
        Building test artifact destination=\(scheduledScenario.scenario.destination.platformDirectoryName) plan=\(scheduledScenario.scenario.plan.slug) build_profile=\(buildProfile.rawValue)
        """
      )
      logger.debug("derived_data_path=\(context.derivedDataPath.path)")
      let buildCommand = ValidationCommandBuilder.buildForTestingCommand(
        projectRoot: projectRoot,
        subject: scheduledScenario.scenario.subject,
        plan: scheduledScenario.scenario.plan,
        destination: scheduledScenario.scenario.destination,
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
          Build-for-testing failed destination=\(scheduledScenario.scenario.destination.platformDirectoryName) plan=\(scheduledScenario.scenario.plan.slug) build_profile=\(buildProfile.rawValue) output_excerpt=\(trimmedOutputExcerpt(from: buildResult.combinedOutput))
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
      logger.info(
        """
        Built test artifact destination=\(scheduledScenario.scenario.destination.platformDirectoryName) plan=\(scheduledScenario.scenario.plan.slug) build_profile=\(buildProfile.rawValue) elapsed=\(formatElapsed(since: buildStartedAt))
        """
      )
      logger.debug(
        """
        xctestrun_path=\(buildArtifact.xctestrunPath.path) derived_data_path=\(buildArtifact.derivedDataPath.path)
        """
      )
      return .ready(buildArtifact)
    } catch {
      logger.error(
        """
        Build-for-testing threw destination=\(scheduledScenario.scenario.destination.platformDirectoryName) plan=\(scheduledScenario.scenario.plan.slug) build_profile=\(buildProfile.rawValue) error=\(error.localizedDescription)
        """
      )
      return .failed(error.localizedDescription)
    }
  }

  func makeExecutionPlan(for request: ValidationRequest) -> ValidationExecutionPlan {
    var index = 0
    var mitigationScenarios = [ValidationScheduledScenario]()
    var macOSScenarios = [ValidationScheduledScenario]()
    var iPhoneScenarios = [ValidationScheduledScenario]()
    var iPadScenarios = [ValidationScheduledScenario]()

    func appendScenario(_ scenario: ValidationScenario, to bucket: inout [ValidationScheduledScenario]) {
      bucket.append(
        ValidationScheduledScenario(
          index: index,
          scenario: scenario,
          lane: ValidationDestinationLane(destination: scenario.destination),
          buildKey: ValidationBuildCacheKey(
            destination: scenario.destination,
            plan: scenario.plan,
            buildProfile: request.buildProfile
          ),
          maxAttempts: ValidationRetryPolicy.maxAttempts(for: scenario.destination)
        )
      )
      index += 1
    }

    for scenario in makeMitigationScenarios(for: request.subject) {
      appendScenario(scenario, to: &mitigationScenarios)
    }

    if request.skipRichCapture == false {
      for scenario in makeRichCaptureScenarios(for: request.subject) {
        switch scenario.destination {
        case .macOS:
          appendScenario(scenario, to: &macOSScenarios)
        case .iPhoneSimulator:
          appendScenario(scenario, to: &iPhoneScenarios)
        case .iPadSimulator:
          appendScenario(scenario, to: &iPadScenarios)
        }
      }
    }

    if request.skipFullMatrix == false {
      for scenario in makeFullMatrixScenarios(for: request.subject) {
        switch scenario.destination {
        case .macOS:
          appendScenario(scenario, to: &macOSScenarios)
        case .iPhoneSimulator:
          appendScenario(scenario, to: &iPhoneScenarios)
        case .iPadSimulator:
          appendScenario(scenario, to: &iPadScenarios)
        }
      }
    }

    let postMitigationLanes = [
      ValidationLanePlan(lane: ValidationDestinationLane(destination: .macOS), scenarios: macOSScenarios),
      ValidationLanePlan(lane: ValidationDestinationLane(destination: .iPhoneSimulator), scenarios: iPhoneScenarios),
      ValidationLanePlan(lane: ValidationDestinationLane(destination: .iPadSimulator), scenarios: iPadScenarios),
    ].filter { $0.scenarios.isEmpty == false }

    let mitigationKeys = Set(mitigationScenarios.map(\.buildKey))
    var seenWarmBuildKeys = Set<ValidationBuildCacheKey>()
    let warmBuildScenarios = postMitigationLanes
      .flatMap(\.scenarios)
      .filter { scenario in
        mitigationKeys.contains(scenario.buildKey) == false
          && seenWarmBuildKeys.insert(scenario.buildKey).inserted
      }

    return ValidationExecutionPlan(
      mitigationScenarios: mitigationScenarios,
      postMitigationLanes: postMitigationLanes,
      warmBuildScenarios: warmBuildScenarios
    )
  }

  func terminateKnownSimulatorProcessesIfNeeded(
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
    guard terminationCommands.isEmpty == false else {
      return
    }

    logger.debug("Terminating known simulator processes destination=\(destination.displayName)")
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
  }

}

#endif
