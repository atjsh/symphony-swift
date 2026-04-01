import Foundation

public enum SymphonySharedValidationError: Error, Equatable, Sendable {
  case invalidIssueIdentifier(String)
  case invalidServerEndpoint
  case invalidTokenUsage(expectedTotal: Int, actualTotal: Int)
}
