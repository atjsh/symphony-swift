import Foundation
import Observation
import CoreGraphics
import ImageIO

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
      normalizeSelectionAfterFilterChange()
    }
  }

  public var sidebarSelection: ValidationGallerySidebarSelection = .all {
    didSet {
      normalizeSelectionAfterFilterChange()
    }
  }

  public internal(set) var snapshot: ValidationBundleSnapshot?
  public internal(set) var recentBundles = [ValidationRecentBundle]()
  public internal(set) var isLoading = false
  public internal(set) var error: ValidationGalleryError?
  public internal(set) var selectedArtifactID: ValidationGalleryArtifact.ID?
  public internal(set) var selectionFeedback: ValidationGallerySelectionFeedback?
  public internal(set) var selectedCommentID: ValidationGalleryComment.ID?
  public internal(set) var workspacePreferences: ValidationGalleryWorkspacePreferences

  var commentsByBundleRoot = [String: [ValidationGalleryArtifact.ID: [ValidationGalleryComment]]]()

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
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self._loadFromSource = { source in try await loader.load(from: source) }
    self._loadRecentBundles = { try await recentBundleStore.loadRecentBundles() }
    self._saveRecentBundles = { try await recentBundleStore.saveRecentBundles($0) }
    self._loadWorkspacePreferences = { try workspacePreferencesStore.loadWorkspacePreferences() }
    self._saveWorkspacePreferences = { try workspacePreferencesStore.saveWorkspacePreferences($0) }
    self.makeBookmark = makeBookmark
    self.resolveBookmark = resolveBookmark
    self.now = now
    self.workspacePreferences = (
      try? workspacePreferencesStore.loadWorkspacePreferences()
    ) ?? .defaults
  }

  public var filteredArtifacts: [ValidationGalleryArtifact] {
    guard let snapshot else {
      return []
    }

    let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    return snapshot.artifacts.filter { artifact in
      matchesSelection(artifact) && matchesSearch(artifact, query: trimmedQuery)
    }
  }

  public var visiblePlatformSections: [ValidationGalleryPlatformSection] {
    ValidationGalleryOrganizer.makePlatformSections(from: filteredArtifacts)
  }

  public var selectedArtifact: ValidationGalleryArtifact? {
    guard let selectedArtifactID else {
      return filteredArtifacts.first
    }

    return filteredArtifacts.first(where: { $0.id == selectedArtifactID }) ?? filteredArtifacts.first
  }

  public var filteredAuditIssues: [ValidationGalleryAuditIssue] {
    guard let snapshot else {
      return []
    }

    return snapshot.auditIssues.filter { issue in
      switch sidebarSelection {
      case .all:
        true
      case .platform(let platform):
        issue.record.platform == platform
      case .plan(let platform, let plan):
        issue.record.platform == platform && issue.record.plan == plan
      }
    }
  }

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
    guard let selectedArtifactIndex else {
      return nil
    }
    return "\(selectedArtifactIndex + 1) of \(filteredArtifacts.count) visible"
  }

  public var canSelectPreviousArtifact: Bool {
    guard let selectedArtifactIndex else {
      return false
    }
    return selectedArtifactIndex > 0
  }

  public var canSelectNextArtifact: Bool {
    guard let selectedArtifactIndex else {
      return false
    }
    return selectedArtifactIndex < filteredArtifacts.count - 1
  }

  public var selectedArtifactComments: [ValidationGalleryNumberedComment] {
    numberedComments(for: selectedArtifact)
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
    selectedArtifactID = artifactID
    selectionFeedback = nil
    normalizeSelectionAfterFilterChange()
    normalizeSelectedComment()
  }

  public func clearFilters() {
    selectionFeedback = nil
    searchText = ""
    sidebarSelection = .all
    normalizeSelectedComment()
  }

  public func dismissSelectionFeedback() {
    selectionFeedback = nil
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
      selectedArtifactID = nil
      selectionFeedback = nil
      selectedCommentID = nil
      return
    }

    if let selectedArtifactID,
      visibleArtifacts.contains(where: { $0.id == selectedArtifactID })
    {
      selectionFeedback = nil
      normalizeSelectedComment()
      return
    }

    let previousSelectionID = selectedArtifactID
    selectedArtifactID = visibleArtifacts.first?.id
    if previousSelectionID != nil, let selectedArtifact {
      selectionFeedback = ValidationGallerySelectionFeedback(
        kind: .autoSelected,
        title: "Showing the first match",
        message: ValidationGalleryFormatting.selectionUpdatedMessage(for: selectedArtifact)
      )
    } else {
      selectionFeedback = nil
    }
    normalizeSelectedComment()
  }

  func normalizeSelectedComment() {
    let visibleComments = selectedArtifactComments
    if let selectedCommentID, visibleComments.contains(where: { $0.id == selectedCommentID }) {
      return
    }

    selectedCommentID = visibleComments.first?.id
  }

  var currentBundleRootKey: String? {
    snapshot?.bundleRootURL.standardizedFileURL.path
  }

  func numberedCurrentBundleComments() -> [NumberedCommentItem] {
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

  private var selectedArtifactIndex: Int? {
    guard let selectedArtifact else {
      return nil
    }
    return filteredArtifacts.firstIndex(where: { $0.id == selectedArtifact.id })
  }

  private func updateSelectedArtifact(by offset: Int) {
    guard let selectedArtifactIndex else {
      return
    }

    let targetIndex = min(max(selectedArtifactIndex + offset, 0), filteredArtifacts.count - 1)
    guard targetIndex != selectedArtifactIndex else {
      return
    }

    selectedArtifactID = filteredArtifacts[targetIndex].id
    selectionFeedback = nil
    normalizeSelectedComment()
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
