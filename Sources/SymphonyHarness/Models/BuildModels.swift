import Foundation
import SymphonyShared

enum BuildCommandFamily: String, Codable, CaseIterable, Sendable {
  case build
  case test
  case run
  case harness
}

public enum ArtifactCommand: String, Codable, CaseIterable, Sendable {
  case build
  case test
  case run
  case harness
}

public enum ProductBackend: String, Codable, CaseIterable, Sendable {
  case xcode
  case swiftPM
}

enum ProductKind: String, Codable, CaseIterable, Sendable {
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

extension BuildCommandFamily {
  var artifactCommand: ArtifactCommand {
    switch self {
    case .build:
      return .build
    case .test:
      return .test
    case .run:
      return .run
    case .harness:
      return .harness
    }
  }
}

extension ProductKind {
  var runtimeTarget: RuntimeTarget {
    switch self {
    case .server:
      return .server
    case .client:
      return .client
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

enum XcodeAction: String, Codable, Sendable {
  case build
  case buildForTesting
  case test
  case launch

  var xcodebuildAction: String? {
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

struct SchemeSelector: Codable, Hashable, Sendable {
  let product: ProductKind
  let scheme: String
  let platform: PlatformKind

  init(product: ProductKind, scheme: String?, platform: PlatformKind?) {
    self.product = product
    self.scheme = scheme ?? product.defaultScheme
    self.platform = platform ?? product.defaultPlatform
  }

  var runIdentifier: String {
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

struct XcodeCommandRequest: Codable, Hashable, Sendable {
  let action: XcodeAction
  let scheme: String
  let destination: ResolvedDestination
  let derivedDataPath: URL
  let resultBundlePath: URL
  let enableCodeCoverage: Bool
  let outputMode: XcodeOutputMode
  let environment: [String: String]
  let workspacePath: URL?
  let projectPath: URL?
  let testPlan: String?
  let onlyTesting: [String]
  let skipTesting: [String]

  init(
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

  func renderedArguments() throws -> [String] {
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
      "-skipPackagePluginValidation",
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
