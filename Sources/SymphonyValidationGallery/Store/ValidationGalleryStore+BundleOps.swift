import Foundation

extension ValidationGalleryStore {

  public func restoreRecents() async {
    do {
      recentBundles = try await recentBundleStore.loadRecentBundles()
        .sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    } catch {
      self.error = .loadFailed(error.localizedDescription)
    }
  }

  public func restoreLastOpenedBundle() async {
    await restoreRecents()
    guard let recent = recentBundles.first else {
      return
    }

    do {
      let source = try source(for: recent)
      await open(source, rememberRecent: false)
    } catch let galleryError as ValidationGalleryError {
      self.error = galleryError
    } catch {
      self.error = .loadFailed(error.localizedDescription)
    }
  }

  public func open(_ source: ValidationBundleSource, rememberRecent: Bool = true) async {
    isLoading = true
    error = nil
    selectionFeedback = nil

    let access = ValidationScopedResourceAccess(urls: [source.url, source.bundleRootURL])
    activeAccess = access

    defer {
      isLoading = false
    }

    do {
      let snapshot = try await loader.load(from: source)
      self.snapshot = snapshot

      if rememberRecent {
        try await persistRecentBundle(for: source)
      }

      normalizeSelectionAfterFilterChange()
    } catch let galleryError as ValidationGalleryError {
      self.error = galleryError
      self.snapshot = nil
      self.selectedArtifactID = nil
    } catch {
      self.error = .loadFailed(error.localizedDescription)
      self.snapshot = nil
      self.selectedArtifactID = nil
    }
  }

  public func openRecent(_ recentBundle: ValidationRecentBundle) async {
    do {
      let source = try source(for: recentBundle)
      await open(source, rememberRecent: false)
    } catch let galleryError as ValidationGalleryError {
      self.error = galleryError
    } catch {
      self.error = .loadFailed(error.localizedDescription)
    }
  }

  public func setBrowserDisplayMode(_ displayMode: ValidationGalleryBrowserDisplayMode) {
    guard workspacePreferences.browserDisplayMode != displayMode else {
      return
    }

    workspacePreferences.browserDisplayMode = displayMode
    persistWorkspacePreferences()
  }

  public func setMacPreviewEmphasis(_ emphasis: ValidationGalleryMacPreviewEmphasis) {
    guard workspacePreferences.macPreviewEmphasis != emphasis else {
      return
    }

    workspacePreferences.macPreviewEmphasis = emphasis
    persistWorkspacePreferences()
  }

  public func setInspectorPreviewHeight(_ height: Double) {
    workspacePreferences.inspectorPreviewHeight = height
    persistWorkspacePreferences()
  }

  public func present(error: ValidationGalleryError) {
    self.error = error
  }

  func source(for recentBundle: ValidationRecentBundle) throws -> ValidationBundleSource {
    let resolvedURL: URL
    if let bookmarkData = recentBundle.bookmarkData {
      let resolved = try resolveBookmark(bookmarkData)
      if resolved.isStale {
        throw ValidationGalleryError.bookmarkStale(recentBundle.displayName)
      }
      resolvedURL = resolved.url
    } else {
      resolvedURL = URL(fileURLWithPath: recentBundle.fallbackPath)
    }

    switch recentBundle.kind {
    case .folder:
      return .folder(resolvedURL)
    case .manifestFile:
      return .manifestFile(resolvedURL)
    }
  }

  func persistRecentBundle(for source: ValidationBundleSource) async throws {
    let bookmarkData = try? makeBookmark(source.url)
    let recentBundle = ValidationRecentBundle(
      kind: source.kind,
      displayName: source.displayName,
      bookmarkData: bookmarkData,
      fallbackPath: source.url.path,
      lastOpenedAt: now()
    )

    var recents = try await recentBundleStore.loadRecentBundles()
    recents.removeAll { $0.id == recentBundle.id }
    recents.insert(recentBundle, at: 0)
    if recents.count > 8 {
      recents.removeSubrange(8...)
    }

    try await recentBundleStore.saveRecentBundles(recents)
    recentBundles = recents
  }

  func persistWorkspacePreferences() {
    try? workspacePreferencesStore.saveWorkspacePreferences(workspacePreferences)
  }
}
