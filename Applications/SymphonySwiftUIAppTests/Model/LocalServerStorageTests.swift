#if os(macOS)
  import Foundation
  import Testing

  @testable import SymphonySwiftUIApp

  @Suite("LocalServerStorage", .tags(.model, .localServer))
  struct LocalServerStorageTests {

    // MARK: - UserDefaultsLocalServerProfileStore

    @Test func profileStoreRoundTrips() throws {
      let suiteName = "dev.atjsh.symphony.test.\(UUID().uuidString)"
      let defaults = try #require(UserDefaults(suiteName: suiteName))
      defer { defaults.removePersistentDomain(forName: suiteName) }

      let store = UserDefaultsLocalServerProfileStore(key: "TestProfile", userDefaults: defaults)

      #expect(store.loadProfile() == nil)

      let profile = LocalServerProfile(
        workflowPath: "/tmp/WORKFLOW.md",
        host: "127.0.0.1",
        port: 9090,
        sqlitePath: "/tmp/db.sqlite3",
        environmentKeys: ["GITHUB_TOKEN", "OPENAI_API_KEY"]
      )
      try store.saveProfile(profile)

      let loaded = try #require(store.loadProfile())
      #expect(loaded == profile)
      #expect(loaded.host == "127.0.0.1")
      #expect(loaded.port == 9090)
      #expect(loaded.environmentKeys == ["GITHUB_TOKEN", "OPENAI_API_KEY"])
    }

    @Test func profileStoreClearRemovesProfile() throws {
      let suiteName = "dev.atjsh.symphony.test.\(UUID().uuidString)"
      let defaults = try #require(UserDefaults(suiteName: suiteName))
      defer { defaults.removePersistentDomain(forName: suiteName) }

      let store = UserDefaultsLocalServerProfileStore(key: "TestProfile", userDefaults: defaults)
      try store.saveProfile(LocalServerProfile(workflowPath: "/tmp/W.md"))
      #expect(store.loadProfile() != nil)

      try store.clearProfile()
      #expect(store.loadProfile() == nil)
    }

    // MARK: - InMemoryLocalServerProfileStore

    @Test func inMemoryProfileStoreRoundTrips() throws {
      let store = InMemoryLocalServerProfileStore()
      #expect(store.loadProfile() == nil)

      let profile = LocalServerProfile(workflowPath: "/tmp/WORKFLOW.md")
      try store.saveProfile(profile)
      #expect(store.loadProfile() == profile)

      try store.clearProfile()
      #expect(store.loadProfile() == nil)
    }

    @Test func inMemoryProfileStoreInitializesWithProfile() {
      let profile = LocalServerProfile(workflowPath: "/tmp/W.md", host: "h", port: 1)
      let store = InMemoryLocalServerProfileStore(profile: profile)
      #expect(store.loadProfile() == profile)
    }

    // MARK: - InMemoryLocalServerSecretStore

    @Test func inMemorySecretStoreRoundTrips() throws {
      let store = InMemoryLocalServerSecretStore()
      #expect(store.secret(for: "TOKEN") == nil)

      try store.setSecret("abc123", for: "TOKEN")
      #expect(store.secret(for: "TOKEN") == "abc123")

      try store.removeSecret(for: "TOKEN")
      #expect(store.secret(for: "TOKEN") == nil)
    }

    @Test func inMemorySecretStoreInitializesWithValues() {
      let store = InMemoryLocalServerSecretStore(values: ["K": "V"])
      #expect(store.secret(for: "K") == "V")
    }

    // MARK: - WorkflowEnvironmentVariableScanner

    @Test func scannerExtractsVariableNames() throws {
      let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      let url = dir.appendingPathComponent("WORKFLOW.md")
      try """
        ---
        tracker:
          api_key: $GITHUB_TOKEN
        ---
        Use $OPENAI_API_KEY and $GITHUB_TOKEN again.
        Also $CUSTOM_VAR here.
        """.write(to: url, atomically: true, encoding: .utf8)

      let scanner = WorkflowEnvironmentVariableScanner()
      let variables = try scanner.scanVariables(at: url)

      #expect(variables == ["CUSTOM_VAR", "GITHUB_TOKEN", "OPENAI_API_KEY"])
    }

    @Test func scannerReturnsEmptyForNoVariables() throws {
      let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      let url = dir.appendingPathComponent("WORKFLOW.md")
      try "No variables here.".write(to: url, atomically: true, encoding: .utf8)

      let scanner = WorkflowEnvironmentVariableScanner()
      let variables = try scanner.scanVariables(at: url)

      #expect(variables.isEmpty)
    }

    // MARK: - BundledLocalServerHelperLocator

    @Test func locatorFindsExecutableHelper() throws {
      let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
      let helperPath = dir.appendingPathComponent("Contents/MacOS/SymphonyLocalServerHelper")
      try FileManager.default.createDirectory(
        at: helperPath.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try "#!/bin/sh\n".write(to: helperPath, atomically: true, encoding: .utf8)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: helperPath.path
      )

      let bundle = Bundle(url: dir)!
      let locator = BundledLocalServerHelperLocator(bundle: bundle)
      let found = try locator.helperURL()

      #expect(found == helperPath)
    }

    @Test func locatorThrowsWhenHelperMissing() throws {
      let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      let bundle = try #require(Bundle(url: dir))
      let locator = BundledLocalServerHelperLocator(
        bundle: bundle,
        fileManager: .default
      )

      #expect(throws: (any Error).self) {
        try locator.helperURL()
      }
    }

    // MARK: - StubHelperLocator

    @Test func stubHelperLocatorReturnsConfiguredURL() throws {
      let url = URL(fileURLWithPath: "/tmp/Helper")
      let locator = StubHelperLocator(url: url)
      #expect(try locator.helperURL() == url)
    }

    // MARK: - UITestingWorkflowFileSaver

    @MainActor @Test func uiTestingSaverUsesEnvironmentDirectoryAndFilename() throws {
      let baseDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
      let saver = UITestingWorkflowFileSaver(
        environmentProvider: {
          [
            "SYMPHONY_UI_TESTING_WORKFLOW_DIRECTORY": baseDir.path,
            "SYMPHONY_UI_TESTING_WORKFLOW_FILENAME": "custom.md",
          ]
        }
      )

      let result = try saver.saveWorkflow(
        named: "WORKFLOW.md",
        suggestedDirectoryURL: nil,
        content: "hello"
      )

      let expectedURL = baseDir.appendingPathComponent("custom.md")
      #expect(result == expectedURL)
      #expect(try String(contentsOf: expectedURL, encoding: .utf8) == "hello")
    }

    @MainActor @Test func uiTestingSaverFallsToSuggestedDirectory() throws {
      let suggestedDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
      let saver = UITestingWorkflowFileSaver(environmentProvider: { [:] })

      let result = try saver.saveWorkflow(
        named: "WORKFLOW.md",
        suggestedDirectoryURL: suggestedDir,
        content: "content"
      )

      let expectedURL = suggestedDir.appendingPathComponent("WORKFLOW.md")
      #expect(result == expectedURL)
    }

    // MARK: - LocalServerServices.uiTesting()

    @MainActor
    @Test func uiTestingFactoryCreatesWorkingServices() async {
      let services = LocalServerServices.uiTesting(environmentProvider: { [:] })

      #expect(services.profileStore.loadProfile() != nil)
      #expect(services.manager.statusSnapshot.state == .needsSetup)

      await services.manager.start(
        request: LocalServerLaunchRequest(
          helperURL: URL(fileURLWithPath: "/tmp/Helper"),
          workflowURL: URL(fileURLWithPath: "/tmp/WORKFLOW.md"),
          currentDirectoryURL: URL(fileURLWithPath: "/tmp"),
          endpoint: BootstrapServerEndpoint(scheme: "http", host: "localhost", port: 8080),
          environment: [:]
        )
      )
      #expect(services.manager.statusSnapshot.state == .running)
    }

    @MainActor
    @Test func uiTestingFactoryEmptyProfileMode() {
      let services = LocalServerServices.uiTesting(
        environmentProvider: { ["SYMPHONY_UI_TESTING_EMPTY_LOCAL_SERVER_PROFILE": "1"] }
      )
      #expect(services.profileStore.loadProfile() == nil)
    }
  }
#endif
