import Foundation

/// State of the validation server process lifecycle.
public enum ValidationServerLaunchState: String, Codable, Equatable, Sendable {
  case idle
  case starting
  case waitingForHealth
  case running
  case failed
}

/// Snapshot of the current validation server status.
public struct ValidationServerStatusSnapshot: Equatable, Sendable {
  public var state: ValidationServerLaunchState
  public var hostname: String
  public var port: Int
  public var transcript: [String]
  public var failureDescription: String?
  public var processIdentifier: Int32?

  public init(
    state: ValidationServerLaunchState,
    hostname: String = "127.0.0.1",
    port: Int = 8090,
    transcript: [String] = [],
    failureDescription: String? = nil,
    processIdentifier: Int32? = nil
  ) {
    self.state = state
    self.hostname = hostname
    self.port = port
    self.transcript = transcript
    self.failureDescription = failureDescription
    self.processIdentifier = processIdentifier
  }

  public var endpointDisplayString: String {
    "http://\(hostname):\(port)"
  }
}

/// Protocol for managing the lifecycle of a local validation server process.
@MainActor
public protocol ValidationServerLifecycleManaging: AnyObject, Sendable {
  var statusSnapshot: ValidationServerStatusSnapshot { get }
  var onStatusChange: (@MainActor (ValidationServerStatusSnapshot) -> Void)? { get set }
  func start(hostname: String, port: Int, projectRoot: URL) async
  func stop() async
}
