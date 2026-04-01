import Foundation

public final class UserDefaultsValidationGalleryWorkspacePreferencesStore:
  ValidationGalleryWorkspacePreferencesPersisting
{
  private let userDefaults: UserDefaults
  private let storageKey: String
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  public init(
    userDefaults: UserDefaults = .standard,
    storageKey: String = "XcodeValidationGallery.workspacePreferences"
  ) {
    self.userDefaults = userDefaults
    self.storageKey = storageKey

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    self.encoder = encoder

    self.decoder = JSONDecoder()
  }

  public func loadWorkspacePreferences() throws -> ValidationGalleryWorkspacePreferences? {
    guard let data = userDefaults.data(forKey: storageKey) else {
      return nil
    }

    return try decoder.decode(ValidationGalleryWorkspacePreferences.self, from: data)
  }

  public func saveWorkspacePreferences(_ preferences: ValidationGalleryWorkspacePreferences) throws {
    let data = try encoder.encode(preferences)
    userDefaults.set(data, forKey: storageKey)
  }
}
