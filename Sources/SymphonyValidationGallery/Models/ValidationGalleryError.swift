import Foundation

public enum ValidationGalleryError: Error, Equatable, LocalizedError, Sendable {
  case missingRequiredFile(String)
  case malformedJSON(fileName: String, reason: String)
  case bookmarkStale(String)
  case accessDenied(String)
  case loadFailed(String)
  case exportFailed(String)

  public var errorDescription: String? {
    switch self {
    case .missingRequiredFile(let fileName):
      "The validation bundle is missing \(fileName)."
    case .malformedJSON(let fileName, let reason):
      "Could not decode \(fileName): \(reason)"
    case .bookmarkStale(let displayName):
      "The saved location for \(displayName) is stale and needs to be relinked."
    case .accessDenied(let path):
      "Access to \(path) was denied."
    case .loadFailed(let message):
      message
    case .exportFailed(let message):
      message
    }
  }
}
