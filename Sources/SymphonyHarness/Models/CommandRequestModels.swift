import Foundation

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

public struct GoEnryMaterializationRequest: Sendable {
  public let currentDirectory: URL

  public init(currentDirectory: URL) {
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
