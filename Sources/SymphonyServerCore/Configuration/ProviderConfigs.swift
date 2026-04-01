import Foundation
import SymphonyShared

// MARK: - Agent Config (Section 6.3.6)

public struct AgentConfig: Equatable, Sendable {
  public let defaultProvider: ProviderName
  public let maxConcurrentAgents: Int
  public let maxTurns: Int
  public let maxRetryBackoffMS: Int
  public let maxConcurrentAgentsByState: [String: Int]

  public init(
    defaultProvider: ProviderName = .codex,
    maxConcurrentAgents: Int = 10,
    maxTurns: Int = 20,
    maxRetryBackoffMS: Int = 300_000,
    maxConcurrentAgentsByState: [String: Int] = [:]
  ) {
    self.defaultProvider = defaultProvider
    self.maxConcurrentAgents = maxConcurrentAgents
    self.maxTurns = maxTurns
    self.maxRetryBackoffMS = maxRetryBackoffMS
    self.maxConcurrentAgentsByState = maxConcurrentAgentsByState
  }

  public static let defaults = AgentConfig()
}

// MARK: - Provider Configs (Section 6.3.6)

public struct ProvidersConfig: Equatable, Sendable {
  public let codex: CodexProviderConfig
  public let claudeCode: ClaudeCodeProviderConfig
  public let copilotCLI: CopilotCLIProviderConfig

  public init(
    codex: CodexProviderConfig = .defaults,
    claudeCode: ClaudeCodeProviderConfig = .defaults,
    copilotCLI: CopilotCLIProviderConfig = .defaults
  ) {
    self.codex = codex
    self.claudeCode = claudeCode
    self.copilotCLI = copilotCLI
  }

  public static let defaults = ProvidersConfig()

  public func stallTimeoutMS(for provider: ProviderName) -> Int {
    switch provider {
    case .codex: return codex.stallTimeoutMS
    case .claudeCode: return claudeCode.stallTimeoutMS
    case .copilotCLI: return copilotCLI.stallTimeoutMS
    }
  }
}

public enum CodexSandboxValue: Equatable, Sendable {
  case string(String)
  case bool(Bool)
  case integer(Int)
  case double(Double)
  case array([CodexSandboxValue])
  case object([String: CodexSandboxValue])
  case null

  public var foundationValue: Any {
    switch self {
    case .string(let value):
      value
    case .bool(let value):
      value
    case .integer(let value):
      value
    case .double(let value):
      value
    case .array(let value):
      value.map(\.foundationValue)
    case .object(let value):
      value.mapValues(\.foundationValue)
    case .null:
      NSNull()
    }
  }

  public var stringValue: String? {
    guard case .string(let value) = self else { return nil }
    return value
  }
}

extension CodexSandboxValue: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) {
    self = .string(value)
  }
}

extension CodexSandboxValue: ExpressibleByBooleanLiteral {
  public init(booleanLiteral value: Bool) {
    self = .bool(value)
  }
}

extension CodexSandboxValue: ExpressibleByIntegerLiteral {
  public init(integerLiteral value: Int) {
    self = .integer(value)
  }
}

extension CodexSandboxValue: ExpressibleByFloatLiteral {
  public init(floatLiteral value: Double) {
    self = .double(value)
  }
}

extension CodexSandboxValue: ExpressibleByArrayLiteral {
  public init(arrayLiteral elements: CodexSandboxValue...) {
    self = .array(elements)
  }
}

extension CodexSandboxValue: ExpressibleByDictionaryLiteral {
  public init(dictionaryLiteral elements: (String, CodexSandboxValue)...) {
    self = .object(Dictionary(uniqueKeysWithValues: elements))
  }
}

extension CodexSandboxValue: ExpressibleByNilLiteral {
  public init(nilLiteral: ()) {
    self = .null
  }
}

public struct CodexProviderConfig: Equatable, Sendable {
  public let command: String
  public let sessionApprovalPolicy: String?
  public let sessionSandbox: CodexSandboxValue?
  public let turnApprovalPolicy: String?
  public let turnSandboxPolicy: CodexSandboxValue?
  public let turnTimeoutMS: Int
  public let readTimeoutMS: Int
  public let stallTimeoutMS: Int

  public init(
    command: String = "codex app-server",
    sessionApprovalPolicy: String? = nil,
    sessionSandbox: CodexSandboxValue? = nil,
    turnApprovalPolicy: String? = nil,
    turnSandboxPolicy: CodexSandboxValue? = nil,
    turnTimeoutMS: Int = 3_600_000,
    readTimeoutMS: Int = 5_000,
    stallTimeoutMS: Int = 300_000
  ) {
    self.command = command
    self.sessionApprovalPolicy = sessionApprovalPolicy
    self.sessionSandbox = sessionSandbox
    self.turnApprovalPolicy = turnApprovalPolicy ?? sessionApprovalPolicy
    self.turnSandboxPolicy = turnSandboxPolicy
    self.turnTimeoutMS = turnTimeoutMS
    self.readTimeoutMS = readTimeoutMS
    self.stallTimeoutMS = stallTimeoutMS
  }

  public var approvalPolicy: String? {
    sessionApprovalPolicy
  }

  public var threadSandbox: String? {
    sessionSandbox?.stringValue
  }

  public static let defaults = CodexProviderConfig()
}

public struct ClaudeCodeProviderConfig: Equatable, Sendable {
  public let command: String
  public let permissionMode: String?
  public let allowedTools: [String]
  public let disallowedTools: [String]
  public let turnTimeoutMS: Int
  public let readTimeoutMS: Int
  public let stallTimeoutMS: Int

  public init(
    command: String = "claude",
    permissionMode: String? = nil,
    allowedTools: [String] = [],
    disallowedTools: [String] = [],
    turnTimeoutMS: Int = 3_600_000,
    readTimeoutMS: Int = 5_000,
    stallTimeoutMS: Int = 300_000
  ) {
    self.command = command
    self.permissionMode = permissionMode
    self.allowedTools = allowedTools
    self.disallowedTools = disallowedTools
    self.turnTimeoutMS = turnTimeoutMS
    self.readTimeoutMS = readTimeoutMS
    self.stallTimeoutMS = stallTimeoutMS
  }

  public static let defaults = ClaudeCodeProviderConfig()
}

public struct CopilotCLIProviderConfig: Equatable, Sendable {
  public let command: String
  public let turnTimeoutMS: Int
  public let readTimeoutMS: Int
  public let stallTimeoutMS: Int

  public init(
    command: String = "copilot --acp --stdio",
    turnTimeoutMS: Int = 3_600_000,
    readTimeoutMS: Int = 5_000,
    stallTimeoutMS: Int = 300_000
  ) {
    self.command = command
    self.turnTimeoutMS = turnTimeoutMS
    self.readTimeoutMS = readTimeoutMS
    self.stallTimeoutMS = stallTimeoutMS
  }

  public static let defaults = CopilotCLIProviderConfig()
}

// MARK: - Server Config (Section 6.3.7)

public struct SymphonyServerConfig: Equatable, Sendable {
  public let host: String
  public let port: Int

  public init(host: String = "127.0.0.1", port: Int = 8080) {
    self.host = host
    self.port = port
  }

  public static let defaults = SymphonyServerConfig()
}

// MARK: - Storage Config (Section 6.3.8)

public struct StorageConfig: Equatable, Sendable {
  public let sqlitePath: String?
  public let retainRawEvents: Bool

  public init(sqlitePath: String? = nil, retainRawEvents: Bool = true) {
    self.sqlitePath = sqlitePath
    self.retainRawEvents = retainRawEvents
  }

  public static let defaults = StorageConfig()
}
