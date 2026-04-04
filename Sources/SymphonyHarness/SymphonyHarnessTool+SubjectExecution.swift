import Foundation
import SymphonyShared

extension SymphonyHarnessTool {
  public func execute(_ request: ExecutionRequest, currentDirectory: URL) throws -> String {
    switch request.command {
    case .build:
      return try executeSubjectRequest(request, startDirectory: currentDirectory)
    case .test:
      return try executeSubjectRequest(request, startDirectory: currentDirectory)
    case .run:
      return try executeSubjectRequest(request, startDirectory: currentDirectory)
    case .validate:
      return try executeSubjectRequest(request, startDirectory: currentDirectory)
    case .doctor:
      throw unsupportedSubjectBridgeError(for: request)
    }
  }

  public func build(_ request: ExecutionRequest) throws -> String {
    try executeSubjectRequest(request, startDirectory: currentWorkingDirectory())
  }

  public func test(_ request: ExecutionRequest) throws -> String {
    try executeSubjectRequest(request, startDirectory: currentWorkingDirectory())
  }

  public func run(_ request: ExecutionRequest) throws -> String {
    try executeSubjectRequest(request, startDirectory: currentWorkingDirectory())
  }

  public func validate(_ request: ExecutionRequest) throws -> String {
    try executeSubjectRequest(request, startDirectory: currentWorkingDirectory())
  }

  func currentWorkingDirectory() -> URL {
    URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
  }

  func executeSubjectRequest(_ request: ExecutionRequest, startDirectory: URL) throws -> String {
    guard request.command != .doctor else {
      throw unsupportedSubjectBridgeError(for: request)
    }

    let workspace = try workspaceDiscovery.discover(from: startDirectory)
    let capabilities = try toolchainCapabilitiesResolver.resolve()
    let startedAt = Date()
    let plan = try makeExecutionPlan(
      for: request,
      workspace: workspace,
      capabilities: capabilities,
      startedAt: startedAt
    )
    let summaryPath = plan.sharedRunRoot.appendingPathComponent("summary.txt")
    let sharedRunID = plan.sharedRunRoot.lastPathComponent

    try prepareSharedRunRoot(at: plan.sharedRunRoot)

    let subjectResults = try executePlannedSubjectRuns(
      plan: plan,
      request: request,
      workspace: workspace,
      sharedRunID: sharedRunID
    )
    var aggregateAnomalies = [ArtifactAnomaly]()
    var extraSummaryLines = [String]()
    var firstFailureMessage: String?

    for (index, scheduledRun) in plan.subjectRuns.enumerated() {
      let subjectResult = subjectResults[index]
      aggregateAnomalies.append(
        contentsOf: subjectResult.artifactSet.anomalies.map {
          $0.subject == nil
            ? ArtifactAnomaly(
              code: $0.code,
              message: $0.message,
              phase: $0.phase,
              subject: scheduledRun.subject.name
            ) : $0
        }
      )
      if firstFailureMessage == nil, subjectResult.outcome == .failure {
        firstFailureMessage = "\(request.command.rawValue) failed for \(scheduledRun.subject.name)."
      }
    }

    if isDefaultRepositoryValidate(request) {
      let policyOutcome = try executeRepositoryValidationPolicies(
        request: request,
        workspace: workspace,
        capabilities: capabilities,
        subjectResults: subjectResults
      )
      aggregateAnomalies.append(contentsOf: policyOutcome.anomalies)
      extraSummaryLines.append(contentsOf: policyOutcome.summaryLines)
      if firstFailureMessage == nil {
        firstFailureMessage = policyOutcome.failureMessage
      }
    }

    let endedAt = Date()
    let sharedSummary = SharedRunSummary(
      command: request.command,
      runID: plan.sharedRunRoot.lastPathComponent,
      startedAt: startedAt,
      endedAt: endedAt,
      subjects: plan.subjectRuns.map(\.subject.name),
      subjectResults: subjectResults,
      anomalies: aggregateAnomalies
    )
    try writeSharedRunArtifacts(
      plan: plan,
      request: request,
      summary: sharedSummary,
      startedAt: startedAt,
      endedAt: endedAt,
      extraSummaryLines: extraSummaryLines
    )

    if let firstFailureMessage {
      throw SymphonyHarnessCommandFailure(message: firstFailureMessage, summaryPath: summaryPath)
    }
    return summaryPath.path
  }

  func executePlannedSubjectRuns(
    plan: ExecutionPlan,
    request: ExecutionRequest,
    workspace: WorkspaceContext,
    sharedRunID: String
  ) throws -> [SubjectRunResult] {
    guard plan.subjectRuns.count > 1, request.command != .validate else {
      return try plan.subjectRuns.enumerated().map { index, scheduledRun in
        try executeScheduledSubjectRun(
          scheduledRun,
          for: request,
          workspace: workspace,
          sharedRunRoot: plan.sharedRunRoot,
          sharedRunID: sharedRunID,
          workerID: index
        )
      }
    }

    let concurrentQueue = DispatchQueue(
      label: "symphony.harness.subject-runs",
      attributes: .concurrent
    )
    let exclusiveQueue = DispatchQueue(label: "symphony.harness.subject-runs.exclusive")
    let group = DispatchGroup()
    let collector = ScheduledRunCollector(count: plan.subjectRuns.count)

    for (index, scheduledRun) in plan.subjectRuns.enumerated() {
      group.enter()
      let queue = scheduledRun.requiresExclusiveDestination ? exclusiveQueue : concurrentQueue
      queue.async { [self] in
        defer { group.leave() }
        do {
          let result = try executeScheduledSubjectRun(
            scheduledRun,
            for: request,
            workspace: workspace,
            sharedRunRoot: plan.sharedRunRoot,
            sharedRunID: sharedRunID,
            workerID: index
          )
          collector.store(result: result, at: index)
        } catch {
          statusSink(
            "[harness] subject \(scheduledRun.subject.name) failed: \(error.localizedDescription)")
        }
      }
    }

    let groupTimeout: TimeInterval = request.command == .build ? 180 : 600
    let waitResult = group.wait(timeout: .now() + groupTimeout)
    if waitResult == .timedOut {
      let pendingSubjects = collector.pendingIndices(total: plan.subjectRuns.count)
        .map { plan.subjectRuns[$0].subject.name }
      let message =
        "[harness] subject execution timed out after \(Int(groupTimeout))s — pending subjects: \(pendingSubjects.joined(separator: ", "))"
      statusSink(message)
      throw SymphonyHarnessCommandFailure(message: message)
    }

    return try collector.orderedResults()
  }

  func makeExecutionPlan(
    for request: ExecutionRequest,
    workspace: WorkspaceContext,
    capabilities: ToolchainCapabilities,
    startedAt: Date
  ) throws -> ExecutionPlan {
    let productionSubjects = try request.subjects.map(resolveHarnessSubject(named:))
    let explicitTestSubjects = try request.explicitTestSubjects.map(resolveHarnessSubject(named:))

    for subject in productionSubjects where subject.kind == .test || subject.kind == .uiTest {
      throw unsupportedSubjectBridgeError(forSubject: subject.name)
    }
    for subject in explicitTestSubjects where subject.kind != .test && subject.kind != .uiTest {
      throw unsupportedSubjectBridgeError(forSubject: subject.name)
    }

    let plannedSubjects: [HarnessSubject]
    let defaultedSubjects: [String]

    if request.command == .build {
      guard explicitTestSubjects.isEmpty, !productionSubjects.isEmpty else {
        throw unsupportedSubjectBridgeError(for: request)
      }
      plannedSubjects = uniqueSubjects(productionSubjects)
      defaultedSubjects = []
    } else if request.command == .run {
      guard explicitTestSubjects.isEmpty, productionSubjects.count == 1 else {
        throw unsupportedSubjectBridgeError(for: request)
      }
      plannedSubjects = productionSubjects
      defaultedSubjects = []
    } else {
      if productionSubjects.isEmpty, explicitTestSubjects.isEmpty {
        let defaults = defaultTestProductionSubjects(capabilities: capabilities)
        plannedSubjects = defaults
        defaultedSubjects = defaults.map(\.name)
      } else {
        plannedSubjects = uniqueSubjects(productionSubjects + explicitTestSubjects)
        defaultedSubjects = []
      }
    }
    let validationPolicies: [ValidationPolicy]
    if request.command == .validate {
      validationPolicies = isDefaultRepositoryValidate(request)
        ? [.coverage, .artifacts, .environment, .xcodeTestPlans, .accessibility]
        : [.coverage, .artifacts, .environment]
    } else {
      validationPolicies = []
    }
    let runID = makeSharedRunID(command: request.command, date: startedAt)
    let sharedRunRoot = workspace.buildStateRoot.appendingPathComponent(
      "runs/\(runID)",
      isDirectory: true
    )

    let subjectRuns = plannedSubjects.map { subject in
      ScheduledSubjectRun(
        subject: subject,
        command: request.command,
        schedulerLane: schedulerLane(for: subject),
        requiresExclusiveDestination: subject.requiresExclusiveDestination,
        capabilityOutcome: capabilityOutcome(
          for: subject,
          command: request.command,
          capabilities: capabilities
        )
      )
    }

    return ExecutionPlan(
      subjectRuns: subjectRuns,
      sharedRunRoot: sharedRunRoot,
      defaultedSubjects: defaultedSubjects,
      validationPolicies: validationPolicies
    )
  }

  func executeScheduledSubjectRun(
    _ scheduledRun: ScheduledSubjectRun,
    for request: ExecutionRequest,
    workspace: WorkspaceContext,
    sharedRunRoot: URL,
    sharedRunID: String,
    workerID: Int
  ) throws -> SubjectRunResult {
    let subject = scheduledRun.subject
    let subjectRoot = sharedRunRoot.appendingPathComponent(
      "subjects/\(subject.name)",
      isDirectory: true
    )

    guard scheduledRun.capabilityOutcome.status == .supported else {
      let skippedOutcome: SubjectRunOutcome =
        scheduledRun.capabilityOutcome.status == .skipped ? .skipped : .unsupported
      var skippedReason = Self.noXcodeMessage
      if let reason = scheduledRun.capabilityOutcome.reason {
        skippedReason = reason
      }
      let artifactSet = try writeSkippedSubjectArtifacts(
        subject: subject,
        command: request.command,
        subjectRoot: subjectRoot,
        outcome: skippedOutcome,
        reason: skippedReason
      )
      return SubjectRunResult(
        subject: subject.name,
        outcome: skippedOutcome,
        artifactSet: artifactSet
      )
    }

    if isDefaultRepositoryValidate(request), subject.name == "SymphonySwiftUIApp" {
      return try executeDefaultAppValidationSuite(
        subject: subject,
        request: request,
        workspace: workspace,
        subjectRoot: subjectRoot,
        sharedRunID: sharedRunID,
        workerID: workerID
      )
    }

    let selection = try selection(for: scheduledRun)
    let executionContext = try makeSubjectExecutionContext(
      workspace: workspace,
      subject: subject,
      command: request.command,
      sharedRunID: sharedRunID,
      workerID: workerID
    )

    do {
      if scheduledRun.command == .build {
        try executeBuildSelection(
          selection,
          request: request,
          workspace: workspace,
          executionContext: executionContext
        )
      } else if scheduledRun.command == .run {
        try executeRunSelection(
          selection,
          request: request,
          workspace: workspace,
          executionContext: executionContext
        )
      } else {
        try executeTestSelection(
          selection,
          request: request,
          workspace: workspace,
          executionContext: executionContext
        )
      }
    } catch let error as SymphonyHarnessCommandFailure {
      let artifactSet = try loadSubjectArtifactSet(subject: subject.name, subjectRoot: subjectRoot)
      _ = error
      return SubjectRunResult(subject: subject.name, outcome: .failure, artifactSet: artifactSet)
    } catch {
      let artifactSet = try writeFailedSubjectArtifacts(
        subject: subject,
        command: request.command,
        subjectRoot: subjectRoot,
        reason: error.localizedDescription
      )
      return SubjectRunResult(subject: subject.name, outcome: .failure, artifactSet: artifactSet)
    }

    let artifactSet = try loadSubjectArtifactSet(subject: subject.name, subjectRoot: subjectRoot)
    return SubjectRunResult(subject: subject.name, outcome: .success, artifactSet: artifactSet)
  }

  func selection(for scheduledRun: ScheduledSubjectRun) throws -> SubjectExecutionSelection {
    if scheduledRun.command == .build {
      return try buildSelection(for: scheduledRun.subject)
    }
    if scheduledRun.command == .run {
      return try runSelection(for: scheduledRun.subject)
    }
    return try testSelection(
      for: scheduledRun.subject,
      productionSubject: scheduledRun.subject.kind == .test || scheduledRun.subject.kind == .uiTest
        ? nil : scheduledRun.subject
    )
  }

}
