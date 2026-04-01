import SwiftUI
import SymphonyShared
import Testing

@testable import SymphonySwiftUIApp

#if canImport(AppKit)
  import AppKit
#endif

@MainActor
@Suite("EndpointEditorView – Helpers & Rendering", .tags(.views))
struct EndpointEditorViewTests {
  @Test func EndpointEditorHelpersRenderDismissAndConnect() async throws {
    let client = ActionDrivenSymphonyAPIClient()
    let model = SymphonyOperatorModel(client: client)
    model.host = "  example.com  "
    model.portText = "  9443 "
    model.connectionError = "Timed out"

    render(host(AnyView(OperatorEndpointEditorView(model: model)), width: 640, height: 480))

    var dismissCount = 0
    let dismissAction = OperatorEndpointEditorView.makeEndpointDismissAction {
      dismissCount += 1
    }
    dismissAction()
    #expect(dismissCount == 1)

    let connectAction = OperatorEndpointEditorView.makeEndpointConnectAction(
      model: model,
      draftHost: "  example.com  ",
      draftPort: "  9443 "
    ) {
      dismissCount += 1
    }
    connectAction()

    try await waitUntil {
      model.health?.trackerKind == "github"
        && model.connectionError == nil
        && dismissCount == 2
    }

    #expect(model.host == "example.com")
    #expect(model.portText == "9443")

    #if os(macOS)
      let workflowURL = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString
      ).appendingPathComponent("WORKFLOW.md")
      try FileManager.default.createDirectory(
        at: workflowURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try "Resolve {{issue.title}}".write(to: workflowURL, atomically: true, encoding: .utf8)

      let localManager = UITestingLocalServerManager()
      let localModel = SymphonyOperatorModel(
        client: client,
        localServerServices: LocalServerServices(
          manager: localManager,
          profileStore: InMemoryLocalServerProfileStore(
            profile: LocalServerProfile(workflowPath: workflowURL.path)
          ),
          secretStore: InMemoryLocalServerSecretStore(),
          workflowSelector: StubWorkflowSelector(selectedURL: workflowURL),
          workflowSaver: UITestingWorkflowFileSaver(environmentProvider: { [:] }),
          variableScanner: WorkflowEnvironmentVariableScanner(),
          helperLocator: StubHelperLocator(
            url: URL(fileURLWithPath: "/tmp/SymphonyLocalServerHelper")
          ),
          environmentProvider: { [:] }
        )
      )
      render(
        host(
          AnyView(OperatorEndpointEditorView(model: localModel, initialMode: .localServer)),
          width: 700,
          height: 620
        )
      )

      let localStartAction = OperatorEndpointEditorView.makeLocalServerStartAction(
        model: localModel,
        draftHost: "localhost",
        draftPort: "8080"
      ) {
        dismissCount += 1
      }
      localStartAction()

      try await waitUntil {
        localModel.localServerLaunchState == .running && dismissCount == 3
      }

      let localStopAction = OperatorEndpointEditorView.makeLocalServerStopAction(
        model: localModel)
      localStopAction()
      try await waitUntil {
        localModel.localServerLaunchState == .idle
      }
    #endif
  }

  @Test func EndpointEditorModeMetadataRemainsStable() {
    #expect(ServerEditorMode.localServer.id == "localServer")
    #expect(ServerEditorMode.existingServer.id == "existingServer")
    #expect(ServerEditorMode.localServer.title == "Local Server")
    #expect(ServerEditorMode.existingServer.title == "Existing Server")
  }

  @Test func MacOSEndpointEditorReportsUsableExistingAndWorkflowHeights() throws {
    #if os(macOS)
      let existingModel = SymphonyOperatorModel(client: PassiveSymphonyAPIClient())
      let existingSize = fittingSize(
        AnyView(OperatorEndpointEditorView(model: existingModel)))
      #expect(existingSize.width >= 680)
      #expect(existingSize.height >= 360)

      let workflowModel = SymphonyOperatorModel(
        client: PassiveSymphonyAPIClient(),
        localServerServices: LocalServerServices(
          manager: UITestingLocalServerManager(),
          profileStore: InMemoryLocalServerProfileStore(),
          secretStore: InMemoryLocalServerSecretStore(),
          workflowSelector: StubWorkflowSelector(selectedURL: nil),
          workflowSaver: UITestingWorkflowFileSaver(environmentProvider: { [:] }),
          variableScanner: WorkflowEnvironmentVariableScanner(),
          helperLocator: StubHelperLocator(
            url: URL(fileURLWithPath: "/tmp/SymphonyLocalServerHelper")
          ),
          environmentProvider: { [:] }
        )
      )

      let workflowSize = fittingSize(
        AnyView(
          OperatorEndpointEditorView(model: workflowModel, initialMode: .localServer))
      )
      #expect(workflowSize.width >= 1040)
      #expect(workflowSize.height >= 620)
      #expect(workflowSize.height > existingSize.height)
    #endif
  }

  #if os(macOS)
    @Test func EndpointEditorRendersLocalServerWithNoWorkflow() {
      let localModel = SymphonyOperatorModel(
        client: PassiveSymphonyAPIClient(),
        localServerServices: LocalServerServices(
          manager: UITestingLocalServerManager(),
          profileStore: InMemoryLocalServerProfileStore(),
          secretStore: InMemoryLocalServerSecretStore(),
          workflowSelector: StubWorkflowSelector(selectedURL: nil),
          workflowSaver: UITestingWorkflowFileSaver(environmentProvider: { [:] }),
          variableScanner: WorkflowEnvironmentVariableScanner(),
          helperLocator: StubHelperLocator(
            url: URL(fileURLWithPath: "/tmp/SymphonyLocalServerHelper")
          ),
          environmentProvider: { [:] }
        )
      )
      localModel.prepareLocalServerEditor(mode: .localServer)
      #expect(localModel.localWorkflowWizardStep == .workflow)

      render(
        host(
          AnyView(OperatorEndpointEditorView(model: localModel, initialMode: .localServer)),
          width: 700,
          height: 620
        )
      )
    }

    @Test func EndpointEditorRendersLocalServerWithConfiguredWorkflow() throws {
      let workflowURL = try makeTemporaryWorkflowFile()
      let localModel = SymphonyOperatorModel(
        client: PassiveSymphonyAPIClient(),
        localServerServices: LocalServerServices(
          manager: UITestingLocalServerManager(),
          profileStore: InMemoryLocalServerProfileStore(
            profile: LocalServerProfile(workflowPath: workflowURL.path)
          ),
          secretStore: InMemoryLocalServerSecretStore(),
          workflowSelector: StubWorkflowSelector(selectedURL: workflowURL),
          workflowSaver: UITestingWorkflowFileSaver(environmentProvider: { [:] }),
          variableScanner: WorkflowEnvironmentVariableScanner(),
          helperLocator: StubHelperLocator(
            url: URL(fileURLWithPath: "/tmp/SymphonyLocalServerHelper")
          ),
          environmentProvider: { [:] }
        )
      )
      localModel.prepareLocalServerEditor(mode: .localServer)
      #expect(localModel.localWorkflowWizardStep == .localServer)

      render(
        host(
          AnyView(OperatorEndpointEditorView(model: localModel, initialMode: .localServer)),
          width: 700,
          height: 620
        )
      )
    }

    @Test func EndpointEditorRendersLocalServerInRunningState() async throws {
      let workflowURL = try makeTemporaryWorkflowFile()
      let manager = RecordingLocalServerManager()
      manager.nextStartSnapshot = LocalServerStatusSnapshot(
        state: .running,
        endpoint: BootstrapServerEndpoint(scheme: "http", host: "localhost", port: 8080),
        transcript: ["[SymphonyServer] starting", "[SymphonyServer] ready"],
        failureDescription: nil,
        processIdentifier: 99
      )
      let client = ActionDrivenSymphonyAPIClient()
      let localModel = SymphonyOperatorModel(
        client: client,
        localServerServices: LocalServerServices(
          manager: manager,
          profileStore: InMemoryLocalServerProfileStore(
            profile: LocalServerProfile(workflowPath: workflowURL.path)
          ),
          secretStore: InMemoryLocalServerSecretStore(),
          workflowSelector: StubWorkflowSelector(selectedURL: workflowURL),
          workflowSaver: UITestingWorkflowFileSaver(environmentProvider: { [:] }),
          variableScanner: WorkflowEnvironmentVariableScanner(),
          helperLocator: StubHelperLocator(
            url: URL(fileURLWithPath: "/tmp/SymphonyLocalServerHelper")
          ),
          environmentProvider: { [:] }
        )
      )
      localModel.chooseLocalWorkflow()
      await localModel.startLocalServer()

      try await waitUntil { localModel.localServerLaunchState == .running }

      render(
        host(
          AnyView(OperatorEndpointEditorView(model: localModel, initialMode: .localServer)),
          width: 700,
          height: 620
        )
      )
    }

    @Test func EndpointEditorRendersLocalServerInFailedState() async throws {
      let workflowURL = try makeTemporaryWorkflowFile()
      let manager = RecordingLocalServerManager()
      manager.nextStartSnapshot = LocalServerStatusSnapshot(
        state: .failed,
        endpoint: BootstrapServerEndpoint.defaultEndpoint,
        transcript: ["[SymphonyServer] failed to start: port in use"],
        failureDescription: "Port 8080 is already in use.",
        processIdentifier: nil
      )
      let localModel = SymphonyOperatorModel(
        client: MockSymphonyAPIClient(),
        localServerServices: LocalServerServices(
          manager: manager,
          profileStore: InMemoryLocalServerProfileStore(
            profile: LocalServerProfile(workflowPath: workflowURL.path)
          ),
          secretStore: InMemoryLocalServerSecretStore(),
          workflowSelector: StubWorkflowSelector(selectedURL: workflowURL),
          workflowSaver: UITestingWorkflowFileSaver(environmentProvider: { [:] }),
          variableScanner: WorkflowEnvironmentVariableScanner(),
          helperLocator: StubHelperLocator(
            url: URL(fileURLWithPath: "/tmp/SymphonyLocalServerHelper")
          ),
          environmentProvider: { [:] }
        )
      )
      localModel.chooseLocalWorkflow()
      await localModel.startLocalServer()

      try await waitUntil { localModel.localServerLaunchState == .failed }

      render(
        host(
          AnyView(OperatorEndpointEditorView(model: localModel, initialMode: .localServer)),
          width: 700,
          height: 620
        )
      )
    }
  #endif
}
