import CoreGraphics
import Foundation
import ImageIO
import Observation
import OSLog

let gallerySignposter = OSSignposter(
  subsystem: "dev.atjsh.xcode-validation-gallery.performance",
  category: "store"
)

// MARK: - Flat browser row model

/// A flat representation of the browser hierarchy, replacing 4-level nested
/// ForEach (platform → plan → checkpoint → artifacts) with a single-level
/// ForEach. This dramatically reduces SwiftUI view-tree depth and the cost of
/// hit-testing on every mouse-move event.
struct FlatBrowserRow: Identifiable {
  enum Content {
    case platformHeader(platform: String, artifactCount: Int)
    case planHeader(plan: String, artifactCount: Int)
    case checkpoint(
      header: String,
      artifactCount: Int,
      artifacts: [ValidationGalleryArtifact]
    )
  }

  let id: String
  let content: Content

  static func makeRows(
    from sections: [ValidationGalleryPlatformSection]
  ) -> [FlatBrowserRow] {
    var rows: [FlatBrowserRow] = []
    for platform in sections {
      let count = platform.plans.reduce(0) {
        $0 + $1.checkpoints.reduce(0) { $0 + $1.artifacts.count }
      }
      rows.append(FlatBrowserRow(
        id: "platform:\(platform.id)",
        content: .platformHeader(platform: platform.platform, artifactCount: count)
      ))
      for plan in platform.plans {
        let planCount = plan.checkpoints.reduce(0) { $0 + $1.artifacts.count }
        rows.append(FlatBrowserRow(
          id: "plan:\(plan.id)",
          content: .planHeader(plan: plan.plan, artifactCount: planCount)
        ))
        for checkpoint in plan.checkpoints {
          rows.append(FlatBrowserRow(
            id: "checkpoint:\(checkpoint.id)",
            content: .checkpoint(
              header: checkpoint.checkpoint,
              artifactCount: checkpoint.artifacts.count,
              artifacts: checkpoint.artifacts
            )
          ))
        }
      }
    }
    return rows
  }
}

public struct ValidationGallerySelectionFeedback: Equatable, Sendable {
  public enum Kind: Equatable, Sendable {
    case autoSelected
  }

  public let kind: Kind
  public let title: String
  public let message: String

  public init(kind: Kind, title: String, message: String) {
    self.kind = kind
    self.title = title
    self.message = message
  }
}

@MainActor
final class ValidationScopedResourceAccess {
  private let urls: [URL]
  private let startedFlags: [Bool]

  init(urls: [URL]) {
    self.urls = Array(Set(urls.map(\.standardizedFileURL)))
    self.startedFlags = self.urls.map { $0.startAccessingSecurityScopedResource() }
  }

  deinit {
    for (url, started) in zip(urls, startedFlags) where started {
      url.stopAccessingSecurityScopedResource()
    }
  }
}

@MainActor
@Observable
public final class ValidationGalleryStore {

  typealias NumberedCommentItem = (
    artifact: ValidationGalleryArtifact,
    comment: ValidationGalleryComment,
    annotationID: Int
  )

  public var searchText = "" {
    didSet {
      if searchDebounceInterval > .zero {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task { @MainActor [weak self] in
          try? await Task.sleep(for: self?.searchDebounceInterval ?? .milliseconds(200))
          guard !Task.isCancelled else { return }
          self?.recomputeFilteredState()
          self?.normalizeSelectionAfterFilterChange()
        }
      } else {
        recomputeFilteredState()
        normalizeSelectionAfterFilterChange()
      }
    }
  }

  private var searchDebounceTask: Task<Void, Never>?
  let searchDebounceInterval: Duration

  public var sidebarSelection: ValidationGallerySidebarSelection = .all {
    didSet {
      recomputeFilteredState()
      normalizeSelectionAfterFilterChange()
    }
  }

  public internal(set) var snapshot: ValidationBundleSnapshot? {
    didSet {
      cachedAnnotationIDs = nil
      recomputeFilteredState()
    }
  }
  public internal(set) var recentBundles = [ValidationRecentBundle]()
  public internal(set) var isLoading = false
  public internal(set) var error: ValidationGalleryError?
  public internal(set) var selectedArtifactID: ValidationGalleryArtifact.ID?
  public internal(set) var selectionFeedback: ValidationGallerySelectionFeedback?
  public internal(set) var selectedCommentID: ValidationGalleryComment.ID?
  public internal(set) var workspacePreferences: ValidationGalleryWorkspacePreferences

  var commentsByBundleRoot = [String: [ValidationGalleryArtifact.ID: [ValidationGalleryComment]]]() {
    didSet {
      cachedAnnotationIDs = nil
      refreshSelectedArtifactComments()
    }
  }

  /// Cached mapping from comment ID → annotation number, built lazily from
  /// `numberedCurrentBundleComments()`. Invalidated whenever comments or the
  /// snapshot change.
  var cachedAnnotationIDs: [ValidationGalleryComment.ID: Int]?

  let _loadFromSource: @Sendable (ValidationBundleSource) async throws -> ValidationBundleSnapshot
  let _loadRecentBundles: @Sendable () async throws -> [ValidationRecentBundle]
  let _saveRecentBundles: @Sendable ([ValidationRecentBundle]) async throws -> Void
  let _loadWorkspacePreferences: () throws -> ValidationGalleryWorkspacePreferences?
  let _saveWorkspacePreferences: (ValidationGalleryWorkspacePreferences) throws -> Void
  let makeBookmark: @Sendable (URL) throws -> Data?
  let resolveBookmark: @Sendable (Data) throws -> ValidationResolvedBookmark
  let now: @Sendable () -> Date
  var activeAccess: ValidationScopedResourceAccess?

  public init<Loader: ValidationBundleLoading, BundleStore: ValidationRecentBundlePersisting, PrefsStore: ValidationGalleryWorkspacePreferencesPersisting>(
    loader: Loader,
    recentBundleStore: BundleStore,
    workspacePreferencesStore: PrefsStore
      = UserDefaultsValidationGalleryWorkspacePreferencesStore(),
    makeBookmark: @escaping @Sendable (URL) throws -> Data? = { url in
      #if os(macOS)
        return try url.bookmarkData(
          options: .withSecurityScope,
          includingResourceValuesForKeys: nil,
          relativeTo: nil
        )
      #else
        return try url.bookmarkData(
          options: [],
          includingResourceValuesForKeys: nil,
          relativeTo: nil
        )
      #endif
    },
    resolveBookmark: @escaping @Sendable (Data) throws -> ValidationResolvedBookmark = { data in
      var isStale = false

      #if os(macOS)
        let url = try URL(
          resolvingBookmarkData: data,
          options: [.withSecurityScope],
          relativeTo: nil,
          bookmarkDataIsStale: &isStale
        )
      #else
        let url = try URL(
          resolvingBookmarkData: data,
          options: [],
          relativeTo: nil,
          bookmarkDataIsStale: &isStale
        )
      #endif

      return ValidationResolvedBookmark(url: url, isStale: isStale)
    },
    now: @escaping @Sendable () -> Date = Date.init,
    searchDebounceInterval: Duration = .milliseconds(200)
  ) {
    self._loadFromSource = { source in try await loader.load(from: source) }
    self._loadRecentBundles = { try await recentBundleStore.loadRecentBundles() }
    self._saveRecentBundles = { try await recentBundleStore.saveRecentBundles($0) }
    self._loadWorkspacePreferences = { try workspacePreferencesStore.loadWorkspacePreferences() }
    self._saveWorkspacePreferences = { try workspacePreferencesStore.saveWorkspacePreferences($0) }
    self.makeBookmark = makeBookmark
    self.resolveBookmark = resolveBookmark
    self.now = now
    self.searchDebounceInterval = searchDebounceInterval
    self.workspacePreferences = (
      try? workspacePreferencesStore.loadWorkspacePreferences()
    ) ?? .defaults
  }

  public internal(set) var filteredArtifacts: [ValidationGalleryArtifact] = []
  public internal(set) var visiblePlatformSections: [ValidationGalleryPlatformSection] = []
  public internal(set) var selectedArtifact: ValidationGalleryArtifact?
  @ObservationIgnored private var cachedSelectedArtifactIndex: Int?
  @ObservationIgnored private var cachedSelectedArtifactComments = [ValidationGalleryNumberedComment]()
  public internal(set) var filteredAuditIssues: [ValidationGalleryAuditIssue] = []
  public internal(set) var selectedArtifactAuditIssues: [ValidationGalleryAuditIssue] = []
  internal var flatBrowserRows: [FlatBrowserRow] = []

  /// Bumped once at the end of a selection transaction to coalesce multiple
  /// internal `@ObservationIgnored` property changes into a single notification.
  private var selectionRevision: UInt64 = 0

  public var hasActiveFilters: Bool {
    trimmedSearchText.isEmpty == false || sidebarSelection != .all
  }

  public var hasNoVisibleArtifacts: Bool {
    snapshot != nil && filteredArtifacts.isEmpty
  }

  public var visibleScopeTitle: String {
    ValidationGalleryFormatting.sidebarSelectionTitle(sidebarSelection)
  }

  public var resultCountSummary: String {
    ValidationGalleryFormatting.resultCountSummary(filteredArtifacts.count)
  }

  public var filterContextSummary: String {
    var parts = [resultCountSummary, visibleScopeTitle]
    if trimmedSearchText.isEmpty == false {
      parts.append("\"\(trimmedSearchText)\"")
    }
    return parts.joined(separator: " \u{2022} ")
  }

  public var noResultsDescription: String {
    ValidationGalleryFormatting.noResultsDescription(
      searchText: trimmedSearchText,
      visibleScopeTitle: visibleScopeTitle
    )
  }

  public var selectedArtifactPositionText: String? {
    _ = selectionRevision
    guard let cachedSelectedArtifactIndex else {
      return nil
    }
    return "\(cachedSelectedArtifactIndex + 1) of \(filteredArtifacts.count) visible"
  }

  public var canSelectPreviousArtifact: Bool {
    _ = selectionRevision
    guard let cachedSelectedArtifactIndex else {
      return false
    }
    return cachedSelectedArtifactIndex > 0
  }

  public var canSelectNextArtifact: Bool {
    _ = selectionRevision
    guard let cachedSelectedArtifactIndex else {
      return false
    }
    return cachedSelectedArtifactIndex < filteredArtifacts.count - 1
  }

  public var selectedArtifactComments: [ValidationGalleryNumberedComment] {
    _ = selectionRevision
    return cachedSelectedArtifactComments
  }

  public var canCommentSelectedArtifact: Bool {
    selectedArtifact?.record.artifactType == .screenshot
  }

  public var hasCommentsInCurrentBundle: Bool {
    guard let bundleRootKey = currentBundleRootKey else {
      return false
    }

    return commentsByBundleRoot[bundleRootKey]?.values.contains(where: { $0.isEmpty == false }) == true
  }

  // MARK: - Selection & Navigation

  public func selectArtifact(_ artifactID: ValidationGalleryArtifact.ID?) {
    let state = gallerySignposter.beginInterval("selectArtifact")
    defer { gallerySignposter.endInterval("selectArtifact", state) }
    guard selectedArtifactID != artifactID else { return }
    selectedArtifactID = artifactID
    recomputeSelectedArtifact()
    if selectionFeedback != nil { selectionFeedback = nil }
    normalizeSelectionAfterFilterChange()
    selectionRevision &+= 1
  }

  public func clearFilters() {
    selectionFeedback = nil
    searchText = ""
    sidebarSelection = .all
    normalizeSelectedComment()
  }

  public func dismissSelectionFeedback() {
    if selectionFeedback != nil { selectionFeedback = nil }
  }

  public func selectComment(_ commentID: ValidationGalleryComment.ID?) {
    guard let commentID else {
      selectedCommentID = nil
      return
    }

    if selectedArtifactComments.contains(where: { $0.id == commentID }) {
      selectedCommentID = commentID
    }
  }

  public func selectPreviousArtifact() {
    updateSelectedArtifact(by: -1)
  }

  public func selectNextArtifact() {
    updateSelectedArtifact(by: 1)
  }

  public func clearError() {
    error = nil
  }

  // MARK: - Internal Helpers

  func normalizeSelectionAfterFilterChange() {
    let visibleArtifacts = filteredArtifacts
    guard visibleArtifacts.isEmpty == false else {
      if selectedArtifactID != nil { selectedArtifactID = nil }
      recomputeSelectedArtifact()
      if selectionFeedback != nil { selectionFeedback = nil }
      if selectedCommentID != nil { selectedCommentID = nil }
      selectionRevision &+= 1
      return
    }

    if let selectedArtifactID,
      visibleArtifacts.contains(where: { $0.id == selectedArtifactID })
    {
      if selectionFeedback != nil { selectionFeedback = nil }
      normalizeSelectedComment()
      selectionRevision &+= 1
      return
    }

    let previousSelectionID = selectedArtifactID
    let newID = visibleArtifacts.first?.id
    if newID != selectedArtifactID { selectedArtifactID = newID }
    recomputeSelectedArtifact()
    if previousSelectionID != nil, let selectedArtifact {
      selectionFeedback = ValidationGallerySelectionFeedback(
        kind: .autoSelected,
        title: "Showing the first match",
        message: ValidationGalleryFormatting.selectionUpdatedMessage(for: selectedArtifact)
      )
    } else {
      if selectionFeedback != nil { selectionFeedback = nil }
    }
    normalizeSelectedComment()
    selectionRevision &+= 1
  }

  func normalizeSelectedComment() {
    let visibleComments = selectedArtifactComments
    if let selectedCommentID, visibleComments.contains(where: { $0.id == selectedCommentID }) {
      return
    }

    let newCommentID = visibleComments.first?.id
    if newCommentID != selectedCommentID { selectedCommentID = newCommentID }
  }

  var currentBundleRootKey: String? {
    snapshot?.bundleRootURL.standardizedFileURL.path
  }

  func numberedCurrentBundleComments() -> [NumberedCommentItem] {
    let state = gallerySignposter.beginInterval("numberedCurrentBundleComments")
    defer { gallerySignposter.endInterval("numberedCurrentBundleComments", state) }

    guard let bundleRootKey = currentBundleRootKey else {
      return []
    }

    let bundleComments = commentsByBundleRoot[bundleRootKey] ?? [:]
    let orderedArtifacts = (snapshot?.artifacts ?? [])
      .filter { artifact in
        artifact.record.artifactType == .screenshot && bundleComments[artifact.id]?.isEmpty == false
      }
      .sorted(by: compareArtifactsForCommentOrdering(_:_:))

    var numberedItems = [NumberedCommentItem]()
    numberedItems.reserveCapacity(bundleComments.values.reduce(0) { $0 + $1.count })

    for artifact in orderedArtifacts {
      for comment in bundleComments[artifact.id] ?? [] {
        numberedItems.append(
          (
            artifact: artifact,
            comment: comment,
            annotationID: numberedItems.count + 1
          )
        )
      }
    }

    return numberedItems
  }

  // MARK: - Private

  private func recomputeFilteredState() {
    let state = gallerySignposter.beginInterval("recomputeFilteredState")
    defer { gallerySignposter.endInterval("recomputeFilteredState", state) }

    guard let snapshot else {
      filteredArtifacts = []
      visiblePlatformSections = []
      flatBrowserRows = []
      filteredAuditIssues = []
      recomputeSelectedArtifact()
      return
    }

    let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    let filterState = gallerySignposter.beginInterval("filterArtifacts")
    let newFilteredArtifacts = snapshot.artifacts.filter { artifact in
      matchesSelection(artifact) && matchesSearch(artifact, query: trimmedQuery)
    }
    gallerySignposter.endInterval("filterArtifacts", filterState)
    if newFilteredArtifacts != filteredArtifacts {
      filteredArtifacts = newFilteredArtifacts
    }

    let newSections = ValidationGalleryOrganizer.makePlatformSections(
      from: filteredArtifacts
    )
    if newSections != visiblePlatformSections {
      visiblePlatformSections = newSections
      flatBrowserRows = FlatBrowserRow.makeRows(from: visiblePlatformSections)
    }

    let newAuditIssues = snapshot.auditIssues.filter { issue in
      switch sidebarSelection {
      case .all:
        true
      case .platform(let platform):
        issue.record.platform == platform
      case .plan(let platform, let plan):
        issue.record.platform == platform && issue.record.plan == plan
      }
    }
    if newAuditIssues != filteredAuditIssues {
      filteredAuditIssues = newAuditIssues
    }
    recomputeSelectedArtifact()
  }

  private func recomputeSelectedArtifact() {
    let state = gallerySignposter.beginInterval("recomputeSelectedArtifact")
    defer { gallerySignposter.endInterval("recomputeSelectedArtifact", state) }

    let newSelectedIndex: Int?
    if let selectedArtifactID {
      newSelectedIndex = filteredArtifacts.firstIndex(where: { $0.id == selectedArtifactID })
        ?? filteredArtifacts.indices.first
    } else {
      newSelectedIndex = filteredArtifacts.indices.first
    }

    let newSelected = newSelectedIndex.map { filteredArtifacts[$0] }

    if newSelectedIndex != cachedSelectedArtifactIndex {
      cachedSelectedArtifactIndex = newSelectedIndex
    }
    if newSelected != selectedArtifact {
      selectedArtifact = newSelected
    }

    let newAuditIssues: [ValidationGalleryAuditIssue]
    if let artifact = selectedArtifact {
      newAuditIssues = filteredAuditIssues.filter {
        $0.record.platform == artifact.record.platform
          && $0.record.plan == artifact.record.plan
          && $0.record.checkpoint == artifact.record.checkpoint
      }
    } else {
      newAuditIssues = []
    }
    if newAuditIssues != selectedArtifactAuditIssues {
      selectedArtifactAuditIssues = newAuditIssues
    }

    refreshSelectedArtifactComments()
  }

  private func matchesSelection(_ artifact: ValidationGalleryArtifact) -> Bool {
    switch sidebarSelection {
    case .all:
      return true
    case .platform(let platform):
      return artifact.record.platform == platform
    case .plan(let platform, let plan):
      return artifact.record.platform == platform && artifact.record.plan == plan
    }
  }

  private func matchesSearch(_ artifact: ValidationGalleryArtifact, query: String) -> Bool {
    guard query.isEmpty == false else {
      return true
    }

    let normalizedQuery = query.localizedLowercase
    let searchableText = [
      artifact.record.platform,
      artifact.record.plan,
      artifact.record.test,
      artifact.record.checkpoint,
      artifact.record.surface,
      artifact.record.orientation,
      artifact.record.variant,
      artifact.record.artifactType.rawValue,
      artifact.fileURL.lastPathComponent,
    ]
      .joined(separator: "\n")
      .localizedLowercase

    return searchableText.contains(normalizedQuery)
  }

  private var trimmedSearchText: String {
    searchText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func updateSelectedArtifact(by offset: Int) {
    guard let cachedSelectedArtifactIndex else {
      return
    }

    let targetIndex = min(max(cachedSelectedArtifactIndex + offset, 0), filteredArtifacts.count - 1)
    guard targetIndex != cachedSelectedArtifactIndex else {
      return
    }

    selectedArtifactID = filteredArtifacts[targetIndex].id
    recomputeSelectedArtifact()
    selectionFeedback = nil
    normalizeSelectedComment()
    selectionRevision &+= 1
  }

  private func refreshSelectedArtifactComments() {
    let newComments = numberedComments(for: selectedArtifact)
    if newComments != cachedSelectedArtifactComments {
      cachedSelectedArtifactComments = newComments
    }
  }

  private func compareArtifactsForCommentOrdering(
    _ lhs: ValidationGalleryArtifact,
    _ rhs: ValidationGalleryArtifact
  ) -> Bool {
    let lhsKey = (
      lhs.record.platform,
      lhs.record.plan,
      lhs.record.checkpoint,
      ValidationGalleryFormatting.artifactTitle(lhs)
    )
    let rhsKey = (
      rhs.record.platform,
      rhs.record.plan,
      rhs.record.checkpoint,
      ValidationGalleryFormatting.artifactTitle(rhs)
    )
    return lhsKey < rhsKey
  }
}
