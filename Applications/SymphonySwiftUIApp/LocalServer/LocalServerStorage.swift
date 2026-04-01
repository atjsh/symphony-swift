#if os(macOS)
  import AppKit
  import Foundation
  import Security
  import SymphonyShared

  struct UserDefaultsLocalServerProfileStore: LocalServerProfileStoring {
    private let key: String
    private let userDefaults: UserDefaults

    init(
      key: String = "Symphony.LocalServerProfile",
      userDefaults: UserDefaults = .standard
    ) {
      self.key = key
      self.userDefaults = userDefaults
    }

    func loadProfile() -> LocalServerProfile? {
      guard let data = userDefaults.data(forKey: key) else {
        return nil
      }
      return try? JSONDecoder().decode(LocalServerProfile.self, from: data)
    }

    func saveProfile(_ profile: LocalServerProfile) throws {
      let data = try JSONEncoder().encode(profile)
      userDefaults.set(data, forKey: key)
    }

    func clearProfile() throws {
      userDefaults.removeObject(forKey: key)
    }
  }

  struct InMemoryLocalServerProfileStore: LocalServerProfileStoring {
    final class Storage: @unchecked Sendable {
      var profile: LocalServerProfile?

      init(profile: LocalServerProfile?) {
        self.profile = profile
      }
    }

    private let storage: Storage

    init(profile: LocalServerProfile? = nil) {
      self.storage = Storage(profile: profile)
    }

    func loadProfile() -> LocalServerProfile? {
      storage.profile
    }

    func saveProfile(_ profile: LocalServerProfile) throws {
      storage.profile = profile
    }

    func clearProfile() throws {
      storage.profile = nil
    }
  }

  struct KeychainLocalServerSecretStore: LocalServerSecretStoring {
    private let service: String

    init(service: String = "dev.atjsh.symphony.local-server") {
      self.service = service
    }

    func secret(for key: String) -> String? {
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: key,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
      ]

      var item: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &item)
      guard status == errSecSuccess,
        let data = item as? Data
      else {
        return nil
      }

      return String(data: data, encoding: .utf8)
    }

    func setSecret(_ value: String, for key: String) throws {
      let encodedValue = Data(value.utf8)
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: key,
      ]

      let attributes: [String: Any] = [
        kSecValueData as String: encodedValue
      ]

      let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
      if updateStatus == errSecItemNotFound {
        var insert = query
        insert[kSecValueData as String] = encodedValue
        let insertStatus = SecItemAdd(insert as CFDictionary, nil)
        guard insertStatus == errSecSuccess else {
          throw LocalServerLaunchError.startupFailed("Failed to store \(key) in the keychain.")
        }
        return
      }

      guard updateStatus == errSecSuccess else {
        throw LocalServerLaunchError.startupFailed("Failed to update \(key) in the keychain.")
      }
    }

    func removeSecret(for key: String) throws {
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: key,
      ]
      let status = SecItemDelete(query as CFDictionary)
      guard status == errSecSuccess || status == errSecItemNotFound else {
        throw LocalServerLaunchError.startupFailed("Failed to remove \(key) from the keychain.")
      }
    }
  }

  struct InMemoryLocalServerSecretStore: LocalServerSecretStoring {
    final class Storage: @unchecked Sendable {
      var values: [String: String]

      init(values: [String: String]) {
        self.values = values
      }
    }

    private let storage: Storage

    init(values: [String: String] = [:]) {
      self.storage = Storage(values: values)
    }

    func secret(for key: String) -> String? {
      storage.values[key]
    }

    func setSecret(_ value: String, for key: String) throws {
      storage.values[key] = value
    }

    func removeSecret(for key: String) throws {
      storage.values.removeValue(forKey: key)
    }
  }

  struct WorkflowEnvironmentVariableScanner: LocalServerVariableScanning {
    func scanVariables(at workflowURL: URL) throws -> [String] {
      let contents = try String(contentsOf: workflowURL, encoding: .utf8)
      let regex = try NSRegularExpression(pattern: "\\$([A-Za-z_][A-Za-z0-9_]*)")
      let range = NSRange(contents.startIndex..<contents.endIndex, in: contents)
      var values = Set<String>()

      for match in regex.matches(in: contents, range: range) {
        guard let variableRange = Range(match.range(at: 1), in: contents) else {
          continue
        }
        values.insert(String(contents[variableRange]))
      }

      return values.sorted()
    }
  }

  struct NSOpenPanelWorkflowSelector: LocalWorkflowSelecting {
    func selectWorkflowURL() -> URL? {
      let panel = NSOpenPanel()
      panel.title = "Choose WORKFLOW.md"
      panel.prompt = "Choose"
      panel.canChooseDirectories = false
      panel.canChooseFiles = true
      panel.allowsMultipleSelection = false
      panel.allowedContentTypes = []
      panel.nameFieldStringValue = "WORKFLOW.md"
      return panel.runModal() == .OK ? panel.url : nil
    }
  }

  struct NSSavePanelWorkflowSaver: LocalWorkflowSaving {
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
      self.fileManager = fileManager
    }

    func saveWorkflow(
      named fileName: String,
      suggestedDirectoryURL: URL?,
      content: String
    ) throws -> URL? {
      let panel = NSSavePanel()
      panel.title = "Save WORKFLOW.md"
      panel.prompt = "Save"
      panel.canCreateDirectories = true
      panel.nameFieldStringValue = fileName
      panel.directoryURL = suggestedDirectoryURL ?? fileManager.homeDirectoryForCurrentUser

      guard panel.runModal() == .OK, let destinationURL = panel.url else {
        return nil
      }

      try content.write(to: destinationURL, atomically: true, encoding: .utf8)
      return destinationURL
    }
  }

  struct UITestingWorkflowFileSaver: LocalWorkflowSaving {
    let fileManager: FileManager
    let environmentProvider: @Sendable () -> [String: String]

    init(
      fileManager: FileManager = .default,
      environmentProvider: @escaping @Sendable () -> [String: String]
    ) {
      self.fileManager = fileManager
      self.environmentProvider = environmentProvider
    }

    func saveWorkflow(
      named fileName: String,
      suggestedDirectoryURL: URL?,
      content: String
    ) throws -> URL? {
      let environment = environmentProvider()
      let baseDirectory =
        environment["SYMPHONY_UI_TESTING_WORKFLOW_DIRECTORY"].map {
          URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath, isDirectory: true)
        }
        ?? suggestedDirectoryURL
        ?? fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
      try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

      let resolvedFileName = environment["SYMPHONY_UI_TESTING_WORKFLOW_FILENAME"] ?? fileName
      let workflowURL = baseDirectory.appendingPathComponent(resolvedFileName, isDirectory: false)
      try content.write(to: workflowURL, atomically: true, encoding: .utf8)
      return workflowURL
    }
  }

  struct StubWorkflowSelector: LocalWorkflowSelecting {
    var selectedURL: URL?

    func selectWorkflowURL() -> URL? {
      selectedURL
    }
  }

  struct BundledLocalServerHelperLocator: LocalServerHelperLocating {
    let bundle: Bundle
    let fileManager: FileManager

    init(bundle: Bundle = .main, fileManager: FileManager = .default) {
      self.bundle = bundle
      self.fileManager = fileManager
    }

    func helperURL() throws -> URL {
      let candidates = [
        bundle.bundleURL.appendingPathComponent("Contents/Resources/SymphonyLocalServerHelper"),
        bundle.bundleURL.appendingPathComponent("Contents/Helpers/SymphonyLocalServerHelper"),
        bundle.bundleURL.appendingPathComponent("Contents/MacOS/SymphonyLocalServerHelper"),
        bundle.bundleURL.deletingLastPathComponent().appendingPathComponent("SymphonyLocalServerHelper"),
      ]

      for candidate in candidates where fileManager.isExecutableFile(atPath: candidate.path) {
        return candidate
      }

      throw LocalServerLaunchError.helperUnavailable(candidates[0].path)
    }
  }

  struct StubHelperLocator: LocalServerHelperLocating {
    var url: URL

    func helperURL() throws -> URL {
      url
    }
  }

#endif
