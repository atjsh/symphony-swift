import Foundation

public enum ValidationDestination: String, Codable, CaseIterable, Sendable {
  case macOS
  case iPhoneSimulator
  case iPadSimulator

  public static let defaultMatrix: [ValidationDestination] = [
    .macOS,
    .iPhoneSimulator,
    .iPadSimulator,
  ]

  public var xcodeDestination: String {
    switch self {
    case .macOS:
      "platform=macOS,arch=arm64"
    case .iPhoneSimulator:
      "platform=iOS Simulator,id=E09AB2DE-2B82-49E2-8119-6C2FD1227C04"
    case .iPadSimulator:
      "platform=iOS Simulator,id=FB1A9F71-0620-4314-BF84-1BD1C46ABF5D"
    }
  }

  public var platformDirectoryName: String {
    switch self {
    case .macOS:
      "macos"
    case .iPhoneSimulator:
      "ios"
    case .iPadSimulator:
      "ipados"
    }
  }

  public var simulatorUDID: String? {
    switch self {
    case .macOS:
      nil
    case .iPhoneSimulator:
      "E09AB2DE-2B82-49E2-8119-6C2FD1227C04"
    case .iPadSimulator:
      "FB1A9F71-0620-4314-BF84-1BD1C46ABF5D"
    }
  }

  public var displayName: String {
    switch self {
    case .macOS:
      "My Mac"
    case .iPhoneSimulator:
      "iPhone 17 Pro Max"
    case .iPadSimulator:
      "iPad Pro 13-inch (M5)"
    }
  }
}

public enum ValidationPlan: String, Codable, CaseIterable, Sendable {
  case app
  case appTests
  case uiTests

  public static let fullMatrix: [ValidationPlan] = [.app, .appTests, .uiTests]

  public var slug: String {
    switch self {
    case .app:
      "app"
    case .appTests:
      "app-tests"
    case .uiTests:
      "ui-tests"
    }
  }
}

public enum RunPhase: String, Codable, Sendable {
  case mitigation
  case richCapture
  case fullMatrix

  public var slug: String {
    switch self {
    case .mitigation:
      "mitigation"
    case .richCapture:
      "rich-capture"
    case .fullMatrix:
      "full-matrix"
    }
  }
}

public enum ValidationOutcome: String, Codable, Sendable {
  case passed
  case failed
}

public enum MediaArtifactType: String, Codable, Sendable {
  case screenshot
  case video
  case auditIssue
}

public enum ValidationArtifactRetention: String, Codable, CaseIterable, Sendable {
  case canonicalOnly = "canonical-only"
  case debugFriendly = "debug-friendly"
  case keepEverything = "keep-everything"
}

public enum ValidationBuildProfile: String, Codable, CaseIterable, Sendable {
  case fast
  case standard
}

public enum ValidationExecutionProfile: String, Codable, CaseIterable, Sendable {
  case aggressive
  case balanced
  case serial

  public var defaultConcurrency: ValidationConcurrency {
    switch self {
    case .aggressive:
      ValidationConcurrency(
        maxParallelBuilds: 3,
        maxParallelDestinations: 3,
        maxParallelSimulators: 2,
        warmBuildsBeforeMitigationPass: true
      )
    case .balanced:
      ValidationConcurrency(
        maxParallelBuilds: 2,
        maxParallelDestinations: 2,
        maxParallelSimulators: 1,
        warmBuildsBeforeMitigationPass: true
      )
    case .serial:
      ValidationConcurrency(
        maxParallelBuilds: 1,
        maxParallelDestinations: 1,
        maxParallelSimulators: 1,
        warmBuildsBeforeMitigationPass: false
      )
    }
  }
}

public struct ValidationConcurrency: Codable, Equatable, Sendable {
  public let maxParallelBuilds: Int
  public let maxParallelDestinations: Int
  public let maxParallelSimulators: Int
  public let warmBuildsBeforeMitigationPass: Bool

  public init(
    maxParallelBuilds: Int,
    maxParallelDestinations: Int,
    maxParallelSimulators: Int,
    warmBuildsBeforeMitigationPass: Bool
  ) {
    self.maxParallelBuilds = maxParallelBuilds
    self.maxParallelDestinations = maxParallelDestinations
    self.maxParallelSimulators = maxParallelSimulators
    self.warmBuildsBeforeMitigationPass = warmBuildsBeforeMitigationPass
  }
}

public struct ValidationCommand: Equatable, Sendable {
  public let executable: String
  public let arguments: [String]
  public let environment: [String: String]
  public let currentDirectory: URL

  public init(
    executable: String,
    arguments: [String],
    environment: [String: String],
    currentDirectory: URL
  ) {
    self.executable = executable
    self.arguments = arguments
    self.environment = environment
    self.currentDirectory = currentDirectory
  }
}

enum ValidationRetryPolicy {
  private static let transientSimulatorFailureFragments = [
    "Failed to establish communication with the test runner",
    "Failed to install or launch the test runner",
    "Channel disconnected",
    "Lost connection to testmanagerd",
    "The test runner exited before starting test execution",
    "Early unexpected exit, operation never finished bootstrapping",
    "signal term before establishing connection",
    "(ipc/mig) server died",
  ]

  static func maxAttempts(for destination: ValidationDestination) -> Int {
    destination.simulatorUDID == nil ? 1 : 3
  }

  static func shouldRetryScenario(
    destination: ValidationDestination,
    summary: ValidationTestSummary,
    afterAttempt attempt: Int,
    maxAttempts: Int
  ) -> Bool {
    guard attempt + 1 < maxAttempts else {
      return false
    }

    return shouldRetrySimulatorScenario(
      destination: destination,
      summary: summary
    )
  }

  static func shouldRetrySimulatorScenario(
    destination: ValidationDestination,
    summary: ValidationTestSummary
  ) -> Bool {
    guard destination.simulatorUDID != nil else {
      return false
    }

    return summary.testFailures.contains { failure in
      transientSimulatorFailureFragments.contains { fragment in
        failure.failureText.contains(fragment)
      }
    }
  }
}

public struct ValidationExecutionContext: Equatable, Sendable {
  public let artifactRoot: URL
  public let derivedDataPath: URL
  public let resultBundlePath: URL
  public let attachmentExportPath: URL
  public let mediaDirectory: URL
  public let screenshotsDirectory: URL
  public let videosDirectory: URL
  public let auditDirectory: URL

  public init(
    artifactRoot: URL,
    derivedDataPath: URL,
    resultBundlePath: URL,
    attachmentExportPath: URL,
    mediaDirectory: URL,
    screenshotsDirectory: URL,
    videosDirectory: URL,
    auditDirectory: URL
  ) {
    self.artifactRoot = artifactRoot
    self.derivedDataPath = derivedDataPath
    self.resultBundlePath = resultBundlePath
    self.attachmentExportPath = attachmentExportPath
    self.mediaDirectory = mediaDirectory
    self.screenshotsDirectory = screenshotsDirectory
    self.videosDirectory = videosDirectory
    self.auditDirectory = auditDirectory
  }
}

public struct ValidationTestFailure: Codable, Equatable, Sendable {
  public let testIdentifier: String
  public let failureText: String

  public init(testIdentifier: String, failureText: String) {
    self.testIdentifier = testIdentifier
    self.failureText = failureText
  }
}

public struct ValidationTestSummary: Codable, Equatable, Sendable {
  public let result: String
  public let passedTests: Int
  public let failedTests: Int
  public let testFailures: [ValidationTestFailure]

  public init(
    result: String,
    passedTests: Int,
    failedTests: Int,
    testFailures: [ValidationTestFailure]
  ) {
    self.result = result
    self.passedTests = passedTests
    self.failedTests = failedTests
    self.testFailures = testFailures
  }
}

public struct ValidationRunRecord: Codable, Equatable, Sendable {
  public let phase: RunPhase
  public let destination: ValidationDestination
  public let plan: ValidationPlan
  public let runName: String
  public let outcome: ValidationOutcome
  public let resultBundlePath: URL
  public let summary: ValidationTestSummary
  public let startedAt: Date
  public let endedAt: Date

  public init(
    phase: RunPhase,
    destination: ValidationDestination,
    plan: ValidationPlan,
    runName: String,
    outcome: ValidationOutcome,
    resultBundlePath: URL,
    summary: ValidationTestSummary,
    startedAt: Date,
    endedAt: Date
  ) {
    self.phase = phase
    self.destination = destination
    self.plan = plan
    self.runName = runName
    self.outcome = outcome
    self.resultBundlePath = resultBundlePath
    self.summary = summary
    self.startedAt = startedAt
    self.endedAt = endedAt
  }
}

public struct MediaArtifact: Codable, Equatable, Sendable {
  public let platform: String
  public let plan: String
  public let test: String
  public let checkpoint: String
  public let surface: String
  public let orientation: String
  public let variant: String
  public let artifactType: MediaArtifactType
  public let file: String
  public let sourceResultBundle: String

  public init(
    platform: String,
    plan: String,
    test: String,
    checkpoint: String,
    surface: String,
    orientation: String,
    variant: String,
    artifactType: MediaArtifactType,
    file: String,
    sourceResultBundle: String
  ) {
    self.platform = platform
    self.plan = plan
    self.test = test
    self.checkpoint = checkpoint
    self.surface = surface
    self.orientation = orientation
    self.variant = variant
    self.artifactType = artifactType
    self.file = file
    self.sourceResultBundle = sourceResultBundle
  }
}

public struct ValidationCanonicalMediaKey: Hashable, Sendable {
  public let platform: String
  public let plan: String
  public let checkpoint: String
  public let surface: String
  public let orientation: String
  public let variant: String
  public let artifactType: MediaArtifactType
  public let filePath: String

  public init(
    platform: String,
    plan: String,
    checkpoint: String,
    surface: String,
    orientation: String,
    variant: String,
    artifactType: MediaArtifactType,
    filePath: String
  ) {
    self.platform = platform
    self.plan = plan
    self.checkpoint = checkpoint
    self.surface = surface
    self.orientation = orientation
    self.variant = variant
    self.artifactType = artifactType
    self.filePath = Self.normalize(filePath)
  }

  public init(artifact: MediaArtifact, filePath: String? = nil) {
    self.init(
      platform: artifact.platform,
      plan: artifact.plan,
      checkpoint: artifact.checkpoint,
      surface: artifact.surface,
      orientation: artifact.orientation,
      variant: artifact.variant,
      artifactType: artifact.artifactType,
      filePath: filePath ?? artifact.file
    )
  }

  private static func normalize(_ filePath: String) -> String {
    let expandedPath = NSString(string: filePath).expandingTildeInPath
    if expandedPath.hasPrefix("/") {
      return URL(fileURLWithPath: expandedPath).standardizedFileURL.path
    }

    return filePath
      .replacingOccurrences(of: "\\", with: "/")
      .replacingOccurrences(of: "./", with: "", options: .anchored)
  }
}

public extension MediaArtifact {
  var canonicalMediaKey: ValidationCanonicalMediaKey {
    ValidationCanonicalMediaKey(artifact: self)
  }
}

public typealias RunManifest = [MediaArtifact]

public struct AuditIssueRecord: Codable, Equatable, Sendable {
  public let platform: String
  public let plan: String
  public let test: String
  public let message: String
  public let checkpoint: String?
  public let file: String
  public let sourceResultBundle: String

  public init(
    platform: String,
    plan: String,
    test: String,
    message: String,
    checkpoint: String?,
    file: String,
    sourceResultBundle: String
  ) {
    self.platform = platform
    self.plan = plan
    self.test = test
    self.message = message
    self.checkpoint = checkpoint
    self.file = file
    self.sourceResultBundle = sourceResultBundle
  }
}

public enum ValidationStatus: String, Codable, Sendable {
  case passed
  case failed
  case blocked
}

public struct ValidationSummary: Codable, Equatable, Sendable {
  public let outputRoot: String
  public let status: ValidationStatus
  public let runRecords: [ValidationRunRecord]
  public let mediaArtifacts: [MediaArtifact]
  public let auditIssues: [AuditIssueRecord]
  public let unresolvedBlockers: [String]

  public init(
    outputRoot: String,
    status: ValidationStatus,
    runRecords: [ValidationRunRecord],
    mediaArtifacts: [MediaArtifact],
    auditIssues: [AuditIssueRecord],
    unresolvedBlockers: [String]
  ) {
    self.outputRoot = outputRoot
    self.status = status
    self.runRecords = runRecords
    self.mediaArtifacts = mediaArtifacts
    self.auditIssues = auditIssues
    self.unresolvedBlockers = unresolvedBlockers
  }
}
