import Foundation

#if os(macOS)

extension XcodeValidationRunner {

  func runParallel(
    _ request: ValidationRequest,
    outputRoot: URL,
    resolvedConcurrency: ValidationConcurrency,
    logger: ValidationRunLogger
  ) async throws -> ValidationSummary {
    let plan = makeExecutionPlan(for: request)
    let buildStore = ValidationBuildArtifactStore(maxParallelBuilds: resolvedConcurrency.maxParallelBuilds)
    let destinationLimiter = ValidationAsyncLimiter(limit: resolvedConcurrency.maxParallelDestinations)
    let simulatorLimiter = ValidationAsyncLimiter(limit: resolvedConcurrency.maxParallelSimulators)
    let postProcessingLimiter = ValidationAsyncLimiter(limit: 2)

    var indexedOutcomes = [ValidationIndexedScenarioOutcome]()
    var postProcessingTasks = [Task<ValidationPostProcessingOutcome, Never>]()
    var warmBuildTasks = [Task<Void, Never>]()

    do {
      var mitigationLaneState = ValidationLaneState()
      for (index, scheduledScenario) in plan.mitigationScenarios.enumerated() {
        let outcome = try await executeScheduledScenario(
          scheduledScenario,
          laneState: &mitigationLaneState,
          projectRoot: request.projectRoot,
          outputRoot: outputRoot,
          artifactRetention: request.artifactRetention,
          buildProfile: request.buildProfile,
          buildStore: buildStore,
          postProcessingLimiter: postProcessingLimiter,
          logger: logger
        )
        indexedOutcomes.append(outcome.indexedOutcome)
        if let postProcessingTask = outcome.postProcessingTask {
          postProcessingTasks.append(postProcessingTask)
        }

        if index == 0, resolvedConcurrency.warmBuildsBeforeMitigationPass {
          logger.info("Starting warm build jobs after first mitigation scenario")
          warmBuildTasks = startWarmBuildTasks(
            for: plan.warmBuildScenarios,
            projectRoot: request.projectRoot,
            outputRoot: outputRoot,
            buildProfile: request.buildProfile,
            buildStore: buildStore,
            logger: logger
          )
        }
      }

      let mitigationSummary = makeSummary(
        outputRoot: outputRoot,
        indexedOutcomes: indexedOutcomes,
        postProcessingOutcomes: [],
        artifactRetention: request.artifactRetention
      )
      if mitigationSummary.unresolvedBlockers.isEmpty == false {
        logger.info(
          """
          Stopping after mitigation due to unresolved blockers count=\(mitigationSummary.unresolvedBlockers.count)
          """
        )
        let mitigationPostProcessing = await collectPostProcessingOutcomes(from: postProcessingTasks)
        postProcessingTasks.removeAll(keepingCapacity: true)
        await settle(warmBuildTasks)
        let finalMitigationSummary = makeSummary(
          outputRoot: outputRoot,
          indexedOutcomes: indexedOutcomes,
          postProcessingOutcomes: mitigationPostProcessing,
          artifactRetention: request.artifactRetention
        )
        try persist(summary: finalMitigationSummary, at: outputRoot)
        logger.info(
          """
          Run completed status=\(finalMitigationSummary.status.rawValue) runs=\(finalMitigationSummary.runRecords.count) media_artifacts=\(finalMitigationSummary.mediaArtifacts.count) audit_issues=\(finalMitigationSummary.auditIssues.count) blockers=\(finalMitigationSummary.unresolvedBlockers.count)
          """
        )
        return finalMitigationSummary
      }

      logger.info("Mitigation gate opened lane_count=\(plan.postMitigationLanes.count)")
      let laneResults = await executePostMitigationLanes(
        plan.postMitigationLanes,
        request: request,
        outputRoot: outputRoot,
        artifactRetention: request.artifactRetention,
        buildProfile: request.buildProfile,
        buildStore: buildStore,
        destinationLimiter: destinationLimiter,
        simulatorLimiter: simulatorLimiter,
        postProcessingLimiter: postProcessingLimiter,
        logger: logger
      )

      indexedOutcomes.append(contentsOf: laneResults.indexedOutcomes)
      postProcessingTasks.append(contentsOf: laneResults.postProcessingTasks)

      await settle(warmBuildTasks)
      let postProcessingOutcomes = await collectPostProcessingOutcomes(from: postProcessingTasks)
      if let error = laneResults.firstError {
        throw error
      }

      let summary = makeSummary(
        outputRoot: outputRoot,
        indexedOutcomes: indexedOutcomes,
        postProcessingOutcomes: postProcessingOutcomes,
        artifactRetention: request.artifactRetention
      )
      try persist(summary: summary, at: outputRoot)
      logger.info(
        """
        Run completed status=\(summary.status.rawValue) runs=\(summary.runRecords.count) media_artifacts=\(summary.mediaArtifacts.count) audit_issues=\(summary.auditIssues.count) blockers=\(summary.unresolvedBlockers.count)
        """
      )
      return summary
    } catch {
      await settle(warmBuildTasks)
      _ = await collectPostProcessingOutcomes(from: postProcessingTasks)
      throw error
    }
  }

  func executePostMitigationLanes(
    _ lanePlans: [ValidationLanePlan],
    request: ValidationRequest,
    outputRoot: URL,
    artifactRetention: ValidationArtifactRetention,
    buildProfile: ValidationBuildProfile,
    buildStore: ValidationBuildArtifactStore,
    destinationLimiter: ValidationAsyncLimiter,
    simulatorLimiter: ValidationAsyncLimiter,
    postProcessingLimiter: ValidationAsyncLimiter,
    logger: ValidationRunLogger
  ) async -> ValidationPostMitigationExecutionResult {
    await withTaskGroup(of: ValidationLaneExecutionResult.self) { group in
      for lanePlan in lanePlans {
        group.addTask { [self] in
          var laneState = ValidationLaneState()
          var indexedOutcomes = [ValidationIndexedScenarioOutcome]()
          var postProcessingTasks = [Task<ValidationPostProcessingOutcome, Never>]()

          do {
            for scheduledScenario in lanePlan.scenarios {
              let indexedOutcome = try await withLanePermits(
                for: lanePlan.lane,
                scheduledScenario: scheduledScenario,
                laneState: &laneState,
                request: request,
                outputRoot: outputRoot,
                artifactRetention: artifactRetention,
                buildProfile: buildProfile,
                buildStore: buildStore,
                destinationLimiter: destinationLimiter,
                simulatorLimiter: simulatorLimiter,
                postProcessingLimiter: postProcessingLimiter,
                logger: logger
              )

              indexedOutcomes.append(indexedOutcome.indexedOutcome)
              if let postProcessingTask = indexedOutcome.postProcessingTask {
                postProcessingTasks.append(postProcessingTask)
              }
            }

            return ValidationLaneExecutionResult(
              indexedOutcomes: indexedOutcomes,
              postProcessingTasks: postProcessingTasks,
              error: nil
            )
          } catch {
            return ValidationLaneExecutionResult(
              indexedOutcomes: indexedOutcomes,
              postProcessingTasks: postProcessingTasks,
              error: error
            )
          }
        }
      }

      var indexedOutcomes = [ValidationIndexedScenarioOutcome]()
      var postProcessingTasks = [Task<ValidationPostProcessingOutcome, Never>]()
      var firstError: Error?

      for await laneResult in group {
        indexedOutcomes.append(contentsOf: laneResult.indexedOutcomes)
        postProcessingTasks.append(contentsOf: laneResult.postProcessingTasks)
        if firstError == nil {
          firstError = laneResult.error
        }
      }

      return ValidationPostMitigationExecutionResult(
        indexedOutcomes: indexedOutcomes,
        postProcessingTasks: postProcessingTasks,
        firstError: firstError
      )
    }
  }

}

#endif
