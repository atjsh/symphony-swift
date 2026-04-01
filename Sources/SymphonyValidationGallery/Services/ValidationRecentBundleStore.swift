import Foundation

public actor UserDefaultsValidationRecentBundleStore: ValidationRecentBundlePersisting {
  private let userDefaults: UserDefaults
  private let storageKey: String
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  public init(
    userDefaults: UserDefaults = .standard,
    storageKey: String = "XcodeValidationGallery.recentBundles"
  ) {
    self.userDefaults = userDefaults
    self.storageKey = storageKey

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    self.encoder = encoder

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    self.decoder = decoder
  }

  public func loadRecentBundles() async throws -> [ValidationRecentBundle] {
    guard let data = userDefaults.data(forKey: storageKey) else {
      return []
    }
    return try decoder.decode([ValidationRecentBundle].self, from: data)
  }

  public func saveRecentBundles(_ recentBundles: [ValidationRecentBundle]) async throws {
    let data = try encoder.encode(recentBundles)
    userDefaults.set(data, forKey: storageKey)
  }
}
