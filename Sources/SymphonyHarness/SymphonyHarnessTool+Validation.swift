import Foundation
import SymphonyShared

extension SymphonyHarnessTool {
  func executeRepositoryValidationPolicies(
    request: ExecutionRequest,
    workspace: WorkspaceContext,
    capabilities: ToolchainCapabilities,
    subjectResults: [SubjectRunResult]
  ) throws -> RepositoryValidationOutcome {
    var summaryLines = [String]()
    var anomalies = [ArtifactAnomaly]()
    var failureMessage: String?

    do {
      let report = try doctorService.makeReport(
        from: DoctorCommandRequest(
          strict: false,
          json: false,
          quiet: true,
          currentDirectory: workspace.projectRoot
        )
      )
      var errorIssues = [DiagnosticIssue]()
      for issue in report.issues where issue.severity == .error {
        errorIssues.append(issue)
      }
      if !errorIssues.isEmpty {
        var renderedIssues = [String]()
        for issue in errorIssues {
          renderedIssues.append("[\(issue.code)] \(issue.message)")
        }
        let issueText = renderedIssues.joined(separator: "; ")
        summaryLines.append("validation_policy_result environment: failure")
        summaryLines.append("validation_policy_detail environment: \(issueText)")
        anomalies.append(
          ArtifactAnomaly(
            code: "environment_policy_failed",
            message: issueText,
            phase: "validate-policy"
          )
        )
        if failureMessage == nil {
          failureMessage = "validate failed for repository environment policies."
        }
      } else {
        summaryLines.append("validation_policy_result environment: success")
      }
    } catch {
      summaryLines.append("validation_policy_result environment: failure")
      summaryLines.append("validation_policy_detail environment: \(error.localizedDescription)")
      anomalies.append(
        ArtifactAnomaly(
          code: "environment_policy_failed",
          message: error.localizedDescription,
          phase: "validate-policy"
        )
      )
      if failureMessage == nil {
        failureMessage = "validate failed for repository environment policies."
      }
    }

    do {
      let execution = try commitHarness.execute(
        workspace: workspace,
        request: HarnessCommandRequest(
          minimumCoveragePercent: 100,
          json: false,
          outputMode: request.outputMode,
          currentDirectory: workspace.projectRoot
        )
      )
      if execution.report.meetsCoverageThreshold {
        summaryLines.append("validation_policy_result coverage: success")
      } else {
        summaryLines.append("validation_policy_result coverage: failure")
        anomalies.append(
          ArtifactAnomaly(
            code: "coverage_policy_failed",
            message: commitHarness.renderHuman(report: execution.report),
            phase: "validate-policy"
          )
        )
        if failureMessage == nil {
          failureMessage = "validate failed for repository coverage policies."
        }
      }
    } catch {
      summaryLines.append("validation_policy_result coverage: failure")
      anomalies.append(
        ArtifactAnomaly(
          code: "coverage_policy_failed",
          message: error.localizedDescription,
          phase: "validate-policy"
        )
      )
      if failureMessage == nil {
        failureMessage = "validate failed for repository coverage policies."
      }
    }

    let artifactPolicyOutcome = Self.artifactValidationPolicyOutcome(for: subjectResults)
    summaryLines.append(contentsOf: artifactPolicyOutcome.summaryLines)
    anomalies.append(contentsOf: artifactPolicyOutcome.anomalies)
    if failureMessage == nil {
      failureMessage = artifactPolicyOutcome.failureMessage
    }

    if capabilities.supportsSimulatorCommands {
      let appPolicyOutcome = Self.defaultAppValidationPolicyOutcome(
        subjectResults: subjectResults,
        supportsSimulatorCommands: true,
        buildStateRoot: workspace.buildStateRoot
      )
      summaryLines.append(contentsOf: appPolicyOutcome.summaryLines)
      anomalies.append(contentsOf: appPolicyOutcome.anomalies)
      if failureMessage == nil {
        failureMessage = appPolicyOutcome.failureMessage
      }
    } else {
      let appPolicyOutcome = Self.defaultAppValidationPolicyOutcome(
        subjectResults: subjectResults,
        supportsSimulatorCommands: false,
        buildStateRoot: workspace.buildStateRoot
      )
      summaryLines.append(contentsOf: appPolicyOutcome.summaryLines)
      anomalies.append(contentsOf: appPolicyOutcome.anomalies)
    }

    return RepositoryValidationOutcome(
      summaryLines: summaryLines,
      anomalies: anomalies,
      failureMessage: failureMessage
    )
  }

  func executeDefaultAppValidationSuite(
    subject: HarnessSubject,
    request: ExecutionRequest,
    workspace: WorkspaceContext,
    subjectRoot: URL,
    sharedRunID: String,
    workerID: Int
  ) throws -> SubjectRunResult {
    do {
      var testPlans = [ValidationPlanMetadata]()
      for testPlanURL in checkedInTestPlans(in: workspace) {
        testPlans.append(makeValidationPlanMetadata(for: testPlanURL))
      }
      guard !testPlans.isEmpty else {
        let artifactSet = try writeFailedSubjectArtifacts(
          subject: subject,
          command: .validate,
          subjectRoot: subjectRoot,
          reason: "No checked-in .xctestplan files were found for default app validation."
        )
        return SubjectRunResult(subject: subject.name, outcome: .failure, artifactSet: artifactSet)
      }

      let destinations = try simulatorResolver.approvedValidationDestinations()
      for destination in destinations {
        try simulatorResolver.boot(resolved: destination)
      }
      let fileManager = FileManager.default
      try fileManager.createDirectory(at: subjectRoot, withIntermediateDirectories: true)

      var planResults = [ValidationPlanResult]()
      var combinedLogs = [String]()
      var subjectAnomalies = [ArtifactAnomaly]()
      var createdEntries = [ArtifactIndexEntry]()

      for testPlanURL in testPlans {
        let testPlan = testPlanURL.name
        for destination in destinations {
          var destinationLabel = destination.displayName
          if let simulatorName = destination.simulatorName {
            destinationLabel = simulatorName
          }
          let planSlug = ShellQuoting.slugify("\(testPlan)-\(destinationLabel)")
          let planRoot = subjectRoot.appendingPathComponent("plans/\(planSlug)", isDirectory: true)
          let executionContext = try makeValidationPlanExecutionContext(
            workspace: workspace,
            subject: subject,
            testPlan: testPlan,
            destination: destination,
            sharedRunID: sharedRunID,
            workerID: workerID,
            artifactRoot: planRoot
          )
          let xcodeRequest = XcodeCommandRequest(
            action: .test,
            scheme: subject.name,
            destination: destination,
            derivedDataPath: executionContext.derivedDataPath,
            resultBundlePath: executionContext.resultBundlePath,
            enableCodeCoverage: false,
            outputMode: request.outputMode,
            environment: [:],
            workspacePath: workspace.xcodeWorkspacePath,
            projectPath: workspace.xcodeProjectPath,
            testPlan: testPlan
          )
          let startedAt = Date()
          let result = try runValidationPlanRequest(
            xcodeRequest,
            request: request,
            workspace: workspace,
            scheme: subject.name,
            testPlan: testPlan,
            destination: destination,
            executionContext: executionContext
          )
          let endedAt = Date()
          let record = try artifactManager.recordXcodeExecution(
            workspace: workspace,
            executionContext: executionContext,
            command: .test,
            product: .client,
            scheme: subject.name,
            destination: destination,
            invocation: try xcodeRequest.renderedCommandLine(),
            exitStatus: result.exitStatus,
            combinedOutput: result.combinedOutput,
            startedAt: startedAt,
            endedAt: endedAt,
            subjectName: subject.name
          )
          var anomalies = [ArtifactAnomaly]()
          if let artifactIndex = try artifactManager.loadArtifactIndexIfPresent(at: record.run.indexPath) {
            anomalies = artifactIndex.anomalies
          }
          subjectAnomalies.append(contentsOf: anomalies)
          let planOutcome: SubjectRunOutcome = result.exitStatus == 0 ? .success : .failure
          planResults.append(
            ValidationPlanResult(
              plan: testPlan,
              destination: destination.displayName,
              outcome: planOutcome,
              artifactRoot: planRoot.path,
              includesAccessibilityCoverage: testPlanURL.includesAccessibilityCoverage
            )
          )
          combinedLogs.append(
            "plan \(testPlan) destination \(destination.displayName) outcome \(planOutcome.rawValue) summary \(record.run.summaryPath.path)"
          )
          createdEntries.append(
            ArtifactIndexEntry(
              name: planSlug,
              relativePath: "plans/\(planSlug)",
              kind: "directory",
              createdAt: DateFormatting.iso8601(endedAt)
            )
          )
        }
      }

      let processLogPath = subjectRoot.appendingPathComponent("process-stdout-stderr.txt")
      let summaryPath = subjectRoot.appendingPathComponent("summary.txt")
      let summaryJSONPath = subjectRoot.appendingPathComponent("summary.json")
      let indexPath = subjectRoot.appendingPathComponent("index.json")
      let createdAt = DateFormatting.iso8601(Date())
      var hasPlanFailure = false
      var includesAccessibilityCoverage = false
      var hasAccessibilityCoverageFailure = false
      for planResult in planResults {
        if planResult.outcome == .failure {
          hasPlanFailure = true
        }
        if planResult.includesAccessibilityCoverage {
          includesAccessibilityCoverage = true
          if planResult.outcome == .failure {
            hasAccessibilityCoverageFailure = true
          }
        }
      }
      if hasPlanFailure {
        subjectAnomalies.append(
          ArtifactAnomaly(
            code: "xcode_test_plan_execution_failed",
            message: "One or more required Xcode validation plans failed.",
            phase: "validate"
          )
        )
      }
      if !includesAccessibilityCoverage {
        subjectAnomalies.append(
          ArtifactAnomaly(
            code: "missing_accessibility_validation_plan",
            message: "No checked-in validation plan covered the required UI accessibility suite.",
            phase: "validate"
          )
        )
      } else if hasAccessibilityCoverageFailure {
        subjectAnomalies.append(
          ArtifactAnomaly(
            code: "accessibility_validation_plan_failed",
            message: "One or more required accessibility validation plans failed.",
            phase: "validate"
          )
        )
      }
      let outcome: SubjectRunOutcome
      var hasValidationFailure = false
      for anomaly in subjectAnomalies {
        if anomaly.code == "xcode_test_plan_execution_failed"
          || anomaly.code == "missing_accessibility_validation_plan"
          || anomaly.code == "accessibility_validation_plan_failed"
        {
          hasValidationFailure = true
          break
        }
      }
      if hasValidationFailure {
        outcome = .failure
      } else {
        outcome = .success
      }
      let subjectSummary = AggregatedValidationSubjectSummary(
        command: .validate,
        subject: subject.name,
        outcome: outcome,
        plans: planResults,
        artifactRoot: subjectRoot.path
      )

      try fileManager.createDirectory(
        at: subjectRoot.appendingPathComponent("plans", isDirectory: true),
        withIntermediateDirectories: true
      )
      try combinedLogs.joined(separator: "\n").write(
        to: processLogPath,
        atomically: true,
        encoding: .utf8
      )
      var summaryLines = [
        "command: validate",
        "subject: \(subject.name)",
        "outcome: \(outcome.rawValue)",
        "artifact_root: \(subjectRoot.path)",
      ]
      for planResult in planResults {
        summaryLines.append(
          "plan \(planResult.plan) destination \(planResult.destination) outcome \(planResult.outcome.rawValue)"
        )
      }
      try summaryLines.joined(separator: "\n").write(
        to: summaryPath,
        atomically: true,
        encoding: .utf8
      )
      try (encodePrettyJSON(subjectSummary) + "\n").write(
        to: summaryJSONPath,
        atomically: true,
        encoding: .utf8
      )
      try (encodePrettyJSON(
        SharedRunIndex(
          command: .validate,
          runID: subject.name,
          startedAt: createdAt,
          endedAt: createdAt,
          entries: [
            ArtifactIndexEntry(
              name: "summary.txt",
              relativePath: "summary.txt",
              kind: "file",
              createdAt: createdAt
            ),
            ArtifactIndexEntry(
              name: "summary.json",
              relativePath: "summary.json",
              kind: "file",
              createdAt: createdAt
            ),
            ArtifactIndexEntry(
              name: "index.json",
              relativePath: "index.json",
              kind: "file",
              createdAt: createdAt
            ),
            ArtifactIndexEntry(
              name: "process-stdout-stderr.txt",
              relativePath: "process-stdout-stderr.txt",
              kind: "file",
              createdAt: createdAt
            ),
            ArtifactIndexEntry(
              name: "plans",
              relativePath: "plans",
              kind: "directory",
              createdAt: createdAt
            ),
          ] + createdEntries,
          anomalies: subjectAnomalies
        )
      ) + "\n").write(
        to: indexPath,
        atomically: true,
        encoding: .utf8
      )

      let artifactSet = try loadSubjectArtifactSet(subject: subject.name, subjectRoot: subjectRoot)
      return SubjectRunResult(subject: subject.name, outcome: outcome, artifactSet: artifactSet)
    } catch {
      let artifactSet = try writeFailedSubjectArtifacts(
        subject: subject,
        command: .validate,
        subjectRoot: subjectRoot,
        reason: error.localizedDescription
      )
      return SubjectRunResult(subject: subject.name, outcome: .failure, artifactSet: artifactSet)
    }
  }

}
