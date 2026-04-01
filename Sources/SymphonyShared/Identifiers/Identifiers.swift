import Foundation

public struct IssueID: Codable, Hashable, Sendable {
  public let rawValue: String

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self.init(try container.decode(String.self))
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

public struct RunID: Codable, Hashable, Sendable {
  public let rawValue: String

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self.init(try container.decode(String.self))
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

public struct SessionID: Codable, Hashable, Sendable {
  public let rawValue: String

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self.init(try container.decode(String.self))
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

public struct EventSequence: Codable, Hashable, Comparable, Sendable {
  public let rawValue: Int

  public init(_ rawValue: Int) {
    self.rawValue = rawValue
  }

  public static func < (lhs: EventSequence, rhs: EventSequence) -> Bool {
    lhs.rawValue < rhs.rawValue
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self.init(try container.decode(Int.self))
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

public struct IssueIdentifier: Codable, Hashable, Sendable, CustomStringConvertible {
  public let owner: String
  public let repository: String
  public let number: Int

  public init(owner: String, repository: String, number: Int) throws {
    guard !owner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !repository.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      number > 0
    else {
      throw SymphonySharedValidationError.invalidIssueIdentifier("\(owner)/\(repository)#\(number)")
    }

    self.owner = owner
    self.repository = repository
    self.number = number
  }

  public init(validating rawValue: String) throws {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed == rawValue else {
      throw SymphonySharedValidationError.invalidIssueIdentifier(rawValue)
    }

    let ownerAndRepository = rawValue.split(separator: "#", omittingEmptySubsequences: false)
    guard ownerAndRepository.count == 2,
      let issueNumber = Int(ownerAndRepository[1]),
      issueNumber > 0
    else {
      throw SymphonySharedValidationError.invalidIssueIdentifier(rawValue)
    }

    let repositoryComponents = ownerAndRepository[0].split(
      separator: "/", omittingEmptySubsequences: false)
    guard repositoryComponents.count == 2,
      !repositoryComponents[0].isEmpty,
      !repositoryComponents[1].isEmpty
    else {
      throw SymphonySharedValidationError.invalidIssueIdentifier(rawValue)
    }

    self.owner = String(repositoryComponents[0])
    self.repository = String(repositoryComponents[1])
    self.number = issueNumber
  }

  public var rawValue: String {
    "\(owner)/\(repository)#\(number)"
  }

  public var description: String {
    rawValue
  }

  public var workspaceKey: WorkspaceKey {
    WorkspaceKey(issueIdentifier: self)
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = try IssueIdentifier(validating: try container.decode(String.self))
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

public struct WorkspaceKey: Codable, Hashable, Sendable, CustomStringConvertible {
  public let rawValue: String

  public init(_ rawValue: String) {
    self.rawValue = WorkspaceKey.sanitized(rawValue)
  }

  public init(issueIdentifier: IssueIdentifier) {
    self.init(issueIdentifier.rawValue)
  }

  public var description: String {
    rawValue
  }

  private static func sanitized(_ rawValue: String) -> String {
    let allowed = CharacterSet(
      charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
    return String(rawValue.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self.init(try container.decode(String.self))
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}
