#if os(macOS)
  import Foundation
  import Testing

  @testable import SymphonySwiftUIApp

  private final class StubProcessController: LocalServerProcessControlling, @unchecked Sendable {
    let processIdentifier: Int32
    private(set) var terminated = false

    init(pid: Int32 = 42) {
      self.processIdentifier = pid
    }

    func terminate() {
      terminated = true
    }
  }

  private final class StubProcessLauncher: LocalServerProcessLaunching, @unchecked Sendable {
    var controller: StubProcessController?
    var launchError: Error?
    private(set) var launchCount = 0
    var onLaunch: ((@escaping @Sendable (String) -> Void, @escaping @Sendable (Int32) -> Void) -> Void)?

    func launch(
      request _: LocalServerLaunchRequest,
      onOutput: @escaping @Sendable (String) -> Void,
      onExit: @escaping @Sendable (Int32) -> Void
    ) throws -> any LocalServerProcessControlling {
      launchCount += 1
      if let launchError { throw launchError }
      onLaunch?(onOutput, onExit)
      return controller ?? StubProcessController()
    }
  }

  private func makeLaunchRequest(
    port: Int = 8080,
    host: String = "localhost"
  ) -> LocalServerLaunchRequest {
    LocalServerLaunchRequest(
      helperURL: URL(fileURLWithPath: "/tmp/SymphonyLocalServerHelper"),
      workflowURL: URL(fileURLWithPath: "/tmp/WORKFLOW.md"),
      currentDirectoryURL: URL(fileURLWithPath: "/tmp"),
      endpoint: BootstrapServerEndpoint(scheme: "http", host: host, port: port),
      environment: [:]
    )
  }

  @MainActor
  @Suite("DefaultLocalServerManager", .tags(.model, .localServer))
  struct DefaultLocalServerManagerTests {
    @Test func startTransitionsToRunningOnHealthSuccess() async {
      let launcher = StubProcessLauncher()
      launcher.controller = StubProcessController(pid: 77)
      nonisolated(unsafe) var healthCallCount = 0
      let manager = DefaultLocalServerManager(
        processLauncher: launcher,
        healthCheck: { _ in healthCallCount += 1 }
      )

      await manager.start(request: makeLaunchRequest())

      #expect(manager.statusSnapshot.state == .running)
      #expect(manager.statusSnapshot.processIdentifier == 77)
      #expect(healthCallCount > 0)
      #expect(launcher.launchCount == 1)
    }

    @Test func startReportsFailureWhenHealthTimesOut() async {
      let launcher = StubProcessLauncher()
      launcher.controller = StubProcessController(pid: 10)
      let fastClock = ContinuousClock()
      let manager = DefaultLocalServerManager(
        processLauncher: launcher,
        healthCheck: { _ in throw TestModelFailure.failed("unhealthy") },
        clock: fastClock
      )

      await manager.start(request: makeLaunchRequest())

      #expect(manager.statusSnapshot.state == .failed)
      #expect(manager.statusSnapshot.failureDescription != nil)
    }

    @Test func startReportsOccupiedPortFromTranscript() async {
      let launcher = StubProcessLauncher()
      launcher.controller = StubProcessController(pid: 11)
      launcher.onLaunch = { onOutput, _ in
        onOutput("[SymphonyServer] failed to start: Address already in use")
      }
      let manager = DefaultLocalServerManager(
        processLauncher: launcher,
        healthCheck: { _ in throw TestModelFailure.failed("unhealthy") }
      )

      await manager.start(request: makeLaunchRequest(port: 9090))

      #expect(manager.statusSnapshot.state == .failed)
      #expect(manager.statusSnapshot.failureDescription?.contains("9090") == true)
    }

    @Test func startMapFailedToStartTranscriptLine() async {
      let launcher = StubProcessLauncher()
      launcher.controller = StubProcessController(pid: 12)
      launcher.onLaunch = { onOutput, _ in
        onOutput("[SymphonyServer] failed to start: missing config")
      }
      let manager = DefaultLocalServerManager(
        processLauncher: launcher,
        healthCheck: { _ in throw TestModelFailure.failed("unhealthy") }
      )

      await manager.start(request: makeLaunchRequest())

      #expect(manager.statusSnapshot.state == .failed)
      #expect(
        manager.statusSnapshot.failureDescription?.contains("failed to start: missing config")
          == true
      )
    }

    @Test func startReportsLaunchError() async {
      let launcher = StubProcessLauncher()
      launcher.launchError = LocalServerLaunchError.helperUnavailable("/missing")
      let manager = DefaultLocalServerManager(processLauncher: launcher)

      await manager.start(request: makeLaunchRequest())

      #expect(manager.statusSnapshot.state == .failed)
      #expect(manager.statusSnapshot.failureDescription?.contains("/missing") == true)
    }

    @Test func stopTerminatesProcessAndResetsToIdle() async {
      let controller = StubProcessController(pid: 55)
      let launcher = StubProcessLauncher()
      launcher.controller = controller
      let manager = DefaultLocalServerManager(
        processLauncher: launcher,
        healthCheck: { _ in }
      )

      await manager.start(request: makeLaunchRequest())
      #expect(manager.statusSnapshot.state == .running)

      await manager.stop()

      #expect(manager.statusSnapshot.state == .idle)
      #expect(manager.statusSnapshot.processIdentifier == nil)
      #expect(controller.terminated)
    }

    @Test func stopWithoutProcessResetsToIdle() async {
      let manager = DefaultLocalServerManager(
        processLauncher: StubProcessLauncher(),
        healthCheck: { _ in }
      )

      await manager.stop()

      #expect(manager.statusSnapshot.state == .idle)
    }

    @Test func restartStopsThenStarts() async {
      let launcher = StubProcessLauncher()
      launcher.controller = StubProcessController(pid: 66)
      let manager = DefaultLocalServerManager(
        processLauncher: launcher,
        healthCheck: { _ in }
      )

      await manager.restart(request: makeLaunchRequest())

      #expect(manager.statusSnapshot.state == .running)
      #expect(launcher.launchCount == 1)
    }

    @Test func onStatusChangeCallbackFires() async {
      let launcher = StubProcessLauncher()
      launcher.controller = StubProcessController(pid: 88)
      let manager = DefaultLocalServerManager(
        processLauncher: launcher,
        healthCheck: { _ in }
      )
      var capturedStates = [LocalServerLaunchState]()
      manager.onStatusChange = { snapshot in
        capturedStates.append(snapshot.state)
      }

      await manager.start(request: makeLaunchRequest())

      #expect(capturedStates.contains(.starting))
      #expect(capturedStates.contains(.running))
    }

    @Test func processExitBeforeHealthReportsFailure() async {
      let launcher = StubProcessLauncher()
      let controller = StubProcessController(pid: 13)
      launcher.controller = controller
      nonisolated(unsafe) var healthAttempt = 0
      launcher.onLaunch = { _, onExit in
        onExit(1)
      }
      let manager = DefaultLocalServerManager(
        processLauncher: launcher,
        healthCheck: { _ in
          healthAttempt += 1
          throw TestModelFailure.failed("unhealthy")
        }
      )

      await manager.start(request: makeLaunchRequest())

      #expect(manager.statusSnapshot.state == .failed)
    }

    @Test func transcriptLinesAccumulate() async throws {
      let launcher = StubProcessLauncher()
      launcher.controller = StubProcessController(pid: 14)
      launcher.onLaunch = { onOutput, _ in
        onOutput("[SymphonyServer] starting")
        onOutput("[SymphonyServer] ready")
      }
      let manager = DefaultLocalServerManager(
        processLauncher: launcher,
        healthCheck: { _ in }
      )

      await manager.start(request: makeLaunchRequest())

      try await waitUntil { manager.statusSnapshot.transcript.contains("[SymphonyServer] ready") }
      #expect(manager.statusSnapshot.transcript.contains("[SymphonyServer] starting"))
      #expect(manager.statusSnapshot.transcript.contains("[SymphonyServer] ready"))
    }
  }

  @MainActor
  @Suite("UITestingLocalServerManager", .tags(.model, .localServer))
  struct UITestingLocalServerManagerTests {
    @Test func startTransitionsToRunning() async {
      let manager = UITestingLocalServerManager()
      let request = makeLaunchRequest()

      await manager.start(request: request)

      #expect(manager.statusSnapshot.state == .running)
      #expect(manager.statusSnapshot.processIdentifier == 4242)
      #expect(manager.statusSnapshot.transcript.count == 2)
    }

    @Test func stopTransitionsToIdle() async {
      let manager = UITestingLocalServerManager()
      await manager.start(request: makeLaunchRequest())

      await manager.stop()

      #expect(manager.statusSnapshot.state == .idle)
      #expect(manager.statusSnapshot.processIdentifier == nil)
    }

    @Test func restartDelegatesToStart() async {
      let manager = UITestingLocalServerManager()

      await manager.restart(request: makeLaunchRequest())

      #expect(manager.statusSnapshot.state == .running)
    }
  }
#endif
