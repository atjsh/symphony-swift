#if os(macOS)

import Foundation
import Hummingbird
import SymphonyXcodeValidation
import SymphonyXcodeValidationServerCore

/// HTTP server that exposes the Xcode validation runner via a REST API.
public struct XcodeValidationServer: Sendable {
  private let hostname: String
  private let port: Int
  private let runManager: RunManager

  public init(
    hostname: String = "127.0.0.1",
    port: Int = 8090,
    projectRoot: URL,
    processExecutor: sending ValidationProcessExecuting = SystemValidationProcessExecutor()
  ) {
    self.hostname = hostname
    self.port = port
    self.runManager = RunManager(
      defaultProjectRoot: projectRoot,
      processExecutor: processExecutor
    )
  }

  /// Starts the HTTP server. Blocks until the server shuts down.
  public func run() async throws {
    let router = Router(context: BasicRequestContext.self)
    let routes = ValidationRoutes(runManager: runManager)
    routes.register(on: router)

    let app = Application(
      router: router,
      configuration: .init(address: .hostname(hostname, port: port))
    )

    try await app.runService(gracefulShutdownSignals: [.sigterm, .sigint])
  }
}

#endif
