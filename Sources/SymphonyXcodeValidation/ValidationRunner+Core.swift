import Foundation

#if os(macOS)

extension XcodeValidationRunner {

  public func run(_ request: ValidationRequest) throws -> ValidationSummary {
    try waitForAsyncResult {
      try await self.runAsync(request)
    }
  }

  func runAsync(_ request: ValidationRequest) async throws -> ValidationSummary {
    let outputRoot = request.outputRoot ?? defaultOutputRoot(projectRoot: request.projectRoot)
    try fileManager.createDirectory(at: outputRoot, withIntermediateDirectories: true)
    let resolvedConcurrency = request.resolvedConcurrency()
    let logger = ValidationRunLogger(level: request.logLevel, now: now, sink: logSink)
    logger.info(
      """
      Run started subject=\(request.subject.rawValue) output_root=\(outputRoot.path) artifact_retention=\(request.artifactRetention.rawValue) build_profile=\(request.buildProfile.rawValue) execution_profile=\(request.executionProfile.rawValue) max_parallel_builds=\(resolvedConcurrency.maxParallelBuilds) max_parallel_destinations=\(resolvedConcurrency.maxParallelDestinations) max_parallel_simulators=\(resolvedConcurrency.maxParallelSimulators) warm_builds_before_mitigation_pass=\(resolvedConcurrency.warmBuildsBeforeMitigationPass) skip_rich_capture=\(request.skipRichCapture) skip_full_matrix=\(request.skipFullMatrix)
      """
    )
    defer {
      do {
        try cleanupEphemeralArtifacts(
          outputRoot: outputRoot,
          retention: request.artifactRetention,
          logger: logger
        )
      } catch {
        logger.warning(
          """
          Failed to clean ephemeral artifacts output_root=\(outputRoot.path) error=\(error.localizedDescription)
          """
        )
      }
    }

    if shouldUseLegacySerialPath(request: request, resolvedConcurrency: resolvedConcurrency) {
      logger.info("Using serial execution path execution_profile=\(request.executionProfile.rawValue)")
      return try runSerial(
        request,
        outputRoot: outputRoot,
        logger: logger
      )
    }

    logger.info("Using parallel execution path execution_profile=\(request.executionProfile.rawValue)")
    return try await runParallel(
      request,
      outputRoot: outputRoot,
      resolvedConcurrency: resolvedConcurrency,
      logger: logger
    )
  }

  func runSerial(
    _ request: ValidationRequest,
    outputRoot: URL,
    logger: ValidationRunLogger
  ) throws -> ValidationSummary {
    var buildArtifactCache = [ValidationBuildCacheKey: CachedValidationBuildArtifact]()
    var runRecords = [ValidationRunRecord]()
    var mediaArtifacts = [MediaArtifact]()
    var auditIssues = [AuditIssueRecord]()

    let mitigationScenarios = makeMitigationScenarios(for: request.subject)

    for scenario in mitigationScenarios {
      let outcome = try executeScenario(
        scenario,
        projectRoot: request.projectRoot,
        outputRoot: outputRoot,
        artifactRetention: request.artifactRetention,
        buildProfile: request.buildProfile,
        logger: logger,
        buildArtifactCache: &buildArtifactCache
      )
      runRecords.append(outcome.runRecord)
      mediaArtifacts.append(contentsOf: outcome.mediaArtifacts)
      auditIssues.append(contentsOf: outcome.auditIssues)
    }

    let mitigationSummary = makeSummary(
      outputRoot: outputRoot,
      runRecords: runRecords,
      mediaArtifacts: mediaArtifacts,
      auditIssues: auditIssues,
      artifactRetention: request.artifactRetention
    )
    if mitigationSummary.unresolvedBlockers.isEmpty == false {
      logger.info(
        """
        Stopping after mitigation due to unresolved blockers count=\(mitigationSummary.unresolvedBlockers.count)
        """
      )
      try persist(summary: mitigationSummary, at: outputRoot)
      logger.info(
        """
        Run completed status=\(mitigationSummary.status.rawValue) runs=\(mitigationSummary.runRecords.count) media_artifacts=\(mitigationSummary.mediaArtifacts.count) audit_issues=\(mitigationSummary.auditIssues.count) blockers=\(mitigationSummary.unresolvedBlockers.count)
        """
      )
      return mitigationSummary
    }

    if request.skipRichCapture == false {
      for scenario in makeRichCaptureScenarios(for: request.subject) {
        let outcome = try executeScenario(
          scenario,
          projectRoot: request.projectRoot,
          outputRoot: outputRoot,
          artifactRetention: request.artifactRetention,
          buildProfile: request.buildProfile,
          logger: logger,
          buildArtifactCache: &buildArtifactCache
        )
        runRecords.append(outcome.runRecord)
        mediaArtifacts.append(contentsOf: outcome.mediaArtifacts)
        auditIssues.append(contentsOf: outcome.auditIssues)
      }
    }

    if request.skipFullMatrix == false {
      for scenario in makeFullMatrixScenarios(for: request.subject) {
        let outcome = try executeScenario(
          scenario,
          projectRoot: request.projectRoot,
          outputRoot: outputRoot,
          artifactRetention: request.artifactRetention,
          buildProfile: request.buildProfile,
          logger: logger,
          buildArtifactCache: &buildArtifactCache
        )
          runRecords.append(outcome.runRecord)
          mediaArtifacts.append(contentsOf: outcome.mediaArtifacts)
          auditIssues.append(contentsOf: outcome.auditIssues)
      }
    }

    let summary = makeSummary(
      outputRoot: outputRoot,
      runRecords: runRecords,
      mediaArtifacts: mediaArtifacts,
      auditIssues: auditIssues,
      artifactRetention: request.artifactRetention
    )
    try persist(summary: summary, at: outputRoot)
    logger.info(
      """
      Run completed status=\(summary.status.rawValue) runs=\(summary.runRecords.count) media_artifacts=\(summary.mediaArtifacts.count) audit_issues=\(summary.auditIssues.count) blockers=\(summary.unresolvedBlockers.count)
      """
    )
    return summary
  }

  func makeMitigationScenarios(for subject: ValidationSubject) -> [ValidationScenario] {
    subject.configuration.mitigationScenarios.flatMap { definition in
      materialize(definition, for: subject)
    }
  }

  func makeRichCaptureScenarios(for subject: ValidationSubject) -> [ValidationScenario] {
    guard let definition = subject.configuration.richCaptureScenario else {
      return []
    }
    return materialize(definition, for: subject)
  }

  func makeFullMatrixScenarios(for subject: ValidationSubject) -> [ValidationScenario] {
    let configuration = subject.configuration
    return ValidationDestination.defaultMatrix.flatMap { destination in
      configuration.supportedPlans.map { plan in
        ValidationScenario(
          subject: subject,
          phase: .fullMatrix,
          destination: destination,
          plan: plan,
          runName: "full-\(plan.slug)",
          onlyTesting: [],
          exportAttachments: plan == .uiTests,
          recordVideo: false,
          captureSimulatorScreenshot: false
        )
      }
    }
  }

  func materialize(
    _ definition: ValidationScenarioDefinition,
    for subject: ValidationSubject
  ) -> [ValidationScenario] {
    definition.destinations.map { destination in
      ValidationScenario(
        subject: subject,
        phase: definition.phase,
        destination: destination,
        plan: definition.plan,
        runName: definition.runName,
        onlyTesting: definition.onlyTesting,
        exportAttachments: definition.exportAttachments,
        recordVideo: definition.recordVideo,
        captureSimulatorScreenshot: definition.captureSimulatorScreenshot
          && destination.simulatorUDID != nil
      )
    }
  }

  func shouldUseLegacySerialPath(
    request: ValidationRequest,
    resolvedConcurrency: ValidationConcurrency
  ) -> Bool {
    request.executionProfile == .serial
      && resolvedConcurrency == ValidationExecutionProfile.serial.defaultConcurrency
  }

  func waitForAsyncResult<T>(
    _ operation: @escaping @Sendable () async throws -> T
  ) throws -> T {
    let box = ValidationSynchronousResultBox<T>()

    Task.detached {
      let completion: Result<T, Error>
      do {
        completion = .success(try await operation())
      } catch {
        completion = .failure(error)
      }

      box.result = completion
      box.semaphore.signal()
    }

    box.semaphore.wait()
    guard let result = box.result else {
      throw ValidationRunnerError("Async validation operation did not produce a result.")
    }
    return try result.get()
  }

}

#endif
