#if os(macOS)
  import Foundation
  import SymphonyValidationGallery

  /// Request to launch the validation server helper process.
  struct ValidationServerLaunchRequest: Equatable, Sendable {
    var helperURL: URL
    var hostname: String
    var port: Int
    var projectRoot: URL
  }

  /// Errors specific to validation server launch lifecycle.
  enum ValidationServerLaunchError: LocalizedError, Equatable, Sendable {
    case helperUnavailable(String)
    case startupFailed(String)
    case helperExitedBeforeReady(Int32)
    case healthTimedOut(String)
    case occupiedPort(Int)

    var errorDescription: String? {
      switch self {
      case .helperUnavailable(let path):
        return "The bundled validation server helper was not found at \(path)."
      case .startupFailed(let message):
        return message
      case .helperExitedBeforeReady(let status):
        return "The validation server exited before it became ready (status \(status))."
      case .healthTimedOut(let endpoint):
        return "The validation server did not become healthy at \(endpoint) before timing out."
      case .occupiedPort(let port):
        return "Port \(port) is already in use."
      }
    }
  }
#endif
