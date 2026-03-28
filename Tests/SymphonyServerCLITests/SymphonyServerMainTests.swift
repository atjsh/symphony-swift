import Foundation
import Testing

@testable import SymphonyServerCLI
@testable import SymphonyServer

@Suite("SymphonyServerMain", .serialized)
struct SymphonyServerMainTests {
  @Test func mainRunsBootstrapRunnerWithExitAfterStartupPolicy() {
    var capturedEnvironment = [String: String]()
    var didInvokeKeepAlive = false
    var emittedOutput = [String]()
    var exitCode: Int32?

    SymphonyServerMain.main(
      environment: [
        BootstrapKeepAlivePolicy.exitAfterStartupKey: "1",
        "SYMPHONY_SERVER_HOST": "127.0.0.1",
      ],
      output: { emittedOutput.append($0) },
      errorOutput: { _ in },
      exit: { code in
        exitCode = code
      },
      runner: { environment, output, keepAlive, startServer in
        capturedEnvironment = environment
        output("[SymphonyServer] started")
        keepAlive()
        didInvokeKeepAlive = true
        #expect(!startServer)
      }
    )

    #expect(capturedEnvironment[BootstrapKeepAlivePolicy.exitAfterStartupKey] == "1")
    #expect(emittedOutput == ["[SymphonyServer] started"])
    #expect(didInvokeKeepAlive)
    #expect(exitCode == nil)
  }

  @Test func mainPrintsFailuresAndRequestsExitCodeOne() {
    enum StartupFailure: Error, CustomStringConvertible {
      case failed

      var description: String { "boom" }
    }

    var emittedErrors = [String]()
    var exitCode: Int32?

    SymphonyServerMain.main(
      environment: [:],
      output: { _ in },
      errorOutput: { emittedErrors.append($0) },
      exit: { code in
        exitCode = code
      },
      runner: { _, _, _, _ in
        throw StartupFailure.failed
      }
    )

    #expect(emittedErrors == ["[SymphonyServer] failed to start: boom\n"])
    #expect(exitCode == 1)
  }
}
