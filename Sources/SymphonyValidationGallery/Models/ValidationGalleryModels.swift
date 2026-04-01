import Foundation
import SymphonyXcodeValidation

public enum ValidationBundleSource: Equatable, Sendable {
  case folder(URL)
  case manifestFile(URL)

  public var url: URL {
    switch self {
    case .folder(let url), .manifestFile(let url):
      url
    }
  }

  public var kind: ValidationRecentBundle.Kind {
    switch self {
    case .folder:
      .folder
    case .manifestFile:
      .manifestFile
    }
  }

  public var bundleRootURL: URL {
    switch self {
    case .folder(let url):
      url
    case .manifestFile(let url):
      url.deletingLastPathComponent()
    }
  }

  public var manifestURL: URL {
    switch self {
    case .folder(let url):
      url.appendingPathComponent("manifest.json")
    case .manifestFile(let url):
      url
    }
  }

  public var displayName: String {
    switch self {
    case .folder(let url):
      if url.lastPathComponent.isEmpty == false {
        return url.lastPathComponent
      }
      return url.path
    case .manifestFile(let url):
      let rootName = url.deletingLastPathComponent().lastPathComponent
      return rootName.isEmpty ? url.lastPathComponent : rootName
    }
  }
}

public struct ValidationResolvedBookmark: Equatable, Sendable {
  public let url: URL
  public let isStale: Bool

  public init(url: URL, isStale: Bool) {
    self.url = url
    self.isStale = isStale
  }
}

public struct ValidationRecentBundle: Codable, Equatable, Sendable, Identifiable {
  public enum Kind: String, Codable, Equatable, Sendable {
    case folder
    case manifestFile
  }

  public let kind: Kind
  public let displayName: String
  public let bookmarkData: Data?
  public let fallbackPath: String
  public let lastOpenedAt: Date

  public var id: String {
    "\(kind.rawValue):\(fallbackPath)"
  }

  public init(
    kind: Kind,
    displayName: String,
    bookmarkData: Data?,
    fallbackPath: String,
    lastOpenedAt: Date
  ) {
    self.kind = kind
    self.displayName = displayName
    self.bookmarkData = bookmarkData
    self.fallbackPath = fallbackPath
    self.lastOpenedAt = lastOpenedAt
  }
}

public struct ValidationBundleWarning: Equatable, Sendable, Identifiable {
  public enum Kind: String, Equatable, Sendable {
    case missingMedia
    case missingAuditAttachment
  }

  public let kind: Kind
  public let message: String

  public var id: String {
    "\(kind.rawValue):\(message)"
  }

  public init(kind: Kind, message: String) {
    self.kind = kind
    self.message = message
  }
}

public struct ValidationGalleryArtifact: Equatable, Sendable, Identifiable {
  public let record: MediaArtifact
  public let fileURL: URL
  public let isAvailable: Bool

  public var id: String {
    [
      record.platform,
      record.plan,
      record.checkpoint,
      record.surface,
      record.orientation,
      record.variant,
      record.artifactType.rawValue,
      fileURL.path,
    ].joined(separator: "::")
  }

  public init(record: MediaArtifact, fileURL: URL, isAvailable: Bool) {
    self.record = record
    self.fileURL = fileURL
    self.isAvailable = isAvailable
  }
}

public struct ValidationGalleryAuditIssue: Equatable, Sendable, Identifiable {
  public let record: AuditIssueRecord
  public let fileURL: URL
  public let isAvailable: Bool

  public var id: String {
    [
      record.platform,
      record.plan,
      record.test,
      record.checkpoint ?? "none",
      fileURL.path,
    ].joined(separator: "::")
  }

  public init(record: AuditIssueRecord, fileURL: URL, isAvailable: Bool) {
    self.record = record
    self.fileURL = fileURL
    self.isAvailable = isAvailable
  }
}

public struct ValidationGalleryCheckpointSection: Equatable, Sendable, Identifiable {
  public let platform: String
  public let plan: String
  public let checkpoint: String
  public let artifacts: [ValidationGalleryArtifact]

  public var id: String {
    "\(platform)::\(plan)::\(checkpoint)"
  }

  public init(
    platform: String,
    plan: String,
    checkpoint: String,
    artifacts: [ValidationGalleryArtifact]
  ) {
    self.platform = platform
    self.plan = plan
    self.checkpoint = checkpoint
    self.artifacts = artifacts
  }
}

public struct ValidationGalleryPlanSection: Equatable, Sendable, Identifiable {
  public let platform: String
  public let plan: String
  public let checkpoints: [ValidationGalleryCheckpointSection]

  public var id: String {
    "\(platform)::\(plan)"
  }

  public init(
    platform: String,
    plan: String,
    checkpoints: [ValidationGalleryCheckpointSection]
  ) {
    self.platform = platform
    self.plan = plan
    self.checkpoints = checkpoints
  }
}

public struct ValidationGalleryPlatformSection: Equatable, Sendable, Identifiable {
  public let platform: String
  public let plans: [ValidationGalleryPlanSection]

  public var id: String {
    platform
  }

  public init(platform: String, plans: [ValidationGalleryPlanSection]) {
    self.platform = platform
    self.plans = plans
  }
}

public struct ValidationBundleSnapshot: Equatable, Sendable {
  public let source: ValidationBundleSource
  public let sourceLabel: String
  public let bundleRootURL: URL
  public let manifestURL: URL
  public let summary: ValidationSummary
  public let artifacts: [ValidationGalleryArtifact]
  public let auditIssues: [ValidationGalleryAuditIssue]
  public let warnings: [ValidationBundleWarning]
  public let platformSections: [ValidationGalleryPlatformSection]

  public init(
    source: ValidationBundleSource,
    sourceLabel: String,
    bundleRootURL: URL,
    manifestURL: URL,
    summary: ValidationSummary,
    artifacts: [ValidationGalleryArtifact],
    auditIssues: [ValidationGalleryAuditIssue],
    warnings: [ValidationBundleWarning],
    platformSections: [ValidationGalleryPlatformSection]
  ) {
    self.source = source
    self.sourceLabel = sourceLabel
    self.bundleRootURL = bundleRootURL
    self.manifestURL = manifestURL
    self.summary = summary
    self.artifacts = artifacts
    self.auditIssues = auditIssues
    self.warnings = warnings
    self.platformSections = platformSections
  }
}

public enum ValidationGallerySidebarSelection: Hashable, Sendable {
  case all
  case platform(String)
  case plan(platform: String, plan: String)
}

public enum ValidationGalleryBrowserDisplayMode: String, Codable, CaseIterable, Equatable, Sendable {
  case list
  case grid
}

public enum ValidationGalleryMacPreviewEmphasis: String, Codable, CaseIterable, Equatable, Sendable {
  case standard
  case expanded
}

public struct ValidationGalleryWorkspacePreferences: Codable, Equatable, Sendable {
  public var browserDisplayMode: ValidationGalleryBrowserDisplayMode
  public var macPreviewEmphasis: ValidationGalleryMacPreviewEmphasis
  public var inspectorPreviewHeight: Double?

  public static let defaults = Self(
    browserDisplayMode: .list,
    macPreviewEmphasis: .expanded,
    inspectorPreviewHeight: nil
  )

  public init(
    browserDisplayMode: ValidationGalleryBrowserDisplayMode = .list,
    macPreviewEmphasis: ValidationGalleryMacPreviewEmphasis = .expanded,
    inspectorPreviewHeight: Double? = nil
  ) {
    self.browserDisplayMode = browserDisplayMode
    self.macPreviewEmphasis = macPreviewEmphasis
    self.inspectorPreviewHeight = inspectorPreviewHeight
  }
}

public protocol ValidationBundleLoading: Sendable {
  func load(from source: ValidationBundleSource) async throws -> ValidationBundleSnapshot
}

public protocol ValidationRecentBundlePersisting: Sendable {
  func loadRecentBundles() async throws -> [ValidationRecentBundle]
  func saveRecentBundles(_ recentBundles: [ValidationRecentBundle]) async throws
}

public protocol ValidationGalleryWorkspacePreferencesPersisting {
  func loadWorkspacePreferences() throws -> ValidationGalleryWorkspacePreferences?
  func saveWorkspacePreferences(_ preferences: ValidationGalleryWorkspacePreferences) throws
}

enum ValidationGalleryOrganizer {
  private static let platformOrder = Dictionary(
    uniqueKeysWithValues: ValidationDestination.defaultMatrix.enumerated().map {
      ($0.element.platformDirectoryName, $0.offset)
    }
  )
  private static let planOrder = Dictionary(
    uniqueKeysWithValues: ValidationPlan.fullMatrix.enumerated().map { ($0.element.slug, $0.offset) }
  )

  static func makePlatformSections(
    from artifacts: [ValidationGalleryArtifact]
  ) -> [ValidationGalleryPlatformSection] {
    let groupedByPlatform = Dictionary(grouping: artifacts, by: \.record.platform)

    return groupedByPlatform.keys.sorted(by: comparePlatforms).map { platform in
      let platformArtifacts = groupedByPlatform[platform] ?? []
      let groupedByPlan = Dictionary(grouping: platformArtifacts, by: \.record.plan)
      let plans = groupedByPlan.keys.sorted(by: comparePlans).map { plan in
        let planArtifacts = groupedByPlan[plan] ?? []
        let groupedByCheckpoint = Dictionary(grouping: planArtifacts, by: \.record.checkpoint)
        let checkpoints = groupedByCheckpoint.keys.sorted(by: localizedAscending).map { checkpoint in
          let checkpointArtifacts = (groupedByCheckpoint[checkpoint] ?? []).sorted(by: compareArtifacts)
          return ValidationGalleryCheckpointSection(
            platform: platform,
            plan: plan,
            checkpoint: checkpoint,
            artifacts: checkpointArtifacts
          )
        }
        return ValidationGalleryPlanSection(platform: platform, plan: plan, checkpoints: checkpoints)
      }
      return ValidationGalleryPlatformSection(platform: platform, plans: plans)
    }
  }

  private static func comparePlatforms(_ lhs: String, _ rhs: String) -> Bool {
    let lhsRank = platformOrder[lhs] ?? Int.max
    let rhsRank = platformOrder[rhs] ?? Int.max
    if lhsRank != rhsRank {
      return lhsRank < rhsRank
    }
    return localizedAscending(lhs, rhs)
  }

  private static func comparePlans(_ lhs: String, _ rhs: String) -> Bool {
    let lhsRank = planOrder[lhs] ?? Int.max
    let rhsRank = planOrder[rhs] ?? Int.max
    if lhsRank != rhsRank {
      return lhsRank < rhsRank
    }
    return localizedAscending(lhs, rhs)
  }

  private static func compareArtifacts(
    _ lhs: ValidationGalleryArtifact,
    _ rhs: ValidationGalleryArtifact
  ) -> Bool {
    let lhsParts = [
      lhs.record.surface,
      lhs.record.variant,
      lhs.record.orientation,
      lhs.record.artifactType.rawValue,
      lhs.fileURL.lastPathComponent,
    ]
    let rhsParts = [
      rhs.record.surface,
      rhs.record.variant,
      rhs.record.orientation,
      rhs.record.artifactType.rawValue,
      rhs.fileURL.lastPathComponent,
    ]
    return lhsParts.lexicographicallyPrecedes(rhsParts) { localizedAscending($0, $1) }
  }

  private static func localizedAscending(_ lhs: String, _ rhs: String) -> Bool {
    lhs.localizedStandardCompare(rhs) == .orderedAscending
  }
}
