import Foundation

#if os(macOS)

extension XcodeValidationRunner {

  func queuePostProcessing(
    _ exportWork: ValidationExportWork,
    projectRoot: URL,
    artifactRetention: ValidationArtifactRetention,
    limiter: ValidationAsyncLimiter,
    logger: ValidationRunLogger
  ) -> Task<ValidationPostProcessingOutcome, Never> {
    Task { [self] in
      await limiter.withPermit {
        logger.info("Post-processing started \(exportWork.scheduledScenario.scenario.logDescription)")
        let result = processExportArtifacts(
          exportWork,
          projectRoot: projectRoot,
          artifactRetention: artifactRetention,
          logger: logger
        )
        logger.info(
          """
          Post-processing finished \(exportWork.scheduledScenario.scenario.logDescription) screenshots=\(result.mediaArtifacts.count) audit_issues=\(result.auditIssues.count)
          """
        )
        return result
      }
    }
  }

  func processExportArtifacts(
    _ exportWork: ValidationExportWork,
    projectRoot: URL,
    artifactRetention: ValidationArtifactRetention,
    logger: ValidationRunLogger
  ) -> ValidationPostProcessingOutcome {
    let scenario = exportWork.scheduledScenario.scenario
    let context = exportWork.context
    let runRecord = exportWork.runRecord

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

    do {
      let exportResult = try runCommand(
        label: "xcresulttool export attachments",
        command: exportCommand,
        logger: logger
      )
      guard exportResult.exitStatus == 0 else {
        logger.warning(
          """
          Attachment export failed \(scenario.logDescription) output_excerpt=\(trimmedOutputExcerpt(from: exportResult.combinedOutput))
          """
        )
        return ValidationPostProcessingOutcome(index: exportWork.scheduledScenario.index, mediaArtifacts: [], auditIssues: [])
      }

      let exportManifestURL = context.attachmentExportPath.appendingPathComponent("manifest.json")
      guard fileManager.fileExists(atPath: exportManifestURL.path) else {
        logger.warning(
          """
          Attachment export manifest missing \(scenario.logDescription) export_root=\(context.attachmentExportPath.path)
          """
        )
        return ValidationPostProcessingOutcome(index: exportWork.scheduledScenario.index, mediaArtifacts: [], auditIssues: [])
      }

      let manifestData = try Data(contentsOf: exportManifestURL)
      let exportedArtifacts = try copyMediaArtifacts(
        manifestData: manifestData,
        from: context.attachmentExportPath,
        to: context.screenshotsDirectory,
        run: runRecord,
        logger: logger
      )
      let auditIssues = try copyAuditIssueArtifacts(
        manifestData: manifestData,
        from: context.attachmentExportPath,
        to: context.auditDirectory,
        run: runRecord,
        logger: logger
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
      return ValidationPostProcessingOutcome(
        index: exportWork.scheduledScenario.index,
        mediaArtifacts: exportedArtifacts,
        auditIssues: auditIssues
      )
    } catch {
      logger.warning(
        """
        Post-processing failed \(scenario.logDescription) error=\(error.localizedDescription)
        """
      )
      return ValidationPostProcessingOutcome(index: exportWork.scheduledScenario.index, mediaArtifacts: [], auditIssues: [])
    }
  }

  func collectPostProcessingOutcomes(
    from tasks: [Task<ValidationPostProcessingOutcome, Never>]
  ) async -> [ValidationPostProcessingOutcome] {
    var outcomes = [ValidationPostProcessingOutcome]()
    for task in tasks {
      outcomes.append(await task.value)
    }
    return outcomes
  }

  func settle(_ tasks: [Task<Void, Never>]) async {
    for task in tasks {
      await task.value
    }
  }

  func makeSummary(
    outputRoot: URL,
    runRecords: [ValidationRunRecord],
    mediaArtifacts: [MediaArtifact],
    auditIssues: [AuditIssueRecord],
    artifactRetention: ValidationArtifactRetention
  ) -> ValidationSummary {
    ValidationSummaryBuilder.makeSummary(
      outputRoot: outputRoot,
      runRecords: runRecords,
      mediaArtifacts: normalizedMediaArtifacts(mediaArtifacts, artifactRetention: artifactRetention),
      auditIssues: auditIssues
    )
  }

  func makeSummary(
    outputRoot: URL,
    indexedOutcomes: [ValidationIndexedScenarioOutcome],
    postProcessingOutcomes: [ValidationPostProcessingOutcome],
    artifactRetention: ValidationArtifactRetention
  ) -> ValidationSummary {
    let orderedOutcomes = indexedOutcomes.sorted(by: { $0.index < $1.index })
    let runRecords = orderedOutcomes.map(\.runRecord)
    let immediateMediaArtifacts = orderedOutcomes.flatMap(\.mediaArtifacts)
    let exportedMediaArtifacts = postProcessingOutcomes
      .sorted(by: { $0.index < $1.index })
      .flatMap(\.mediaArtifacts)
    let auditIssues = postProcessingOutcomes
      .sorted(by: { $0.index < $1.index })
      .flatMap(\.auditIssues)

    return ValidationSummaryBuilder.makeSummary(
      outputRoot: outputRoot,
      runRecords: runRecords,
      mediaArtifacts: normalizedMediaArtifacts(
        immediateMediaArtifacts + exportedMediaArtifacts,
        artifactRetention: artifactRetention
      ),
      auditIssues: auditIssues
    )
  }

  func normalizedMediaArtifacts(
    _ mediaArtifacts: [MediaArtifact],
    artifactRetention: ValidationArtifactRetention
  ) -> [MediaArtifact] {
    guard artifactRetention == .canonicalOnly else {
      return mediaArtifacts
    }

    return deduplicatedKeepingLast(mediaArtifacts, by: \.canonicalMediaKey)
  }

  func deduplicatedKeepingLast<Value, Key: Hashable>(
    _ values: [Value],
    by keyPath: KeyPath<Value, Key>
  ) -> [Value] {
    var lastIndexByKey = [Key: Int]()
    for (index, value) in values.enumerated() {
      lastIndexByKey[value[keyPath: keyPath]] = index
    }

    return values.enumerated().compactMap { index, value in
      guard lastIndexByKey[value[keyPath: keyPath]] == index else {
        return nil
      }

      return value
    }
  }

}

#endif
