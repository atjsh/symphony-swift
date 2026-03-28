import Foundation

public enum HarnessCommand: String, Codable, CaseIterable, Sendable {
  case build
  case test
  case run
  case validate
  case doctor
}

public enum ValidationPolicy: String, Codable, CaseIterable, Hashable, Sendable {
  case coverage
  case artifacts
  case environment
  case xcodeTestPlans
  case accessibility
}

public enum CapabilityStatus: String, Codable, Hashable, Sendable {
  case supported
  case skipped
  case unsupported
}

public struct CapabilityOutcome: Codable, Hashable, Sendable {
  public let status: CapabilityStatus
  public let reason: String?

  public init(status: CapabilityStatus, reason: String? = nil) {
    self.status = status
    self.reason = reason
  }
}

public struct ExecutionRequest: Codable, Hashable, Sendable {
  public let command: HarnessCommand
  public let subjects: [String]
  public let explicitTestSubjects: [String]
  public let environment: [String: String]
  public let outputMode: XcodeOutputMode

  public init(
    command: HarnessCommand,
    subjects: [String],
    explicitTestSubjects: [String] = [],
    environment: [String: String] = [:],
    outputMode: XcodeOutputMode = .filtered
  ) {
    self.command = command
    self.subjects = subjects
    self.explicitTestSubjects = explicitTestSubjects
    self.environment = environment
    self.outputMode = outputMode
  }
}

public struct ScheduledSubjectRun: Codable, Hashable, Sendable {
  public let subject: HarnessSubject
  public let command: HarnessCommand
  public let schedulerLane: String
  public let requiresExclusiveDestination: Bool
  public let capabilityOutcome: CapabilityOutcome

  public init(
    subject: HarnessSubject,
    command: HarnessCommand,
    schedulerLane: String,
    requiresExclusiveDestination: Bool,
    capabilityOutcome: CapabilityOutcome
  ) {
    self.subject = subject
    self.command = command
    self.schedulerLane = schedulerLane
    self.requiresExclusiveDestination = requiresExclusiveDestination
    self.capabilityOutcome = capabilityOutcome
  }
}

public struct ExecutionPlan: Codable, Hashable, Sendable {
  public let subjectRuns: [ScheduledSubjectRun]
  public let sharedRunRoot: URL
  public let defaultedSubjects: [String]
  public let validationPolicies: [ValidationPolicy]

  public init(
    subjectRuns: [ScheduledSubjectRun],
    sharedRunRoot: URL,
    defaultedSubjects: [String] = [],
    validationPolicies: [ValidationPolicy] = []
  ) {
    self.subjectRuns = subjectRuns
    self.sharedRunRoot = sharedRunRoot
    self.defaultedSubjects = defaultedSubjects
    self.validationPolicies = validationPolicies
  }
}

public struct SubjectArtifactSet: Codable, Hashable, Sendable {
  public let subject: String
  public let artifactRoot: URL
  public let summaryPath: URL
  public let indexPath: URL
  public let coverageTextPath: URL?
  public let coverageJSONPath: URL?
  public let resultBundlePath: URL?
  public let logPath: URL
  public let anomalies: [ArtifactAnomaly]

  public init(
    subject: String,
    artifactRoot: URL,
    summaryPath: URL,
    indexPath: URL,
    coverageTextPath: URL?,
    coverageJSONPath: URL?,
    resultBundlePath: URL?,
    logPath: URL,
    anomalies: [ArtifactAnomaly] = []
  ) {
    self.subject = subject
    self.artifactRoot = artifactRoot
    self.summaryPath = summaryPath
    self.indexPath = indexPath
    self.coverageTextPath = coverageTextPath
    self.coverageJSONPath = coverageJSONPath
    self.resultBundlePath = resultBundlePath
    self.logPath = logPath
    self.anomalies = anomalies
  }
}

public enum SubjectRunOutcome: String, Codable, Hashable, Sendable {
  case success
  case failure
  case skipped
  case unsupported
}

public struct SubjectRunResult: Codable, Hashable, Sendable {
  public let subject: String
  public let outcome: SubjectRunOutcome
  public let artifactSet: SubjectArtifactSet

  public init(subject: String, outcome: SubjectRunOutcome, artifactSet: SubjectArtifactSet) {
    self.subject = subject
    self.outcome = outcome
    self.artifactSet = artifactSet
  }
}

public struct SharedRunSummary: Codable, Hashable, Sendable {
  public let command: HarnessCommand
  public let runID: String
  public let startedAt: Date
  public let endedAt: Date
  public let subjects: [String]
  public let subjectResults: [SubjectRunResult]
  public let anomalies: [ArtifactAnomaly]

  public init(
    command: HarnessCommand,
    runID: String,
    startedAt: Date,
    endedAt: Date,
    subjects: [String],
    subjectResults: [SubjectRunResult],
    anomalies: [ArtifactAnomaly] = []
  ) {
    self.command = command
    self.runID = runID
    self.startedAt = startedAt
    self.endedAt = endedAt
    self.subjects = subjects
    self.subjectResults = subjectResults
    self.anomalies = anomalies
  }
}
