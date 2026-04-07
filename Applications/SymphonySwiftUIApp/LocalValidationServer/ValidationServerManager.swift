#if os(macOS)
  import Foundation
  import SymphonyValidationGallery
  import SymphonyXcodeValidationServerCore

  @MainActor
  final class DefaultValidationServerManager: ValidationServerLifecycleManaging, @unchecked Sendable
  {
    var onStatusChange: (@MainActor (ValidationServerStatusSnapshot) -> Void)?
    private(set) var statusSnapshot = ValidationServerStatusSnapshot(state: .idle)

    private let processLauncher: any ValidationServerProcessLaunching
    private let helperLocator: any ValidationServerHelperLocating
    private let healthCheck: @Sendable (String, Int) async throws -> Bool
    private let clock: ContinuousClock
    private var process: (any ValidationServerProcessControlling)?
    private var generation: Int = 0
    private var requestedStopGenerations = Set<Int>()

    init(
      processLauncher: (any ValidationServerProcessLaunching)? = nil,
      helperLocator: (any ValidationServerHelperLocating)? = nil,
      healthCheck: (@Sendable (String, Int) async throws -> Bool)? = nil,
      clock: ContinuousClock = ContinuousClock()
    ) {
      self.processLauncher = processLauncher ?? DefaultValidationServerProcessLauncher()
      self.helperLocator = helperLocator ?? BundledValidationServerHelperLocator()
      self.clock = clock
      if let healthCheck {
        self.healthCheck = healthCheck
      } else {
        self.healthCheck = { hostname, port in
          let url = URL(string: "http://\(hostname):\(port)/api/v1/health")!  // swiftlint:disable:this force_unwrapping
          let (_, response) = try await URLSession.shared.data(from: url)
          return (response as? HTTPURLResponse)?.statusCode == 200
        }
      }
    }

    func start(hostname: String, port: Int, projectRoot: URL) async {
      await stop()
      generation += 1
      let currentGeneration = generation

      updateStatus(
        ValidationServerStatusSnapshot(
          state: .starting,
          hostname: hostname,
          port: port,
          transcript: [],
          failureDescription: nil,
          processIdentifier: nil
        )
      )

      do {
        let helperURL = try helperLocator.helperURL()
        let request = ValidationServerLaunchRequest(
          helperURL: helperURL,
          hostname: hostname,
          port: port,
          projectRoot: projectRoot
        )

        let process = try processLauncher.launch(
          request: request,
          onOutput: { [weak self] line in
            Task { @MainActor in
              self?.appendTranscript(line, generation: currentGeneration)
            }
          },
          onExit: { [weak self] status in
            Task { @MainActor in
              self?.handleProcessExit(status: status, generation: currentGeneration)
            }
          }
        )

        self.process = process
        updateStatus(
          ValidationServerStatusSnapshot(
            state: .waitingForHealth,
            hostname: hostname,
            port: port,
            transcript: statusSnapshot.transcript,
            failureDescription: nil,
            processIdentifier: process.processIdentifier
          )
        )

        do {
          try await waitForHealth(hostname: hostname, port: port, generation: currentGeneration)
          guard currentGeneration == generation else { return }
          updateStatus(
            ValidationServerStatusSnapshot(
              state: .running,
              hostname: hostname,
              port: port,
              transcript: statusSnapshot.transcript,
              failureDescription: nil,
              processIdentifier: process.processIdentifier
            )
          )
        } catch let error as ValidationServerLaunchError {
          fail(with: error, generation: currentGeneration)
        } catch {
          fail(with: .startupFailed(error.localizedDescription), generation: currentGeneration)
        }
      } catch let error as ValidationServerLaunchError {
        fail(with: error, generation: currentGeneration)
      } catch {
        fail(with: .startupFailed(error.localizedDescription), generation: currentGeneration)
      }
    }

    func stop() async {
      guard let process else {
        updateStatus(
          ValidationServerStatusSnapshot(
            state: .idle,
            hostname: statusSnapshot.hostname,
            port: statusSnapshot.port,
            transcript: statusSnapshot.transcript,
            failureDescription: nil,
            processIdentifier: nil
          )
        )
        return
      }

      requestedStopGenerations.insert(generation)
      process.terminate()
      self.process = nil
      updateStatus(
        ValidationServerStatusSnapshot(
          state: .idle,
          hostname: statusSnapshot.hostname,
          port: statusSnapshot.port,
          transcript: statusSnapshot.transcript,
          failureDescription: nil,
          processIdentifier: nil
        )
      )
    }

    private func waitForHealth(hostname: String, port: Int, generation: Int) async throws {
      let deadline = clock.now.advanced(by: .seconds(15))
      let endpoint = "http://\(hostname):\(port)"

      while clock.now < deadline {
        if generation != self.generation {
          throw ValidationServerLaunchError.startupFailed(
            "The validation server launch was cancelled.")
        }

        do {
          _ = try await healthCheck(hostname, port)
          return
        } catch {
          if process == nil {
            throw mappedFailure(
              from: statusSnapshot.transcript,
              port: port,
              endpoint: endpoint,
              fallback: .helperExitedBeforeReady(-1)
            )
          }
        }

        try await Task.sleep(for: .milliseconds(150))
      }

      throw mappedFailure(
        from: statusSnapshot.transcript,
        port: port,
        endpoint: endpoint,
        fallback: .healthTimedOut(endpoint)
      )
    }

    private func handleProcessExit(status: Int32, generation: Int) {
      guard generation == self.generation else { return }

      process = nil
      if requestedStopGenerations.remove(generation) != nil || statusSnapshot.state == .idle {
        return
      }

      let failure = mappedFailure(
        from: statusSnapshot.transcript,
        port: statusSnapshot.port,
        endpoint: statusSnapshot.endpointDisplayString,
        fallback: .helperExitedBeforeReady(status)
      )
      fail(with: failure, generation: generation)
    }

    private func appendTranscript(_ line: String, generation: Int) {
      guard generation == self.generation else { return }
      var updated = statusSnapshot
      updated.transcript.append(line)
      updateStatus(updated)
    }

    private func fail(with error: ValidationServerLaunchError, generation: Int) {
      guard generation == self.generation else { return }
      updateStatus(
        ValidationServerStatusSnapshot(
          state: .failed,
          hostname: statusSnapshot.hostname,
          port: statusSnapshot.port,
          transcript: statusSnapshot.transcript,
          failureDescription: error.localizedDescription,
          processIdentifier: statusSnapshot.processIdentifier
        )
      )
    }

    private func updateStatus(_ status: ValidationServerStatusSnapshot) {
      statusSnapshot = status
      onStatusChange?(status)
    }

    private func mappedFailure(
      from transcript: [String],
      port: Int,
      endpoint: String,
      fallback: ValidationServerLaunchError
    ) -> ValidationServerLaunchError {
      if transcript.contains(where: {
        $0.localizedCaseInsensitiveContains("address already in use")
      }) {
        return .occupiedPort(port)
      }
      if let lastFailure = transcript.last(where: { $0.contains("failed to start:") }) {
        return .startupFailed(lastFailure)
      }
      return fallback
    }
  }

  @MainActor
  final class UITestingValidationServerManager: ValidationServerLifecycleManaging,
    @unchecked Sendable
  {
    var onStatusChange: (@MainActor (ValidationServerStatusSnapshot) -> Void)?
    private(set) var statusSnapshot = ValidationServerStatusSnapshot(state: .idle)

    func start(hostname: String, port: Int, projectRoot: URL) async {
      statusSnapshot = ValidationServerStatusSnapshot(
        state: .running,
        hostname: hostname,
        port: port,
        transcript: [
          "[ValidationServer] starting",
          "[ValidationServer] endpoint=http://\(hostname):\(port)",
          "[ValidationServer] projectRoot=\(projectRoot.path)",
        ],
        failureDescription: nil,
        processIdentifier: 4243
      )
      onStatusChange?(statusSnapshot)
    }

    func stop() async {
      statusSnapshot = ValidationServerStatusSnapshot(
        state: .idle,
        hostname: statusSnapshot.hostname,
        port: statusSnapshot.port,
        transcript: statusSnapshot.transcript,
        failureDescription: nil,
        processIdentifier: nil
      )
      onStatusChange?(statusSnapshot)
    }
  }
#endif
