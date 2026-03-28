import Foundation

public struct RepositoryLayout: Codable, Hashable, Sendable {
  public let projectRoot: URL
  public let rootPackagePath: URL
  public let xcodeWorkspacePath: URL?
  public let xcodeProjectPath: URL?
  public let applicationsRoot: URL

  public init(
    projectRoot: URL,
    rootPackagePath: URL,
    xcodeWorkspacePath: URL?,
    xcodeProjectPath: URL?,
    applicationsRoot: URL
  ) {
    self.projectRoot = projectRoot
    self.rootPackagePath = rootPackagePath
    self.xcodeWorkspacePath = xcodeWorkspacePath
    self.xcodeProjectPath = xcodeProjectPath
    self.applicationsRoot = applicationsRoot
  }
}

public enum SubjectKind: String, Codable, CaseIterable, Sendable {
  case library
  case executable
  case app
  case test
  case uiTest
}

public enum BuildSystem: String, Codable, CaseIterable, Sendable {
  case swiftpm
  case xcode
}

public struct HarnessSubject: Codable, Hashable, Sendable {
  public let name: String
  public let kind: SubjectKind
  public let buildSystem: BuildSystem
  public let defaultTestCompanion: String?
  public let requiresXcode: Bool
  public let requiresExclusiveDestination: Bool

  public init(
    name: String,
    kind: SubjectKind,
    buildSystem: BuildSystem,
    defaultTestCompanion: String?,
    requiresXcode: Bool,
    requiresExclusiveDestination: Bool
  ) {
    self.name = name
    self.kind = kind
    self.buildSystem = buildSystem
    self.defaultTestCompanion = defaultTestCompanion
    self.requiresXcode = requiresXcode
    self.requiresExclusiveDestination = requiresExclusiveDestination
  }
}

public enum HarnessSubjects {
  public static let production: [HarnessSubject] = [
    HarnessSubject(
      name: "SymphonyShared",
      kind: .library,
      buildSystem: .swiftpm,
      defaultTestCompanion: "SymphonySharedTests",
      requiresXcode: false,
      requiresExclusiveDestination: false
    ),
    HarnessSubject(
      name: "SymphonyServerCore",
      kind: .library,
      buildSystem: .swiftpm,
      defaultTestCompanion: "SymphonyServerCoreTests",
      requiresXcode: false,
      requiresExclusiveDestination: false
    ),
    HarnessSubject(
      name: "SymphonyServer",
      kind: .library,
      buildSystem: .swiftpm,
      defaultTestCompanion: "SymphonyServerTests",
      requiresXcode: false,
      requiresExclusiveDestination: false
    ),
    HarnessSubject(
      name: "SymphonyServerCLI",
      kind: .executable,
      buildSystem: .swiftpm,
      defaultTestCompanion: "SymphonyServerCLITests",
      requiresXcode: false,
      requiresExclusiveDestination: false
    ),
    HarnessSubject(
      name: "SymphonyHarness",
      kind: .library,
      buildSystem: .swiftpm,
      defaultTestCompanion: "SymphonyHarnessTests",
      requiresXcode: false,
      requiresExclusiveDestination: false
    ),
    HarnessSubject(
      name: "SymphonyHarnessCLI",
      kind: .executable,
      buildSystem: .swiftpm,
      defaultTestCompanion: "SymphonyHarnessCLITests",
      requiresXcode: false,
      requiresExclusiveDestination: false
    ),
    HarnessSubject(
      name: "SymphonySwiftUIApp",
      kind: .app,
      buildSystem: .xcode,
      defaultTestCompanion: "SymphonySwiftUIAppTests",
      requiresXcode: true,
      requiresExclusiveDestination: true
    ),
  ]

  public static let explicitTests: [HarnessSubject] = [
    HarnessSubject(
      name: "SymphonySharedTests",
      kind: .test,
      buildSystem: .swiftpm,
      defaultTestCompanion: nil,
      requiresXcode: false,
      requiresExclusiveDestination: false
    ),
    HarnessSubject(
      name: "SymphonyServerCoreTests",
      kind: .test,
      buildSystem: .swiftpm,
      defaultTestCompanion: nil,
      requiresXcode: false,
      requiresExclusiveDestination: false
    ),
    HarnessSubject(
      name: "SymphonyServerTests",
      kind: .test,
      buildSystem: .swiftpm,
      defaultTestCompanion: nil,
      requiresXcode: false,
      requiresExclusiveDestination: false
    ),
    HarnessSubject(
      name: "SymphonyServerCLITests",
      kind: .test,
      buildSystem: .swiftpm,
      defaultTestCompanion: nil,
      requiresXcode: false,
      requiresExclusiveDestination: false
    ),
    HarnessSubject(
      name: "SymphonyHarnessTests",
      kind: .test,
      buildSystem: .swiftpm,
      defaultTestCompanion: nil,
      requiresXcode: false,
      requiresExclusiveDestination: false
    ),
    HarnessSubject(
      name: "SymphonyHarnessCLITests",
      kind: .test,
      buildSystem: .swiftpm,
      defaultTestCompanion: nil,
      requiresXcode: false,
      requiresExclusiveDestination: false
    ),
    HarnessSubject(
      name: "SymphonySwiftUIAppTests",
      kind: .test,
      buildSystem: .xcode,
      defaultTestCompanion: nil,
      requiresXcode: true,
      requiresExclusiveDestination: true
    ),
    HarnessSubject(
      name: "SymphonySwiftUIAppUITests",
      kind: .uiTest,
      buildSystem: .xcode,
      defaultTestCompanion: nil,
      requiresXcode: true,
      requiresExclusiveDestination: true
    ),
  ]

  public static let runnableSubjectNames = [
    "SymphonyServerCLI",
    "SymphonySwiftUIApp",
  ]

  public static let all = production + explicitTests
  public static let productionSubjectNames = production.map(\.name)
  public static let explicitTestSubjectNames = explicitTests.map(\.name)

  public static func subject(named name: String) -> HarnessSubject? {
    (production + explicitTests).first(where: { $0.name == name })
  }
}
