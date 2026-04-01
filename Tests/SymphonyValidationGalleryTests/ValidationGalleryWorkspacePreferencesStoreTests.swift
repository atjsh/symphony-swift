import Foundation
import Testing

@testable import SymphonyValidationGallery

@Suite("ValidationGalleryWorkspacePreferencesStore")
struct ValidationGalleryWorkspacePreferencesStoreTests {
  @Test func userDefaultsStoreRoundTripsWorkspacePreferences() throws {
    let suiteName = "ValidationGalleryWorkspacePreferencesStoreTests.\(UUID().uuidString)"
    let userDefaults = try #require(UserDefaults(suiteName: suiteName))
    defer {
      userDefaults.removePersistentDomain(forName: suiteName)
    }

    let store = UserDefaultsValidationGalleryWorkspacePreferencesStore(
      userDefaults: userDefaults,
      storageKey: "workspacePreferences"
    )
    let preferences = ValidationGalleryWorkspacePreferences(
      browserDisplayMode: .grid,
      macPreviewEmphasis: .standard
    )

    try store.saveWorkspacePreferences(preferences)

    let reloadedStore = UserDefaultsValidationGalleryWorkspacePreferencesStore(
      userDefaults: userDefaults,
      storageKey: "workspacePreferences"
    )

    #expect(try reloadedStore.loadWorkspacePreferences() == preferences)
  }
}
