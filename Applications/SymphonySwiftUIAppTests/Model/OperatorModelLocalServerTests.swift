#if os(macOS)
  import Foundation
  import SymphonyShared
  import Testing

  @testable import SymphonySwiftUIApp

  @MainActor
  @Suite("OperatorModel – Local Server", .tags(.model, .localServer))
  struct OperatorModelLocalServerTests {
    @Test func LocalServerEditorStartsInWorkflowStepWhenWorkflowIsMissing() {
      let services = LocalServerServices(
        manager: RecordingLocalServerManager(),
        profileStore: InMemoryLocalServerProfileStore(),
        secretStore: InMemoryLocalServerSecretStore(),
        workflowSelector: StubWorkflowSelector(selectedURL: nil),
        workflowSaver: UITestingWorkflowFileSaver(environmentProvider: { [:] }),
        variableScanner: WorkflowEnvironmentVariableScanner(),
        helperLocator: StubHelperLocator(
          url: URL(fileURLWithPath: "/tmp/SymphonyLocalServerHelper")),
        environmentProvider: { [:] }
      )
      let model = SymphonyOperatorModel(
        client: MockSymphonyAPIClient(),
        localServerServices: services
      )

      model.prepareLocalServerEditor(mode: .localServer)

      #expect(model.localWorkflowWizardStep == .workflow)
    }

    @Test func LocalServerEditorStartsInLocalServerStepWhenWorkflowAlreadyExists() throws {
      let workflowURL = try makeTemporaryWorkflowFile()
      let services = LocalServerServices(
        manager: RecordingLocalServerManager(),
        profileStore: InMemoryLocalServerProfileStore(
          profile: LocalServerProfile(workflowPath: workflowURL.path)
        ),
        secretStore: InMemoryLocalServerSecretStore(),
        workflowSelector: StubWorkflowSelector(selectedURL: workflowURL),
        workflowSaver: UITestingWorkflowFileSaver(environmentProvider: { [:] }),
        variableScanner: WorkflowEnvironmentVariableScanner(),
        helperLocator: StubHelperLocator(
          url: URL(fileURLWithPath: "/tmp/SymphonyLocalServerHelper")),
        environmentProvider: { [:] }
      )
      let model = SymphonyOperatorModel(
        client: MockSymphonyAPIClient(),
        localServerServices: services
      )

      model.prepareLocalServerEditor(mode: .localServer)

      #expect(model.localWorkflowWizardStep == .localServer)
    }

    @Test func SavingGeneratedWorkflowPersistsProfileUpdatesEnvEntriesAndAdvances() throws {
      let profileStore = InMemoryLocalServerProfileStore()
      let secretStore = InMemoryLocalServerSecretStore()
      let manager = RecordingLocalServerManager()
      let saveURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("WORKFLOW.md", isDirectory: false)
      let saver = RecordingWorkflowSaver(saveURL: saveURL)
      let services = LocalServerServices(
        manager: manager,
        profileStore: profileStore,
        secretStore: secretStore,
        workflowSelector: StubWorkflowSelector(selectedURL: nil),
        workflowSaver: saver,
        variableScanner: WorkflowEnvironmentVariableScanner(),
        helperLocator: StubHelperLocator(
          url: URL(fileURLWithPath: "/tmp/SymphonyLocalServerHelper")),
        environmentProvider: { [:] }
      )

      let model = SymphonyOperatorModel(
        client: MockSymphonyAPIClient(),
        localServerServices: services
      )
      model.prepareLocalServerEditor(mode: .localServer)
      model.workflowAuthoringDraft.trackerProjectOwner = "atjsh"
      model.workflowAuthoringDraft.trackerProjectOwnerType = "organization"
      model.workflowAuthoringDraft.trackerProjectNumber = "7"
      model.workflowAuthoringDraft.promptBody = """
        Resolve {{issue.title}} with $OPENAI_API_KEY.
        """

      model.saveGeneratedWorkflow()

      #expect(model.localWorkflowWizardStep == .localServer)
      #expect(model.localServerWorkflowPath == saveURL.path)
      #expect(model.localServerEnvironmentEntries.map(\.name) == ["GITHUB_TOKEN", "OPENAI_API_KEY"])

      let persistedProfile = try #require(profileStore.loadProfile())
      #expect(persistedProfile.workflowPath == saveURL.path)
      #expect(saver.savedFileNames == [WorkflowAuthoringDraft.defaultWorkflowFileName])
      try #expect(String(contentsOf: saveURL, encoding: .utf8) == saver.savedContents.last)
    }

    @Test func LocalServerWorkflowSelectionBuildsLaunchEnvironmentAndPersistsDraft() throws {
      let workflowURL = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString
      ).appendingPathComponent("WORKFLOW.md")
      try FileManager.default.createDirectory(
        at: workflowURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try """
        ---
        tracker:
          api_key: $GITHUB_TOKEN
        ---
        Use $OPENAI_API_KEY and {{issue.title}}
        """.write(to: workflowURL, atomically: true, encoding: .utf8)

      let profileStore = InMemoryLocalServerProfileStore()
      let secretStore = InMemoryLocalServerSecretStore()
      let manager = RecordingLocalServerManager()
      let services = LocalServerServices(
        manager: manager,
        profileStore: profileStore,
        secretStore: secretStore,
        workflowSelector: StubWorkflowSelector(selectedURL: workflowURL),
        workflowSaver: UITestingWorkflowFileSaver(environmentProvider: { ["BASE": "1"] }),
        variableScanner: WorkflowEnvironmentVariableScanner(),
        helperLocator: StubHelperLocator(
          url: URL(fileURLWithPath: "/tmp/SymphonyLocalServerHelper")),
        environmentProvider: { ["BASE": "1"] }
      )

      let model = SymphonyOperatorModel(
        client: MockSymphonyAPIClient(),
        localServerServices: services
      )

      model.chooseLocalWorkflow()
      #expect(model.localServerWorkflowPath == workflowURL.path)
      #expect(
        model.localServerEnvironmentEntries.map(\.name) == ["GITHUB_TOKEN", "OPENAI_API_KEY"])

      model.host = "127.0.0.1"
      model.portText = "9090"
      model.localServerSQLitePath = "/tmp/symphony.sqlite3"
      model.localServerEnvironmentEntries[0].value = "gh-token"
      model.localServerEnvironmentEntries[1].value = "openai-token"

      let request = try model.testingMakeLocalServerLaunchRequest()
      #expect(request.endpoint.host == "127.0.0.1")
      #expect(request.endpoint.port == 9090)
      #expect(request.currentDirectoryURL == workflowURL.deletingLastPathComponent())
      #expect(request.environment["BASE"] == "1")
      #expect(request.environment["GITHUB_TOKEN"] == "gh-token")
      #expect(request.environment["OPENAI_API_KEY"] == "openai-token")
      #expect(request.environment[BootstrapEnvironment.serverHostKey] == "127.0.0.1")
      #expect(request.environment[BootstrapEnvironment.serverPortKey] == "9090")
      #expect(
        request.environment[SymphonyServerBootstrapEnvironment.workflowPathKey]
          == workflowURL.path)
      #expect(
        request.environment[SymphonyServerBootstrapEnvironment.serverSQLitePathKey]
          == "/tmp/symphony.sqlite3")

      try model.testingPersistLocalServerDraft()
      let persistedProfile = try #require(profileStore.loadProfile())
      #expect(persistedProfile.workflowPath == workflowURL.path)
      #expect(persistedProfile.host == "127.0.0.1")
      #expect(persistedProfile.port == 9090)
      #expect(persistedProfile.sqlitePath == "/tmp/symphony.sqlite3")
      #expect(persistedProfile.environmentKeys == ["GITHUB_TOKEN", "OPENAI_API_KEY"])
      #expect(secretStore.secret(for: "GITHUB_TOKEN") == "gh-token")
      #expect(secretStore.secret(for: "OPENAI_API_KEY") == "openai-token")
    }

    @Test func LocalServerStartTransitionsToRunningAndAutoConnects() async throws {
      let workflowURL = try makeTemporaryWorkflowFile()
      let client = MockSymphonyAPIClient()
      client.healthResponse = HealthResponse(
        status: "ok",
        serverTime: "2026-03-24T12:00:00Z",
        version: "1.0.0",
        trackerKind: "github"
      )
      client.issuesResponse = IssuesResponse(items: [makeIssueSummary()])

      let manager = RecordingLocalServerManager()
      manager.nextStartSnapshot = LocalServerStatusSnapshot(
        state: .running,
        endpoint: BootstrapServerEndpoint(scheme: "http", host: "localhost", port: 8080),
        transcript: ["[SymphonyServer] starting"],
        failureDescription: nil,
        processIdentifier: 4242
      )
      let services = LocalServerServices(
        manager: manager,
        profileStore: InMemoryLocalServerProfileStore(),
        secretStore: InMemoryLocalServerSecretStore(),
        workflowSelector: StubWorkflowSelector(selectedURL: workflowURL),
        workflowSaver: UITestingWorkflowFileSaver(environmentProvider: { [:] }),
        variableScanner: WorkflowEnvironmentVariableScanner(),
        helperLocator: StubHelperLocator(
          url: URL(fileURLWithPath: "/tmp/SymphonyLocalServerHelper")),
        environmentProvider: { [:] }
      )
      let model = SymphonyOperatorModel(client: client, localServerServices: services)
      model.chooseLocalWorkflow()

      await model.startLocalServer()
      try await waitUntil {
        model.localServerLaunchState == .running && model.health?.trackerKind == "github"
      }

      #expect(manager.startedRequests.count == 1)
      #expect(model.host == "localhost")
      #expect(model.portText == "8080")
      #expect(model.localServerFailure == nil)
      #expect(model.health?.status == "ok")
    }

    @Test func LocalServerStartMapsValidationAndManagerFailures() async throws {
      let workflowURL = try makeTemporaryWorkflowFile(contents: """
        ---
        tracker:
          api_key: $GITHUB_TOKEN
        ---
        Resolve {{issue.title}}
        """)
      let manager = RecordingLocalServerManager()
      manager.nextStartSnapshot = LocalServerStatusSnapshot(
        state: .failed,
        endpoint: BootstrapServerEndpoint.defaultEndpoint,
        transcript: ["[SymphonyServer] failed to start: Address already in use"],
        failureDescription: "Port 8080 is already in use.",
        processIdentifier: nil
      )
      let services = LocalServerServices(
        manager: manager,
        profileStore: InMemoryLocalServerProfileStore(),
        secretStore: InMemoryLocalServerSecretStore(),
        workflowSelector: StubWorkflowSelector(selectedURL: workflowURL),
        workflowSaver: UITestingWorkflowFileSaver(environmentProvider: { [:] }),
        variableScanner: WorkflowEnvironmentVariableScanner(),
        helperLocator: StubHelperLocator(
          url: URL(fileURLWithPath: "/tmp/SymphonyLocalServerHelper")),
        environmentProvider: { [:] }
      )
      let model = SymphonyOperatorModel(
        client: MockSymphonyAPIClient(),
        localServerServices: services
      )
      model.chooseLocalWorkflow()

      await model.startLocalServer()
      #expect(model.localServerLaunchState == .needsSetup)
      #expect(
        model.localServerFailure == "Fill in the required environment values: GITHUB_TOKEN.")

      model.localServerEnvironmentEntries[0].value = "gh-token"
      await model.startLocalServer()
      try await waitUntil {
        model.localServerLaunchState == .failed
      }

      #expect(model.localServerFailure == "Port 8080 is already in use.")
      #expect(
        model.localServerTranscript
          == ["[SymphonyServer] failed to start: Address already in use"])
    }

    @Test func LocalServerStopAndRestartUseManagerAndClearConnectionState() async throws {
      let workflowURL = try makeTemporaryWorkflowFile()
      let manager = RecordingLocalServerManager()
      manager.nextStartSnapshot = LocalServerStatusSnapshot(
        state: .running,
        endpoint: BootstrapServerEndpoint.defaultEndpoint,
        transcript: ["[SymphonyServer] starting"],
        failureDescription: nil,
        processIdentifier: 7
      )
      let client = MockSymphonyAPIClient()
      client.healthResponse = HealthResponse(
        status: "ok",
        serverTime: "2026-03-24T12:00:00Z",
        version: "1.0.0",
        trackerKind: "github"
      )
      client.issuesResponse = IssuesResponse(items: [makeIssueSummary()])
      let services = LocalServerServices(
        manager: manager,
        profileStore: InMemoryLocalServerProfileStore(),
        secretStore: InMemoryLocalServerSecretStore(),
        workflowSelector: StubWorkflowSelector(selectedURL: workflowURL),
        workflowSaver: UITestingWorkflowFileSaver(environmentProvider: { [:] }),
        variableScanner: WorkflowEnvironmentVariableScanner(),
        helperLocator: StubHelperLocator(
          url: URL(fileURLWithPath: "/tmp/SymphonyLocalServerHelper")),
        environmentProvider: { [:] }
      )
      let model = SymphonyOperatorModel(client: client, localServerServices: services)
      model.chooseLocalWorkflow()

      await model.startLocalServer()
      try await waitUntil {
        model.localServerLaunchState == .running && model.health != nil
      }

      await model.stopLocalServer()
      #expect(manager.stopCallCount == 1)
      #expect(model.health == nil)
      #expect(model.issues.isEmpty)
      #expect(model.localServerLaunchState == .idle)

      manager.nextRestartSnapshot = LocalServerStatusSnapshot(
        state: .running,
        endpoint: BootstrapServerEndpoint.defaultEndpoint,
        transcript: ["[SymphonyServer] restarting"],
        failureDescription: nil,
        processIdentifier: 9
      )
      await model.restartLocalServer()
      try await waitUntil {
        model.localServerLaunchState == .running && model.health != nil
      }

      #expect(manager.restartRequests.count == 1)
    }
  }
#endif
