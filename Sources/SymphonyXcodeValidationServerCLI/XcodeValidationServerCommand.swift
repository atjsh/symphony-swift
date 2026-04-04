#if os(macOS)

import ArgumentParser
import Foundation
import SymphonyXcodeValidationServer

public struct XcodeValidationServerCommand: AsyncParsableCommand {
  public static let configuration = CommandConfiguration(
    commandName: "xcode-validation-server",
    abstract: "Run a local HTTP server exposing the Xcode validation runner."
  )

  @Option(name: .long, help: "Hostname to bind to.")
  public var hostname: String = "127.0.0.1"

  @Option(name: .long, help: "Port to listen on.")
  public var port: Int = 8090

  @Option(name: .long, help: "Path to the Xcode project root.")
  public var projectRoot: String = FileManager.default.currentDirectoryPath

  public init() {}

  public func run() async throws {
    let root = URL(fileURLWithPath: projectRoot)
    let server = XcodeValidationServer(
      hostname: hostname,
      port: port,
      projectRoot: root
    )
    try await server.run()
  }
}

#endif
