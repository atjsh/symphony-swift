import Foundation

#if os(macOS)


struct ValidationScenario: Sendable {
  let subject: ValidationSubject
  let phase: RunPhase
  let destination: ValidationDestination
  let plan: ValidationPlan
  let runName: String
  let onlyTesting: [String]
  let exportAttachments: Bool
  let recordVideo: Bool
  let captureSimulatorScreenshot: Bool
}

extension ValidationScenario {
  var logDescription: String {
    "subject=\(subject.rawValue) phase=\(phase.rawValue) destination=\(destination.platformDirectoryName) plan=\(plan.slug) run=\(runName)"
  }

  var defaultTestIdentifier: String {
    onlyTesting.first ?? subject.configuration.planConfiguration(for: plan).testPlanName
  }
}

struct ValidationBuildCacheKey: Hashable, Sendable {
  let destination: ValidationDestination
  let plan: ValidationPlan
  let buildProfile: ValidationBuildProfile
}

struct CachedValidationBuildArtifact: Sendable {
  let derivedDataPath: URL
  let xctestrunPath: URL
}

enum BuildPreparationResult: Sendable {
  case ready(CachedValidationBuildArtifact)
  case failed(String)
}

struct ValidationScenarioOutcome {
  let runRecord: ValidationRunRecord
  let mediaArtifacts: [MediaArtifact]
  let auditIssues: [AuditIssueRecord]
}

struct ValidationExecutionPlan: Sendable {
  let mitigationScenarios: [ValidationScheduledScenario]
  let postMitigationLanes: [ValidationLanePlan]
  let warmBuildScenarios: [ValidationScheduledScenario]
}

struct ValidationLanePlan: Sendable {
  let lane: ValidationDestinationLane
  let scenarios: [ValidationScheduledScenario]
}

struct ValidationDestinationLane: Hashable, Sendable {
  let id: String
  let destination: ValidationDestination
  let isSimulator: Bool

  init(destination: ValidationDestination) {
    self.destination = destination
    self.isSimulator = destination.simulatorUDID != nil
    switch destination {
    case .macOS:
      self.id = "macos"
    case .iPhoneSimulator:
      self.id = "simulator:E09AB2DE-2B82-49E2-8119-6C2FD1227C04"
    case .iPadSimulator:
      self.id = "simulator:FB1A9F71-0620-4314-BF84-1BD1C46ABF5D"
    }
  }
}

struct ValidationScheduledScenario: Sendable {
  let index: Int
  let scenario: ValidationScenario
  let lane: ValidationDestinationLane
  let buildKey: ValidationBuildCacheKey
  let maxAttempts: Int
}

struct ValidationLaneState: Sendable {
  var hasBooted = false
  var requiresRebootBeforeNextScenario = false
}

struct ValidationAttemptOutcome: Sendable {
  let runRecord: ValidationRunRecord
  let immediateMediaArtifacts: [MediaArtifact]
  let exportWork: ValidationExportWork?
}

struct ValidationExportWork: Sendable {
  let scheduledScenario: ValidationScheduledScenario
  let context: ValidationExecutionContext
  let runRecord: ValidationRunRecord
}

struct ValidationQueuedScenarioOutcome: Sendable {
  let indexedOutcome: ValidationIndexedScenarioOutcome
  let postProcessingTask: Task<ValidationPostProcessingOutcome, Never>?
}

struct ValidationIndexedScenarioOutcome: Sendable {
  let index: Int
  let runRecord: ValidationRunRecord
  let mediaArtifacts: [MediaArtifact]
}

struct ValidationPostProcessingOutcome: Sendable {
  let index: Int
  let mediaArtifacts: [MediaArtifact]
  let auditIssues: [AuditIssueRecord]
}

struct ValidationLaneExecutionResult: Sendable {
  let indexedOutcomes: [ValidationIndexedScenarioOutcome]
  let postProcessingTasks: [Task<ValidationPostProcessingOutcome, Never>]
  let error: Error?
}

struct ValidationPostMitigationExecutionResult: Sendable {
  let indexedOutcomes: [ValidationIndexedScenarioOutcome]
  let postProcessingTasks: [Task<ValidationPostProcessingOutcome, Never>]
  let firstError: Error?
}

final class ValidationSynchronousResultBox<T>: @unchecked Sendable {
  let semaphore = DispatchSemaphore(value: 0)
  var result: Result<T, Error>?
}

actor ValidationAsyncLimiter {
  let limit: Int
  var availablePermits: Int
  var waiters = [CheckedContinuation<Void, Never>]()

  init(limit: Int) {
    self.limit = max(limit, 1)
    self.availablePermits = max(limit, 1)
  }

  func acquire() async {
    if availablePermits > 0 {
      availablePermits -= 1
      return
    }

    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  func release() {
    if waiters.isEmpty == false {
      let continuation = waiters.removeFirst()
      continuation.resume()
      return
    }

    availablePermits = min(availablePermits + 1, limit)
  }

  func withPermit<T: Sendable>(
    _ operation: @Sendable () async -> T
  ) async -> T {
    await acquire()
    let result = await operation()
    release()
    return result
  }

  func withThrowingPermit<T: Sendable>(
    _ operation: @Sendable () async throws -> T
  ) async throws -> T {
    await acquire()
    do {
      let result = try await operation()
      release()
      return result
    } catch {
      release()
      throw error
    }
  }
}

actor ValidationBuildArtifactStore {
  let buildLimiter: ValidationAsyncLimiter
  var cachedArtifacts = [ValidationBuildCacheKey: CachedValidationBuildArtifact]()
  var inFlightTasks = [ValidationBuildCacheKey: Task<BuildPreparationResult, Never>]()

  init(maxParallelBuilds: Int) {
    self.buildLimiter = ValidationAsyncLimiter(limit: maxParallelBuilds)
  }

  func prepareArtifact(
    for key: ValidationBuildCacheKey,
    logger: ValidationRunLogger,
    operation: @escaping @Sendable () async -> BuildPreparationResult
  ) async -> BuildPreparationResult {
    if let cachedArtifact = cachedArtifacts[key] {
      logger.info(
        """
        Reusing build artifact destination=\(key.destination.platformDirectoryName) plan=\(key.plan.slug) build_profile=\(key.buildProfile.rawValue)
        """
      )
      logger.debug(
        """
        Reusing build artifact derived_data_path=\(cachedArtifact.derivedDataPath.path) xctestrun_path=\(cachedArtifact.xctestrunPath.path)
        """
      )
      return .ready(cachedArtifact)
    }

    if let inFlightTask = inFlightTasks[key] {
      logger.info(
        """
        Waiting for in-flight build artifact destination=\(key.destination.platformDirectoryName) plan=\(key.plan.slug) build_profile=\(key.buildProfile.rawValue)
        """
      )
      return await inFlightTask.value
    }

    let task = Task<BuildPreparationResult, Never> {
      await buildLimiter.withPermit {
        await operation()
      }
    }
    inFlightTasks[key] = task
    let result = await task.value
    inFlightTasks[key] = nil
    if case .ready(let cachedArtifact) = result {
      cachedArtifacts[key] = cachedArtifact
    }
    return result
  }
}

struct XCResultSummaryPayload: Decodable {
  struct TestFailure: Decodable {
    let failureText: String
    let testIdentifierString: String?
    let testIdentifierURL: String?
  }

  let result: String
  let passedTests: Int
  let failedTests: Int
  let testFailures: [TestFailure]
}

struct AttachmentAuditManifest: Decodable {
  struct Attachment: Decodable {
    let exportedFileName: String
    let suggestedHumanReadableName: String
  }

  let attachments: [Attachment]
  let testIdentifier: String
}

enum XCResultTestsPayloadParser {
  static func makeSummary(from data: Data) throws -> ValidationTestSummary {
    let payload = try JSONDecoder().decode(XCResultTestsPayload.self, from: data)
    var passedTests = 0
    var failedTests = 0
    var failures = [ValidationTestFailure]()

    for node in payload.testNodes {
      accumulate(node, passedTests: &passedTests, failedTests: &failedTests, failures: &failures)
    }

    let result = payload.testNodes.contains(where: { $0.result == "Failed" }) || failedTests > 0
      ? "Failed" : "Passed"
    return ValidationTestSummary(
      result: result,
      passedTests: passedTests,
      failedTests: failedTests,
      testFailures: failures
    )
  }

  static func accumulate(
    _ node: XCResultTestNode,
    passedTests: inout Int,
    failedTests: inout Int,
    failures: inout [ValidationTestFailure]
  ) {
    if node.nodeType == "Test Case" {
      switch node.result {
      case "Passed":
        passedTests += 1
      case "Failed":
        failedTests += 1
        failures.append(
          ValidationTestFailure(
            testIdentifier: node.nodeIdentifier ?? node.nodeIdentifierURL ?? node.name,
            failureText: failureText(for: node)
          )
        )
      default:
        break
      }
    }

    for child in node.children ?? [] {
      accumulate(child, passedTests: &passedTests, failedTests: &failedTests, failures: &failures)
    }
  }

  static func failureText(for node: XCResultTestNode) -> String {
    let messages = failureMessages(in: node)
    if messages.isEmpty == false {
      return messages.joined(separator: "\n")
    }
    if let details = node.details?.trimmingCharacters(in: .whitespacesAndNewlines),
      details.isEmpty == false
    {
      return details
    }
    return node.name
  }

  static func failureMessages(in node: XCResultTestNode) -> [String] {
    var messages = [String]()

    if node.nodeType == "Failure Message" {
      let detailMessage = node.details?.trimmingCharacters(in: .whitespacesAndNewlines)
      let message = (detailMessage?.isEmpty == false ? detailMessage : node.name) ?? node.name
      messages.append(message)
    }

    for child in node.children ?? [] {
      messages.append(contentsOf: failureMessages(in: child))
    }

    return messages
  }
}

struct XCResultTestsPayload: Decodable {
  let testNodes: [XCResultTestNode]
}

struct XCResultTestNode: Decodable {
  let nodeIdentifier: String?
  let nodeIdentifierURL: String?
  let nodeType: String
  let name: String
  let details: String?
  let result: String?
  let children: [XCResultTestNode]?
}

struct ValidationRunnerError: Error, LocalizedError {
  let message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? {
    message
  }
}

#endif
