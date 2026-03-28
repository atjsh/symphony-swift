import Foundation
import SymphonyShared

public enum OperatorDetailTab: String, CaseIterable, Sendable {
  case overview
  case sessions
  case logs

  var title: String {
    switch self {
    case .overview:
      "Overview"
    case .sessions:
      "Sessions"
    case .logs:
      "Logs"
    }
  }

  var systemImage: String {
    switch self {
    case .overview:
      "doc.text.magnifyingglass"
    case .sessions:
      "person.2"
    case .logs:
      "text.alignleft"
    }
  }
}

public enum OperatorLogFilter: String, CaseIterable, Sendable {
  case all
  case messages
  case tools
  case alerts

  var title: String {
    switch self {
    case .all:
      "All"
    case .messages:
      "Messages"
    case .tools:
      "Tools"
    case .alerts:
      "Alerts"
    }
  }

  var systemImage: String {
    switch self {
    case .all:
      "line.3.horizontal.decrease.circle"
    case .messages:
      "text.bubble"
    case .tools:
      "hammer"
    case .alerts:
      "exclamationmark.triangle"
    }
  }

  func matches(_ event: AgentRawEvent) -> Bool {
    switch self {
    case .all:
      true
    case .messages:
      event.normalizedKind == .message
    case .tools:
      event.normalizedKind == .toolCall || event.normalizedKind == .toolResult
    case .alerts:
      event.normalizedKind == .approvalRequest || event.normalizedKind == .error
    }
  }
}
