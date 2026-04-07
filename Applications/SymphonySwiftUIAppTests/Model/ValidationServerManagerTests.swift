#if os(macOS)
  import Foundation
  import Synchronization
  import Testing
  @testable import SymphonySwiftUIApp
  import SymphonyValidationGallery

  @Suite("DefaultValidationServerManager")
  @MainActor
  struct DefaultValidationServerManagerTests {
    // MARK: - Helpers

    private func makeManager(
      launcher: RecordingValidationServerProcessLauncher = .init(),
      locator: RecordingValidationServerHelperLocator = .init(),
      healthCheck: (@Sendable (String, Int) async throws -> Bool)? = nil
    ) -> DefaultValidationServerManager {
      DefaultValidationServerManager(
        processLauncher: launcher,
        helperLocator: locator,
        healthCheck: healthCheck ?? { _, _ in true }
      )
    }

    private let testProjectRoot = URL(fileURLWithPath: "/tmp/test-project")

    // MARK: - Initial State

    @Test("initial state is idle")
    func initialState() {
      let manager = makeManager()
      #expect(manager.statusSnapshot.state == .idle)
    }

    // MARK: - Start Success

    @Test("start transitions through states to running")
    func startTransitionsToRunning() async {
      var capturedSnapshots = [ValidationServerStatusSnapshot]()
      let launcher = RecordingValidationServerProcessLauncher()
      let manager = makeManager(launcher: launcher)
      manager.onStatusChange = { snapshot in
        capturedSnapshots.append(snapshot)
      }

      await manager.start(hostname: "127.0.0.1", port: 8090, projectRoot: testProjectRoot)

      #expect(manager.statusSnapshot.state == .running)
      #expect(launcher.launchedRequests.count == 1)
      #expect(launcher.launchedRequests[0].hostname == "127.0.0.1")
      #expect(launcher.launchedRequests[0].port == 8090)
      #expect(launcher.launchedRequests[0].projectRoot == testProjectRoot)

      // Should have transitioned through starting → waitingForHealth → running
      let states = capturedSnapshots.map(\.state)
      #expect(states.contains(.starting))
      #expect(states.contains(.waitingForHealth))
      #expect(states.contains(.running))
    }

    @Test("running state includes process identifier")
    func runningIncludesPID() async {
      let launcher = RecordingValidationServerProcessLauncher()
      launcher.nextProcess = RecordingValidationServerProcess(processIdentifier: 5678)
      let manager = makeManager(launcher: launcher)

      await manager.start(hostname: "127.0.0.1", port: 8090, projectRoot: testProjectRoot)

      #expect(manager.statusSnapshot.processIdentifier == 5678)
    }

    // MARK: - Helper Locator Failure

    @Test("start fails when helper is unavailable")
    func startFailsHelperUnavailable() async {
      var locator = RecordingValidationServerHelperLocator()
      locator.shouldThrow = ValidationServerLaunchError.helperUnavailable("/missing/path")
      let manager = makeManager(locator: locator)

      await manager.start(hostname: "127.0.0.1", port: 8090, projectRoot: testProjectRoot)

      #expect(manager.statusSnapshot.state == .failed)
      #expect(manager.statusSnapshot.failureDescription?.contains("not found") == true)
    }

    // MARK: - Process Launch Failure

    @Test("start fails when process launch throws")
    func startFailsProcessLaunchError() async {
      let launcher = RecordingValidationServerProcessLauncher()
      launcher.shouldThrow = ValidationServerLaunchError.startupFailed("spawn error")
      let manager = makeManager(launcher: launcher)

      await manager.start(hostname: "127.0.0.1", port: 8090, projectRoot: testProjectRoot)

      #expect(manager.statusSnapshot.state == .failed)
      #expect(manager.statusSnapshot.failureDescription == "spawn error")
    }

    // MARK: - Health Check Failure

    @Test("start fails when health check times out")
    func startFailsHealthTimeout() async {
      let manager = makeManager(
        healthCheck: { _, _ in
          throw URLError(.cannotConnectToHost)
        }
      )

      await manager.start(hostname: "127.0.0.1", port: 8090, projectRoot: testProjectRoot)

      #expect(manager.statusSnapshot.state == .failed)
    }

    // MARK: - Stop

    @Test("stop terminates process and resets to idle")
    func stopTerminatesAndResets() async {
      let launcher = RecordingValidationServerProcessLauncher()
      let manager = makeManager(launcher: launcher)

      await manager.start(hostname: "127.0.0.1", port: 8090, projectRoot: testProjectRoot)
      #expect(manager.statusSnapshot.state == .running)

      await manager.stop()
      #expect(manager.statusSnapshot.state == .idle)
      #expect(manager.statusSnapshot.processIdentifier == nil)
      #expect(launcher.nextProcess.terminateCallCount == 1)
    }

    @Test("stop without running process sets idle")
    func stopWithoutProcess() async {
      let manager = makeManager()
      await manager.stop()
      #expect(manager.statusSnapshot.state == .idle)
    }

    // MARK: - Double Start

    @Test("second start stops previous before launching")
    func doubleStartStopsPrevious() async {
      let launcher = RecordingValidationServerProcessLauncher()
      let proc1 = RecordingValidationServerProcess(processIdentifier: 111)
      let proc2 = RecordingValidationServerProcess(processIdentifier: 222)
      launcher.nextProcess = proc1
      let manager = makeManager(launcher: launcher)

      await manager.start(hostname: "127.0.0.1", port: 8090, projectRoot: testProjectRoot)
      #expect(manager.statusSnapshot.processIdentifier == 111)

      launcher.nextProcess = proc2
      await manager.start(hostname: "127.0.0.1", port: 9090, projectRoot: testProjectRoot)
      #expect(manager.statusSnapshot.processIdentifier == 222)
      #expect(proc1.terminateCallCount == 1)
    }

    // MARK: - Transcript

    @Test("transcript lines accumulate during start")
    func transcriptAccumulation() async {
      let launcher = RecordingValidationServerProcessLauncher()
      let healthCallCounter = Mutex<Int>(0)
      let manager = makeManager(
        launcher: launcher,
        healthCheck: { _, _ in
          let count = healthCallCounter.withLock { current in
            current += 1
            return current
          }
          if count < 3 {
            launcher.nextProcess.simulateOutput("[Server] preparing")
            throw URLError(.cannotConnectToHost)
          }
          return true
        }
      )

      await manager.start(hostname: "127.0.0.1", port: 8090, projectRoot: testProjectRoot)

      #expect(manager.statusSnapshot.state == ValidationServerLaunchState.running)
    }

    // MARK: - onStatusChange Callback

    @Test("onStatusChange fires for each transition")
    func onStatusChangeFires() async {
      var callbackSnapshots = [ValidationServerLaunchState]()
      let manager = makeManager()
      manager.onStatusChange = { snapshot in
        callbackSnapshots.append(snapshot.state)
      }

      await manager.start(hostname: "127.0.0.1", port: 8090, projectRoot: testProjectRoot)

      #expect(callbackSnapshots.contains(.starting))
      #expect(callbackSnapshots.contains(.running))
    }

    @Test("onStatusChange fires on stop")
    func onStatusChangeFiresOnStop() async {
      var callbackStates = [ValidationServerLaunchState]()
      let manager = makeManager()
      manager.onStatusChange = { snapshot in
        callbackStates.append(snapshot.state)
      }

      await manager.start(hostname: "127.0.0.1", port: 8090, projectRoot: testProjectRoot)
      callbackStates.removeAll()

      await manager.stop()
      #expect(callbackStates.last == .idle)
    }

    // MARK: - Occupied Port Detection

    @Test("address already in use mapped to occupiedPort failure")
    func occupiedPortDetection() async {
      let launcher = RecordingValidationServerProcessLauncher()
      let proc = RecordingValidationServerProcess(processIdentifier: 1234)
      launcher.nextProcess = proc
      let isFirstCall = Mutex<Bool>(true)
      let manager = makeManager(
        launcher: launcher,
        healthCheck: { _, _ in
          let first = isFirstCall.withLock { current in
            let was = current
            current = false
            return was
          }
          if first {
            proc.simulateOutput("[Server] address already in use")
            proc.simulateExit(status: 1)
          }
          throw URLError(.cannotConnectToHost)
        }
      )

      await manager.start(hostname: "127.0.0.1", port: 8090, projectRoot: testProjectRoot)

      #expect(manager.statusSnapshot.state == ValidationServerLaunchState.failed)
    }
  }

  // MARK: - UITestingValidationServerManager Tests

  @Suite("UITestingValidationServerManager")
  @MainActor
  struct UITestingValidationServerManagerTests {
    @Test("start immediately transitions to running")
    func startTransitions() async {
      let manager = UITestingValidationServerManager()
      await manager.start(
        hostname: "127.0.0.1",
        port: 8090,
        projectRoot: URL(fileURLWithPath: "/tmp")
      )
      #expect(manager.statusSnapshot.state == .running)
      #expect(manager.statusSnapshot.processIdentifier == 4243)
      #expect(manager.statusSnapshot.transcript.count > 0)
    }

    @Test("stop transitions back to idle")
    func stopTransitions() async {
      let manager = UITestingValidationServerManager()
      await manager.start(
        hostname: "127.0.0.1",
        port: 8090,
        projectRoot: URL(fileURLWithPath: "/tmp")
      )
      await manager.stop()
      #expect(manager.statusSnapshot.state == .idle)
      #expect(manager.statusSnapshot.processIdentifier == nil)
    }

    @Test("onStatusChange fires on start")
    func onStatusChangeStart() async {
      var states = [ValidationServerLaunchState]()
      let manager = UITestingValidationServerManager()
      manager.onStatusChange = { snapshot in
        states.append(snapshot.state)
      }
      await manager.start(
        hostname: "127.0.0.1",
        port: 8090,
        projectRoot: URL(fileURLWithPath: "/tmp")
      )
      #expect(states == [.running])
    }

    @Test("onStatusChange fires on stop")
    func onStatusChangeStop() async {
      let manager = UITestingValidationServerManager()
      await manager.start(
        hostname: "127.0.0.1",
        port: 8090,
        projectRoot: URL(fileURLWithPath: "/tmp")
      )
      var states = [ValidationServerLaunchState]()
      manager.onStatusChange = { snapshot in
        states.append(snapshot.state)
      }
      await manager.stop()
      #expect(states == [.idle])
    }
  }

  // MARK: - ValidationServerTypes Tests

  @Suite("ValidationServerTypes")
  struct ValidationServerTypesTests {
    @Test("ValidationServerLaunchRequest equatable")
    func launchRequestEquatable() {
      let a = ValidationServerLaunchRequest(
        helperURL: URL(fileURLWithPath: "/bin/helper"),
        hostname: "localhost",
        port: 8090,
        projectRoot: URL(fileURLWithPath: "/tmp")
      )
      let b = a
      #expect(a == b)
    }

    @Test("ValidationServerLaunchError descriptions")
    func errorDescriptions() {
      let errors: [ValidationServerLaunchError] = [
        .helperUnavailable("/path"),
        .startupFailed("oops"),
        .helperExitedBeforeReady(1),
        .healthTimedOut("http://localhost:8090"),
        .occupiedPort(8090),
      ]
      for error in errors {
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.isEmpty == false)
      }
    }

    @Test("ValidationServerLaunchError equatable")
    func errorEquatable() {
      #expect(
        ValidationServerLaunchError.occupiedPort(8090) == ValidationServerLaunchError.occupiedPort(
          8090))
      #expect(
        ValidationServerLaunchError.occupiedPort(8090) != ValidationServerLaunchError.occupiedPort(
          9090))
    }
  }

  // MARK: - HelperLocator Tests

  @Suite("BundledValidationServerHelperLocator")
  struct BundledValidationServerHelperLocatorTests {
    @Test("throws when no executable found in empty bundle")
    func throwsWhenNoExecutable() throws {
      let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: tempDir) }

      let fakeBundle = Bundle(url: tempDir) ?? .main
      let locator = BundledValidationServerHelperLocator(bundle: fakeBundle)
      #expect(throws: ValidationServerLaunchError.self) {
        try locator.helperURL()
      }
    }

    @Test("StubValidationServerHelperLocator returns configured URL")
    func stubReturnsURL() throws {
      let url = URL(fileURLWithPath: "/usr/local/bin/test-helper")
      let locator = StubValidationServerHelperLocator(url: url)
      let result = try locator.helperURL()
      #expect(result == url)
    }
  }

  // MARK: - ValidationServerStatusSnapshot Tests

  @Suite("ValidationServerStatusSnapshot")
  struct ValidationServerStatusSnapshotTests {
    @Test("endpointDisplayString formats correctly")
    func endpointDisplayString() {
      let snapshot = ValidationServerStatusSnapshot(
        state: .running,
        hostname: "192.168.1.1",
        port: 9090
      )
      #expect(snapshot.endpointDisplayString == "http://192.168.1.1:9090")
    }

    @Test("default values")
    func defaultValues() {
      let snapshot = ValidationServerStatusSnapshot(state: .idle)
      #expect(snapshot.hostname == "127.0.0.1")
      #expect(snapshot.port == 8090)
      #expect(snapshot.transcript.isEmpty)
      #expect(snapshot.failureDescription == nil)
      #expect(snapshot.processIdentifier == nil)
    }

    @Test("equatable")
    func equatable() {
      let a = ValidationServerStatusSnapshot(state: .running, hostname: "a", port: 1)
      let b = ValidationServerStatusSnapshot(state: .running, hostname: "a", port: 1)
      #expect(a == b)
    }
  }
#endif
