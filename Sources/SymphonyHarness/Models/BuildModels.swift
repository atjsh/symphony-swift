import Foundation
import SymphonyShared

public enum BuildCommandFamily: String, Codable, CaseIterable, Sendable {
  case build
  case test
  case run
  case harness
}

public enum ProductBackend: String, Codable, CaseIterable, Sendable {
  case xcode
  case swiftPM
}

public enum ProductKind: String, Codable, CaseIterable, Sendable {
  case server
  case client

  public var defaultBackend: ProductBackend {
    switch self {
    case .server:
      return .swiftPM
    case .client:
      return .xcode
    }
  }

  public var defaultScheme: String {
    switch self {
    case .server:
      return "SymphonyServer"
    case .client:
      return "SymphonySwiftUIApp"
    }
  }

  public var defaultSwiftPMProduct: String? {
    switch self {
    case .server:
      return "symphony-server"
    case .client:
      return nil
    }
  }

  public var defaultSwiftPMTestFilter: String? {
    switch self {
    case .server:
      return "SymphonyServerTests"
    case .client:
      return nil
    }
  }

  public var defaultPlatform: PlatformKind {
    switch self {
    case .server:
      return .macos
    case .client:
      return .iosSimulator
    }
  }
}

public enum PlatformKind: String, Codable, CaseIterable, Sendable {
  case macos
  case iosSimulator = "ios-simulator"

  public var xcodeDestinationPlatform: String {
    switch self {
    case .macos:
      return "macOS"
    case .iosSimulator:
      return "iOS Simulator"
    }
  }
}

public enum XcodeOutputMode: String, Codable, CaseIterable, Sendable {
  case filtered
  case full
  case quiet
}

public struct WorkspaceContext: Sendable {
  public let repositoryLayout: RepositoryLayout
  public let projectRoot: URL
  public let buildStateRoot: URL
  public let xcodeWorkspacePath: URL?
  public let xcodeProjectPath: URL?

  public init(
    projectRoot: URL,
    buildStateRoot: URL,
    xcodeWorkspacePath: URL?,
    xcodeProjectPath: URL?,
    repositoryLayout: RepositoryLayout? = nil
  ) {
    let resolvedLayout =
      repositoryLayout
      ?? RepositoryLayout(
        projectRoot: projectRoot,
        rootPackagePath: projectRoot.appendingPathComponent("Package.swift", isDirectory: false),
        xcodeWorkspacePath: xcodeWorkspacePath,
        xcodeProjectPath: xcodeProjectPath,
        applicationsRoot: projectRoot.appendingPathComponent("Applications", isDirectory: true)
      )
    self.repositoryLayout = resolvedLayout
    self.projectRoot = projectRoot
    self.buildStateRoot = buildStateRoot
    self.xcodeWorkspacePath = xcodeWorkspacePath
    self.xcodeProjectPath = xcodeProjectPath
  }
}

public struct WorkerScope: Codable, Hashable, Sendable {
  public let id: Int
  public let slug: String

  public init(id: Int) throws {
    guard id >= 0 else {
      throw SymphonyHarnessError(
        code: "invalid_worker_id", message: "Worker ids must be non-negative.")
    }

    self.id = id
    self.slug = "worker-\(id)"
  }
}

public struct ExecutionContext: Sendable {
  public let worker: WorkerScope
  public let timestamp: String
  public let runID: String
  public let artifactRoot: URL
  public let derivedDataPath: URL
  public let resultBundlePath: URL
  public let logPath: URL
  public let runtimeRoot: URL

  public init(
    worker: WorkerScope,
    timestamp: String,
    runID: String,
    artifactRoot: URL,
    derivedDataPath: URL,
    resultBundlePath: URL,
    logPath: URL,
    runtimeRoot: URL
  ) {
    self.worker = worker
    self.timestamp = timestamp
    self.runID = runID
    self.artifactRoot = artifactRoot
    self.derivedDataPath = derivedDataPath
    self.resultBundlePath = resultBundlePath
    self.logPath = logPath
    self.runtimeRoot = runtimeRoot
  }
}

public enum XcodeAction: String, Codable, Sendable {
  case build
  case buildForTesting
  case test
  case launch

  public var xcodebuildAction: String? {
    switch self {
    case .build:
      return "build"
    case .buildForTesting:
      return "build-for-testing"
    case .test:
      return "test"
    case .launch:
      return nil
    }
  }
}

public struct SchemeSelector: Codable, Hashable, Sendable {
  public let product: ProductKind
  public let scheme: String
  public let platform: PlatformKind

  public init(product: ProductKind, scheme: String?, platform: PlatformKind?) {
    self.product = product
    self.scheme = scheme ?? product.defaultScheme
    self.platform = platform ?? product.defaultPlatform
  }

  public var runIdentifier: String {
    ShellQuoting.slugify(self.scheme)
  }
}

public struct DestinationSelector: Codable, Hashable, Sendable {
  public let platform: PlatformKind
  public let simulatorName: String?
  public let simulatorUDID: String?

  public init(platform: PlatformKind, simulatorName: String? = nil, simulatorUDID: String? = nil) {
    self.platform = platform
    self.simulatorName = simulatorName
    self.simulatorUDID = simulatorUDID
  }
}

public struct ResolvedDestination: Codable, Hashable, Sendable {
  public let platform: PlatformKind
  public let displayName: String
  public let simulatorName: String?
  public let simulatorUDID: String?
  public let xcodeDestination: String

  public init(
    platform: PlatformKind,
    displayName: String,
    simulatorName: String?,
    simulatorUDID: String?,
    xcodeDestination: String
  ) {
    self.platform = platform
    self.displayName = displayName
    self.simulatorName = simulatorName
    self.simulatorUDID = simulatorUDID
    self.xcodeDestination = xcodeDestination
  }
}

public struct XcodeCommandRequest: Codable, Hashable, Sendable {
  public let action: XcodeAction
  public let scheme: String
  public let destination: ResolvedDestination
  public let derivedDataPath: URL
  public let resultBundlePath: URL
  public let enableCodeCoverage: Bool
  public let outputMode: XcodeOutputMode
  public let environment: [String: String]
  public let workspacePath: URL?
  public let projectPath: URL?
  public let testPlan: String?
  public let onlyTesting: [String]
  public let skipTesting: [String]

  public init(
    action: XcodeAction,
    scheme: String,
    destination: ResolvedDestination,
    derivedDataPath: URL,
    resultBundlePath: URL,
    enableCodeCoverage: Bool = false,
    outputMode: XcodeOutputMode,
    environment: [String: String],
    workspacePath: URL?,
    projectPath: URL?,
    testPlan: String? = nil,
    onlyTesting: [String] = [],
    skipTesting: [String] = []
  ) {
    self.action = action
    self.scheme = scheme
    self.destination = destination
    self.derivedDataPath = derivedDataPath
    self.resultBundlePath = resultBundlePath
    self.enableCodeCoverage = enableCodeCoverage
    self.outputMode = outputMode
    self.environment = environment
    self.workspacePath = workspacePath
    self.projectPath = projectPath
    self.testPlan = testPlan
    self.onlyTesting = onlyTesting
    self.skipTesting = skipTesting
  }

  public func renderedArguments() throws -> [String] {
    guard let action = action.xcodebuildAction else {
      throw SymphonyHarnessError(
        code: "invalid_xcode_action",
        message: "Launch requests do not render an xcodebuild action directly.")
    }

    var arguments = [String]()
    if let workspacePath {
      arguments += ["-workspace", workspacePath.path]
    } else if let projectPath {
      arguments += ["-project", projectPath.path]
    } else {
      throw SymphonyHarnessError(
        code: "missing_build_definition", message: "No Xcode workspace or project was resolved.")
    }

    arguments += [
      "-scheme", scheme,
      "-destination", destination.xcodeDestination,
      "-derivedDataPath", derivedDataPath.path,
      "-resultBundlePath", resultBundlePath.path,
    ]

    if let testPlan {
      arguments += ["-testPlan", testPlan]
    }

    if enableCodeCoverage {
      arguments += ["-enableCodeCoverage", "YES"]
    }

    for item in onlyTesting {
      arguments += ["-only-testing:\(item)"]
    }

    for item in skipTesting {
      arguments += ["-skip-testing:\(item)"]
    }

    arguments.append(action)
    return arguments
  }

  public func renderedCommandLine() throws -> String {
    ShellQuoting.render(command: "xcodebuild", arguments: try renderedArguments())
  }
}

public struct XcodeRunResult: Codable, Hashable, Sendable {
  public let exitStatus: Int32
  public let invocation: String
  public let startedAt: Date
  public let endedAt: Date
  public let resultBundlePath: URL
  public let logPath: URL

  public init(
    exitStatus: Int32,
    invocation: String,
    startedAt: Date,
    endedAt: Date,
    resultBundlePath: URL,
    logPath: URL
  ) {
    self.exitStatus = exitStatus
    self.invocation = invocation
    self.startedAt = startedAt
    self.endedAt = endedAt
    self.resultBundlePath = resultBundlePath
    self.logPath = logPath
  }
}

public struct CoverageFileReport: Codable, Hashable, Sendable {
  public let name: String
  public let path: String
  public let coveredLines: Int
  public let executableLines: Int
  public let lineCoverage: Double

  public init(
    name: String, path: String, coveredLines: Int, executableLines: Int, lineCoverage: Double
  ) {
    self.name = name
    self.path = path
    self.coveredLines = coveredLines
    self.executableLines = executableLines
    self.lineCoverage = lineCoverage
  }
}

public struct CoverageTargetReport: Codable, Hashable, Sendable {
  public let name: String
  public let buildProductPath: String?
  public let coveredLines: Int
  public let executableLines: Int
  public let lineCoverage: Double
  public let files: [CoverageFileReport]?

  public init(
    name: String,
    buildProductPath: String?,
    coveredLines: Int,
    executableLines: Int,
    lineCoverage: Double,
    files: [CoverageFileReport]?
  ) {
    self.name = name
    self.buildProductPath = buildProductPath
    self.coveredLines = coveredLines
    self.executableLines = executableLines
    self.lineCoverage = lineCoverage
    self.files = files
  }
}

public struct CoverageReport: Codable, Hashable, Sendable {
  public let coveredLines: Int
  public let executableLines: Int
  public let lineCoverage: Double
  public let includeTestTargets: Bool
  public let excludedTargets: [String]
  public let targets: [CoverageTargetReport]

  public init(
    coveredLines: Int,
    executableLines: Int,
    lineCoverage: Double,
    includeTestTargets: Bool,
    excludedTargets: [String],
    targets: [CoverageTargetReport]
  ) {
    self.coveredLines = coveredLines
    self.executableLines = executableLines
    self.lineCoverage = lineCoverage
    self.includeTestTargets = includeTestTargets
    self.excludedTargets = excludedTargets
    self.targets = targets
  }
}

public struct CoverageLineRange: Codable, Hashable, Sendable {
  public let startLine: Int
  public let endLine: Int

  public init(startLine: Int, endLine: Int) {
    self.startLine = startLine
    self.endLine = endLine
  }
}

public struct CoverageInspectionFunctionReport: Codable, Hashable, Sendable {
  public let name: String
  public let coveredLines: Int
  public let executableLines: Int
  public let lineCoverage: Double

  public init(name: String, coveredLines: Int, executableLines: Int, lineCoverage: Double) {
    self.name = name
    self.coveredLines = coveredLines
    self.executableLines = executableLines
    self.lineCoverage = lineCoverage
  }
}

public struct CoverageInspectionFileReport: Codable, Hashable, Sendable {
  public let targetName: String
  public let path: String
  public let coveredLines: Int
  public let executableLines: Int
  public let lineCoverage: Double
  public let missingLineRanges: [CoverageLineRange]
  public let functions: [CoverageInspectionFunctionReport]

  public init(
    targetName: String,
    path: String,
    coveredLines: Int,
    executableLines: Int,
    lineCoverage: Double,
    missingLineRanges: [CoverageLineRange],
    functions: [CoverageInspectionFunctionReport]
  ) {
    self.targetName = targetName
    self.path = path
    self.coveredLines = coveredLines
    self.executableLines = executableLines
    self.lineCoverage = lineCoverage
    self.missingLineRanges = missingLineRanges
    self.functions = functions
  }
}

public struct CoverageInspectionReport: Codable, Hashable, Sendable {
  public let backend: ProductBackend
  public let product: ProductKind
  public let generatedAt: String
  public let files: [CoverageInspectionFileReport]

  public init(
    backend: ProductBackend, product: ProductKind, generatedAt: String,
    files: [CoverageInspectionFileReport]
  ) {
    self.backend = backend
    self.product = product
    self.generatedAt = generatedAt
    self.files = files
  }
}

public struct CoverageInspectionRawCommand: Codable, Hashable, Sendable {
  public let commandLine: String
  public let scope: String
  public let filePath: String?
  public let format: String
  public let output: String

  public init(commandLine: String, scope: String, filePath: String?, format: String, output: String)
  {
    self.commandLine = commandLine
    self.scope = scope
    self.filePath = filePath
    self.format = format
    self.output = output
  }
}

public struct CoverageInspectionRawReport: Codable, Hashable, Sendable {
  public let backend: ProductBackend
  public let product: ProductKind
  public let commands: [CoverageInspectionRawCommand]

  public init(
    backend: ProductBackend, product: ProductKind, commands: [CoverageInspectionRawCommand]
  ) {
    self.backend = backend
    self.product = product
    self.commands = commands
  }
}

public struct PackageCoverageFileReport: Codable, Hashable, Sendable {
  public let path: String
  public let coveredLines: Int
  public let executableLines: Int
  public let lineCoverage: Double

  public init(path: String, coveredLines: Int, executableLines: Int, lineCoverage: Double) {
    self.path = path
    self.coveredLines = coveredLines
    self.executableLines = executableLines
    self.lineCoverage = lineCoverage
  }
}

public struct PackageCoverageReport: Codable, Hashable, Sendable {
  public let scope: String
  public let coveredLines: Int
  public let executableLines: Int
  public let lineCoverage: Double
  public let coverageJSONPath: String
  public let files: [PackageCoverageFileReport]

  public init(
    scope: String,
    coveredLines: Int,
    executableLines: Int,
    lineCoverage: Double,
    coverageJSONPath: String,
    files: [PackageCoverageFileReport]
  ) {
    self.scope = scope
    self.coveredLines = coveredLines
    self.executableLines = executableLines
    self.lineCoverage = lineCoverage
    self.coverageJSONPath = coverageJSONPath
    self.files = files
  }
}

public struct HarnessCoverageViolation: Codable, Hashable, Sendable {
  public let suite: String
  public let kind: String
  public let name: String
  public let coveredLines: Int
  public let executableLines: Int
  public let lineCoverage: Double
  public let uncoveredFunctions: [String]?
  public let missingLineRanges: [CoverageLineRange]?

  public init(
    suite: String,
    kind: String,
    name: String,
    coveredLines: Int,
    executableLines: Int,
    lineCoverage: Double,
    uncoveredFunctions: [String]? = nil,
    missingLineRanges: [CoverageLineRange]? = nil
  ) {
    self.suite = suite
    self.kind = kind
    self.name = name
    self.coveredLines = coveredLines
    self.executableLines = executableLines
    self.lineCoverage = lineCoverage
    self.uncoveredFunctions = uncoveredFunctions
    self.missingLineRanges = missingLineRanges
  }

  enum CodingKeys: String, CodingKey {
    case suite
    case kind
    case name
    case coveredLines
    case executableLines
    case lineCoverage
    case uncoveredFunctions
    case missingLineRanges
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    suite = try container.decode(String.self, forKey: .suite)
    kind = try container.decode(String.self, forKey: .kind)
    name = try container.decode(String.self, forKey: .name)
    coveredLines = try container.decode(Int.self, forKey: .coveredLines)
    executableLines = try container.decode(Int.self, forKey: .executableLines)
    lineCoverage = try container.decode(Double.self, forKey: .lineCoverage)
    uncoveredFunctions = try container.decodeIfPresent([String].self, forKey: .uncoveredFunctions)
    missingLineRanges = try container.decodeIfPresent(
      [CoverageLineRange].self,
      forKey: .missingLineRanges
    )
  }
}

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
  public let command: BuildCommandFamily
  public let runID: String
  public let timestamp: String
  public let artifactRoot: URL
  public let summaryPath: URL
  public let indexPath: URL

  public init(
    command: BuildCommandFamily, runID: String, timestamp: String, artifactRoot: URL,
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
  public let command: BuildCommandFamily
  public let runID: String
  public let timestamp: String
  public let anomalies: [ArtifactAnomaly]

  public init(
    entries: [ArtifactIndexEntry], command: BuildCommandFamily, runID: String, timestamp: String,
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

struct BuildCommandRequest: Sendable {
  let product: ProductKind
  let scheme: String?
  let swiftPMProduct: String?
  let platform: PlatformKind?
  let simulator: String?
  let workerID: Int
  let dryRun: Bool
  let buildForTesting: Bool
  let outputMode: XcodeOutputMode
  let subjectName: String?
  let currentDirectory: URL

  init(
    product: ProductKind,
    scheme: String?,
    swiftPMProduct: String? = nil,
    platform: PlatformKind?,
    simulator: String?,
    workerID: Int,
    dryRun: Bool,
    buildForTesting: Bool,
    outputMode: XcodeOutputMode,
    subjectName: String? = nil,
    currentDirectory: URL
  ) {
    self.product = product
    self.scheme = scheme
    self.swiftPMProduct = swiftPMProduct
    self.platform = platform
    self.simulator = simulator
    self.workerID = workerID
    self.dryRun = dryRun
    self.buildForTesting = buildForTesting
    self.outputMode = outputMode
    self.subjectName = subjectName
    self.currentDirectory = currentDirectory
  }
}

struct TestCommandRequest: Sendable {
  let product: ProductKind
  let scheme: String?
  let swiftPMTestFilter: String?
  let platform: PlatformKind?
  let simulator: String?
  let workerID: Int
  let dryRun: Bool
  let onlyTesting: [String]
  let skipTesting: [String]
  let outputMode: XcodeOutputMode
  let subjectName: String?
  let currentDirectory: URL

  init(
    product: ProductKind,
    scheme: String?,
    swiftPMTestFilter: String? = nil,
    platform: PlatformKind?,
    simulator: String?,
    workerID: Int,
    dryRun: Bool,
    onlyTesting: [String],
    skipTesting: [String],
    outputMode: XcodeOutputMode,
    subjectName: String? = nil,
    currentDirectory: URL
  ) {
    self.product = product
    self.scheme = scheme
    self.swiftPMTestFilter = swiftPMTestFilter
    self.platform = platform
    self.simulator = simulator
    self.workerID = workerID
    self.dryRun = dryRun
    self.onlyTesting = onlyTesting
    self.skipTesting = skipTesting
    self.outputMode = outputMode
    self.subjectName = subjectName
    self.currentDirectory = currentDirectory
  }
}

struct RunCommandRequest: Sendable {
  let product: ProductKind
  let scheme: String?
  let swiftPMProduct: String?
  let platform: PlatformKind?
  let simulator: String?
  let workerID: Int
  let dryRun: Bool
  let serverURL: String?
  let serverScheme: String?
  let host: String?
  let port: Int?
  let environment: [String: String]
  let outputMode: XcodeOutputMode
  let subjectName: String?
  let currentDirectory: URL

  init(
    product: ProductKind,
    scheme: String?,
    swiftPMProduct: String? = nil,
    platform: PlatformKind?,
    simulator: String?,
    workerID: Int,
    dryRun: Bool,
    serverURL: String?,
    serverScheme: String? = nil,
    host: String?,
    port: Int?,
    environment: [String: String],
    outputMode: XcodeOutputMode,
    subjectName: String? = nil,
    currentDirectory: URL
  ) {
    self.product = product
    self.scheme = scheme
    self.swiftPMProduct = swiftPMProduct
    self.platform = platform
    self.simulator = simulator
    self.workerID = workerID
    self.dryRun = dryRun
    self.serverURL = serverURL
    self.serverScheme = serverScheme
    self.host = host
    self.port = port
    self.environment = environment
    self.outputMode = outputMode
    self.subjectName = subjectName
    self.currentDirectory = currentDirectory
  }
}

struct HarnessCommandRequest: Sendable {
  let minimumCoveragePercent: Double
  let json: Bool
  let outputMode: XcodeOutputMode
  let currentDirectory: URL

  init(
    minimumCoveragePercent: Double, json: Bool, outputMode: XcodeOutputMode = .filtered,
    currentDirectory: URL
  ) {
    self.minimumCoveragePercent = minimumCoveragePercent
    self.json = json
    self.outputMode = outputMode
    self.currentDirectory = currentDirectory
  }
}

struct HooksInstallRequest: Sendable {
  let currentDirectory: URL

  init(currentDirectory: URL) {
    self.currentDirectory = currentDirectory
  }
}

struct ArtifactsCommandRequest: Sendable {
  let command: BuildCommandFamily
  let latest: Bool
  let runID: String?
  let currentDirectory: URL

  init(command: BuildCommandFamily, latest: Bool, runID: String?, currentDirectory: URL) {
    self.command = command
    self.latest = latest
    self.runID = runID
    self.currentDirectory = currentDirectory
  }
}

public struct DoctorCommandRequest: Sendable {
  public let strict: Bool
  public let json: Bool
  public let quiet: Bool
  public let currentDirectory: URL

  public init(strict: Bool, json: Bool, quiet: Bool, currentDirectory: URL) {
    self.strict = strict
    self.json = json
    self.quiet = quiet
    self.currentDirectory = currentDirectory
  }
}

struct SimSetServerRequest: Sendable {
  let serverURL: String?
  let scheme: String?
  let host: String?
  let port: Int?
  let currentDirectory: URL

  init(serverURL: String?, scheme: String?, host: String?, port: Int?, currentDirectory: URL)
  {
    self.serverURL = serverURL
    self.scheme = scheme
    self.host = host
    self.port = port
    self.currentDirectory = currentDirectory
  }
}

struct SimBootRequest: Sendable {
  let simulator: String?
  let currentDirectory: URL

  init(simulator: String?, currentDirectory: URL) {
    self.simulator = simulator
    self.currentDirectory = currentDirectory
  }
}
