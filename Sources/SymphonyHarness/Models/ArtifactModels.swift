import Foundation
import SymphonyShared

public struct HarnessReport: Codable, Hashable, Sendable {
  public let minimumCoveragePercent: Double
  public let testsInvocation: String
  public let coveragePathInvocation: String
  public let packageCoverage: PackageCoverageReport
  public let clientCoverageInvocation: String?
  public let clientCoverage: CoverageReport?
  public let clientCoverageSkipReason: String?
  public let serverCoverageInvocation: String
  public let serverCoverage: CoverageReport
  public let packageFileViolations: [HarnessCoverageViolation]
  public let clientTargetViolations: [HarnessCoverageViolation]
  public let clientFileViolations: [HarnessCoverageViolation]
  public let serverTargetViolations: [HarnessCoverageViolation]
  public let serverFileViolations: [HarnessCoverageViolation]

  public init(
    minimumCoveragePercent: Double,
    testsInvocation: String,
    coveragePathInvocation: String,
    packageCoverage: PackageCoverageReport,
    clientCoverageInvocation: String?,
    clientCoverage: CoverageReport?,
    clientCoverageSkipReason: String? = nil,
    serverCoverageInvocation: String,
    serverCoverage: CoverageReport,
    packageFileViolations: [HarnessCoverageViolation],
    clientTargetViolations: [HarnessCoverageViolation],
    clientFileViolations: [HarnessCoverageViolation],
    serverTargetViolations: [HarnessCoverageViolation],
    serverFileViolations: [HarnessCoverageViolation]
  ) {
    self.minimumCoveragePercent = minimumCoveragePercent
    self.testsInvocation = testsInvocation
    self.coveragePathInvocation = coveragePathInvocation
    self.packageCoverage = packageCoverage
    self.clientCoverageInvocation = clientCoverageInvocation
    self.clientCoverage = clientCoverage
    self.clientCoverageSkipReason = clientCoverageSkipReason
    self.serverCoverageInvocation = serverCoverageInvocation
    self.serverCoverage = serverCoverage
    self.packageFileViolations = packageFileViolations
    self.clientTargetViolations = clientTargetViolations
    self.clientFileViolations = clientFileViolations
    self.serverTargetViolations = serverTargetViolations
    self.serverFileViolations = serverFileViolations
  }

  public var violations: [HarnessCoverageViolation] {
    packageFileViolations + clientTargetViolations + clientFileViolations + serverTargetViolations
      + serverFileViolations
  }

  public var meetsCoverageThreshold: Bool {
    violations.isEmpty
  }
}

public struct ArtifactRun: Codable, Hashable, Sendable {
  public let command: ArtifactCommand
  public let runID: String
  public let timestamp: String
  public let artifactRoot: URL
  public let summaryPath: URL
  public let indexPath: URL

  public init(
    command: ArtifactCommand,
    runID: String,
    timestamp: String,
    artifactRoot: URL,
    summaryPath: URL, indexPath: URL
  ) {
    self.command = command
    self.runID = runID
    self.timestamp = timestamp
    self.artifactRoot = artifactRoot
    self.summaryPath = summaryPath
    self.indexPath = indexPath
  }
}

public struct ArtifactIndexEntry: Codable, Hashable, Sendable {
  public let name: String
  public let relativePath: String
  public let kind: String
  public let createdAt: String
  public let anomaly: ArtifactAnomaly?

  public init(
    name: String, relativePath: String, kind: String, createdAt: String,
    anomaly: ArtifactAnomaly? = nil
  ) {
    self.name = name
    self.relativePath = relativePath
    self.kind = kind
    self.createdAt = createdAt
    self.anomaly = anomaly
  }
}

public struct ArtifactIndex: Codable, Hashable, Sendable {
  public let entries: [ArtifactIndexEntry]
  public let command: ArtifactCommand
  public let runID: String
  public let timestamp: String
  public let anomalies: [ArtifactAnomaly]

  public init(
    entries: [ArtifactIndexEntry],
    command: ArtifactCommand,
    runID: String,
    timestamp: String,
    anomalies: [ArtifactAnomaly]
  ) {
    self.entries = entries
    self.command = command
    self.runID = runID
    self.timestamp = timestamp
    self.anomalies = anomalies
  }
}

public struct ArtifactAnomaly: Codable, Hashable, Sendable {
  public let code: String
  public let message: String
  public let phase: String
  public let subject: String?

  public init(code: String, message: String, phase: String, subject: String? = nil) {
    self.code = code
    self.message = message
    self.phase = phase
    self.subject = subject
  }
}

public enum RuntimeTarget: String, Codable, CaseIterable, Sendable {
  case server
  case client
}

public struct RuntimeEndpoint: Codable, Hashable, Sendable {
  public let scheme: String
  public let host: String
  public let port: Int

  public init(scheme: String = "http", host: String = "localhost", port: Int = 8080) throws {
    let endpoint = try ServerEndpoint(scheme: scheme, host: host, port: port)
    self.scheme = endpoint.scheme
    self.host = endpoint.host
    self.port = endpoint.port
  }

  public init(serverEndpoint: ServerEndpoint) {
    self.scheme = serverEndpoint.scheme
    self.host = serverEndpoint.host
    self.port = serverEndpoint.port
  }

  public var url: URL? {
    try? ServerEndpoint(scheme: scheme, host: host, port: port).url
  }

  public var serverEndpoint: ServerEndpoint {
    get throws {
      try ServerEndpoint(scheme: scheme, host: host, port: port)
    }
  }
}

public struct LaunchConfiguration: Codable, Hashable, Sendable {
  public let target: RuntimeTarget
  public let scheme: String
  public let destination: ResolvedDestination
  public let endpoint: RuntimeEndpoint
  public let environment: [String: String]

  public init(
    target: RuntimeTarget, scheme: String, destination: ResolvedDestination,
    endpoint: RuntimeEndpoint, environment: [String: String]
  ) {
    self.target = target
    self.scheme = scheme
    self.destination = destination
    self.endpoint = endpoint
    self.environment = environment
  }
}

public enum DiagnosticSeverity: String, Codable, CaseIterable, Comparable, Sendable {
  case error
  case warning
  case info

  public static func < (lhs: DiagnosticSeverity, rhs: DiagnosticSeverity) -> Bool {
    lhs.sortRank < rhs.sortRank
  }

  private var sortRank: Int {
    switch self {
    case .error:
      return 0
    case .warning:
      return 1
    case .info:
      return 2
    }
  }
}

public struct DiagnosticIssue: Codable, Hashable, Sendable {
  public let severity: DiagnosticSeverity
  public let code: String
  public let message: String
  public let suggestedFix: String?

  public init(
    severity: DiagnosticSeverity, code: String, message: String, suggestedFix: String? = nil
  ) {
    self.severity = severity
    self.code = code
    self.message = message
    self.suggestedFix = suggestedFix
  }
}

public struct DiagnosticsReport: Codable, Hashable, Sendable {
  public let issues: [DiagnosticIssue]
  public let notes: [String]
  public let checkedPaths: [String]
  public let checkedExecutables: [String]
  public let xcodeAvailability: Bool
  public let justAvailability: Bool

  public init(
    issues: [DiagnosticIssue],
    notes: [String] = [],
    checkedPaths: [String],
    checkedExecutables: [String],
    xcodeAvailability: Bool = false,
    justAvailability: Bool = false
  ) {
    self.issues = issues.sorted { lhs, rhs in
      if lhs.severity == rhs.severity {
        return lhs.code < rhs.code
      }
      return lhs.severity < rhs.severity
    }
    self.notes = notes
    self.checkedPaths = checkedPaths
    self.checkedExecutables = checkedExecutables
    self.xcodeAvailability = xcodeAvailability
    self.justAvailability = justAvailability
  }

  public var isHealthy: Bool {
    issues.allSatisfy { $0.severity != .error }
  }
}
