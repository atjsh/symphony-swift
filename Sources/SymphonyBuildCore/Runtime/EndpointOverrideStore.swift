import Foundation
import SymphonyShared

public struct EndpointOverrideStore {
  private let fileManager: FileManager

  public init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  public func load(in workspace: WorkspaceContext) throws -> RuntimeEndpoint? {
    let path = storeURL(in: workspace)
    guard fileManager.fileExists(atPath: path.path) else {
      return nil
    }

    let data = try Data(contentsOf: path)
    return try JSONDecoder().decode(RuntimeEndpoint.self, from: data)
  }

  public func save(_ endpoint: RuntimeEndpoint, in workspace: WorkspaceContext) throws -> URL {
    let path = storeURL(in: workspace)
    try fileManager.createDirectory(
      at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(endpoint).write(to: path)
    return path
  }

  public func clear(in workspace: WorkspaceContext) throws {
    let path = storeURL(in: workspace)
    if fileManager.fileExists(atPath: path.path) {
      try fileManager.removeItem(at: path)
    }
  }

  public func resolve(
    workspace: WorkspaceContext,
    serverURL: String?,
    scheme: String? = nil,
    host: String? = nil,
    port: Int? = nil
  ) throws -> RuntimeEndpoint {
    if let serverURL {
      guard let components = URLComponents(string: serverURL),
        let resolvedScheme = components.scheme,
        let resolvedHost = components.host,
        let resolvedPort = components.port
      else {
        throw SymphonyBuildError(
          code: "invalid_server_url",
          message: "The provided server URL must include a scheme, host, and port.")
      }
      return try RuntimeEndpoint(scheme: resolvedScheme, host: resolvedHost, port: resolvedPort)
    }

    if host != nil || port != nil || scheme != nil {
      let fallback = try load(in: workspace) ?? RuntimeEndpoint()
      let resolvedScheme: String
      if let scheme {
        resolvedScheme = scheme
      } else {
        resolvedScheme = fallback.scheme
      }
      let resolvedHost: String
      if let host {
        resolvedHost = host
      } else {
        resolvedHost = fallback.host
      }
      let resolvedPort: Int
      if let port {
        resolvedPort = port
      } else {
        resolvedPort = fallback.port
      }
      return try RuntimeEndpoint(
        scheme: resolvedScheme,
        host: resolvedHost,
        port: resolvedPort
      )
    }

    return try load(in: workspace) ?? RuntimeEndpoint()
  }

  public func clientEnvironment(for endpoint: RuntimeEndpoint) -> [String: String] {
    [
      "SYMPHONY_SERVER_SCHEME": endpoint.scheme,
      "SYMPHONY_SERVER_HOST": endpoint.host,
      "SYMPHONY_SERVER_PORT": String(endpoint.port),
    ]
  }

  public func storeURL(in workspace: WorkspaceContext) -> URL {
    workspace.buildStateRoot.appendingPathComponent(
      "runtime/server-endpoint.json", isDirectory: false)
  }
}
