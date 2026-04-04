import Foundation

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
  public let target: RuntimeTarget
  public let generatedAt: String
  public let files: [CoverageInspectionFileReport]

  public init(
    backend: ProductBackend,
    target: RuntimeTarget,
    generatedAt: String,
    files: [CoverageInspectionFileReport]
  ) {
    self.backend = backend
    self.target = target
    self.generatedAt = generatedAt
    self.files = files
  }

  init(
    backend: ProductBackend,
    product: ProductKind,
    generatedAt: String,
    files: [CoverageInspectionFileReport]
  ) {
    self.init(
      backend: backend,
      target: product.runtimeTarget,
      generatedAt: generatedAt,
      files: files
    )
  }

  enum CodingKeys: String, CodingKey {
    case backend
    case target
    case product
    case generatedAt
    case files
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    backend = try container.decode(ProductBackend.self, forKey: .backend)
    if let target = try container.decodeIfPresent(RuntimeTarget.self, forKey: .target) {
      self.target = target
    } else {
      self.target = try container.decode(ProductKind.self, forKey: .product).runtimeTarget
    }
    generatedAt = try container.decode(String.self, forKey: .generatedAt)
    files = try container.decode([CoverageInspectionFileReport].self, forKey: .files)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(backend, forKey: .backend)
    try container.encode(target, forKey: .target)
    try container.encode(generatedAt, forKey: .generatedAt)
    try container.encode(files, forKey: .files)
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
  public let target: RuntimeTarget
  public let commands: [CoverageInspectionRawCommand]

  public init(
    backend: ProductBackend,
    target: RuntimeTarget,
    commands: [CoverageInspectionRawCommand]
  ) {
    self.backend = backend
    self.target = target
    self.commands = commands
  }

  init(backend: ProductBackend, product: ProductKind, commands: [CoverageInspectionRawCommand]) {
    self.init(backend: backend, target: product.runtimeTarget, commands: commands)
  }

  enum CodingKeys: String, CodingKey {
    case backend
    case target
    case product
    case commands
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    backend = try container.decode(ProductBackend.self, forKey: .backend)
    if let target = try container.decodeIfPresent(RuntimeTarget.self, forKey: .target) {
      self.target = target
    } else {
      self.target = try container.decode(ProductKind.self, forKey: .product).runtimeTarget
    }
    commands = try container.decode([CoverageInspectionRawCommand].self, forKey: .commands)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(backend, forKey: .backend)
    try container.encode(target, forKey: .target)
    try container.encode(commands, forKey: .commands)
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
