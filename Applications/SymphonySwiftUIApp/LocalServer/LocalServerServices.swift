#if os(macOS)
  import Foundation
  import SymphonyServerCore
  import SymphonyShared

  @MainActor
  protocol LocalServerManaging: AnyObject {
    var statusSnapshot: LocalServerStatusSnapshot { get }
    var onStatusChange: ((LocalServerStatusSnapshot) -> Void)? { get set }
    func start(request: LocalServerLaunchRequest) async
    func stop() async
    func restart(request: LocalServerLaunchRequest) async
  }

  protocol LocalServerProfileStoring {
    func loadProfile() -> LocalServerProfile?
    func saveProfile(_ profile: LocalServerProfile) throws
    func clearProfile() throws
  }

  protocol LocalServerSecretStoring {
    func secret(for key: String) -> String?
    func setSecret(_ value: String, for key: String) throws
    func removeSecret(for key: String) throws
  }

  @MainActor
  protocol LocalWorkflowSelecting {
    func selectWorkflowURL() -> URL?
  }

  @MainActor
  protocol LocalWorkflowSaving {
    func saveWorkflow(
      named fileName: String,
      suggestedDirectoryURL: URL?,
      content: String
    ) throws -> URL?
  }

  protocol LocalServerVariableScanning {
    func scanVariables(at workflowURL: URL) throws -> [String]
  }

  protocol LocalServerHelperLocating {
    func helperURL() throws -> URL
  }

  protocol LocalServerProcessControlling: AnyObject {
    var processIdentifier: Int32 { get }
    func terminate()
  }

  protocol LocalServerProcessLaunching {
    func launch(
      request: LocalServerLaunchRequest,
      onOutput: @escaping @Sendable (String) -> Void,
      onExit: @escaping @Sendable (Int32) -> Void
    ) throws -> any LocalServerProcessControlling
  }

  struct LocalServerServices {
    var manager: any LocalServerManaging
    var profileStore: any LocalServerProfileStoring
    var secretStore: any LocalServerSecretStoring
    var workflowSelector: any LocalWorkflowSelecting
    var workflowSaver: any LocalWorkflowSaving
    var variableScanner: any LocalServerVariableScanning
    var helperLocator: any LocalServerHelperLocating
    var environmentProvider: @Sendable () -> [String: String]

    init(
      manager: any LocalServerManaging,
      profileStore: any LocalServerProfileStoring,
      secretStore: any LocalServerSecretStoring,
      workflowSelector: any LocalWorkflowSelecting,
      workflowSaver: any LocalWorkflowSaving,
      variableScanner: any LocalServerVariableScanning,
      helperLocator: any LocalServerHelperLocating,
      environmentProvider: @escaping @Sendable () -> [String: String]
    ) {
      self.manager = manager
      self.profileStore = profileStore
      self.secretStore = secretStore
      self.workflowSelector = workflowSelector
      self.workflowSaver = workflowSaver
      self.variableScanner = variableScanner
      self.helperLocator = helperLocator
      self.environmentProvider = environmentProvider
    }

    @MainActor
    static func live(
      bundle: Bundle = .main,
      environmentProvider: @escaping @Sendable () -> [String: String] = {
        ProcessInfo.processInfo.environment
      }
    ) -> Self {
      let manager = DefaultLocalServerManager()
      return Self(
        manager: manager,
        profileStore: UserDefaultsLocalServerProfileStore(),
        secretStore: KeychainLocalServerSecretStore(),
        workflowSelector: NSOpenPanelWorkflowSelector(),
        workflowSaver: NSSavePanelWorkflowSaver(),
        variableScanner: WorkflowEnvironmentVariableScanner(),
        helperLocator: BundledLocalServerHelperLocator(bundle: bundle),
        environmentProvider: environmentProvider
      )
    }

    @MainActor
    static func uiTesting(
      environmentProvider: @escaping @Sendable () -> [String: String] = {
        ProcessInfo.processInfo.environment
      }
    ) -> Self {
      let environment = environmentProvider()
      let startsWithoutWorkflowProfile = environment["SYMPHONY_UI_TESTING_EMPTY_LOCAL_SERVER_PROFILE"]
        == "1"
      let workflowURL = FileManager.default.temporaryDirectory.appendingPathComponent(
        "symphony-ui-testing-WORKFLOW.md",
        isDirectory: false
      )
      if !FileManager.default.fileExists(atPath: workflowURL.path) {
        try? """
          ---
          tracker:
            project_owner: atjsh
            project_owner_type: organization
            project_number: 1
          ---
          Resolve {{issue.title}}
          """.write(to: workflowURL, atomically: true, encoding: .utf8)
      }

      let profileStore = InMemoryLocalServerProfileStore(
        profile: startsWithoutWorkflowProfile
          ? nil
          : LocalServerProfile(
            workflowPath: workflowURL.path,
            host: "localhost",
            port: 8080,
            sqlitePath: nil,
            environmentKeys: []
          )
      )

      return Self(
        manager: UITestingLocalServerManager(),
        profileStore: profileStore,
        secretStore: InMemoryLocalServerSecretStore(),
        workflowSelector: StubWorkflowSelector(selectedURL: workflowURL),
        workflowSaver: UITestingWorkflowFileSaver(environmentProvider: { environment }),
        variableScanner: WorkflowEnvironmentVariableScanner(),
        helperLocator: StubHelperLocator(url: URL(fileURLWithPath: "/tmp/SymphonyLocalServerHelper")),
        environmentProvider: { environment }
      )
    }
  }

#endif
