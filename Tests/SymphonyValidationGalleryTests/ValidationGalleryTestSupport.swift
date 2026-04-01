import Foundation

@testable import SymphonyValidationGallery

actor InMemoryRecentBundleStore: ValidationRecentBundlePersisting {
  private var recentBundles: [ValidationRecentBundle]

  init(recentBundles: [ValidationRecentBundle] = []) {
    self.recentBundles = recentBundles
  }

  func loadRecentBundles() async throws -> [ValidationRecentBundle] {
    recentBundles
  }

  func saveRecentBundles(_ recentBundles: [ValidationRecentBundle]) async throws {
    self.recentBundles = recentBundles
  }
}

final class InMemoryWorkspacePreferencesStore: ValidationGalleryWorkspacePreferencesPersisting {
  private(set) var workspacePreferences: ValidationGalleryWorkspacePreferences?

  init(workspacePreferences: ValidationGalleryWorkspacePreferences? = nil) {
    self.workspacePreferences = workspacePreferences
  }

  func loadWorkspacePreferences() throws -> ValidationGalleryWorkspacePreferences? {
    workspacePreferences
  }

  func saveWorkspacePreferences(_ preferences: ValidationGalleryWorkspacePreferences) throws {
    workspacePreferences = preferences
  }
}

actor StubValidationBundleLoader: ValidationBundleLoading {
  let snapshot: ValidationBundleSnapshot?

  init(snapshot: ValidationBundleSnapshot?) {
    self.snapshot = snapshot
  }

  func load(from source: ValidationBundleSource) async throws -> ValidationBundleSnapshot {
    guard let snapshot else {
      throw ValidationGalleryError.loadFailed("No snapshot available.")
    }
    return snapshot
  }
}

func screenshotArtifact(
  in snapshot: ValidationBundleSnapshot,
  checkpoint: String
) -> ValidationGalleryArtifact? {
  snapshot.artifacts.first(where: {
    $0.record.artifactType == .screenshot
      && $0.record.checkpoint == checkpoint
  })
}
