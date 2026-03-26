import Foundation
import SwiftUI
import SymphonyShared

@MainActor
public final class SymphonyOperatorModel: ObservableObject {
  @Published public var host: String
  @Published public var portText: String
  @Published public var health: HealthResponse?
  @Published public var issues: [IssueSummary]
  @Published public var selectedIssueID: IssueID?
  @Published public var issueDetail: IssueDetail?
  @Published public var selectedRunID: RunID?
  @Published public var runDetail: RunDetail?
  @Published public var logEvents: [AgentRawEvent]
  @Published public var connectionError: String?
  @Published public var isConnecting: Bool
  @Published public var isRefreshing: Bool
  @Published public var liveStatus: String

  private let client: any SymphonyAPIClientProtocol
  private var liveLogTask: Task<Void, Never>?
  private var logCursor: EventCursor?

  public init(
    client: (any SymphonyAPIClientProtocol)? = nil,
    initialEndpoint: ServerEndpoint? = nil
  ) {
    let resolvedEndpoint = initialEndpoint ?? (try! ServerEndpoint())
    self.client = client ?? URLSessionSymphonyAPIClient()
    self.health = nil
    self.issues = []
    self.selectedIssueID = nil
    self.issueDetail = nil
    self.selectedRunID = nil
    self.runDetail = nil
    self.logEvents = []
    self.connectionError = nil
    self.isConnecting = false
    self.isRefreshing = false
    self.liveStatus = "Idle"
    self.host = resolvedEndpoint.host
    self.portText = String(resolvedEndpoint.port)
  }

  deinit {
    liveLogTask?.cancel()
  }

  public var serverEndpoint: ServerEndpoint? {
    guard let port = Int(portText) else {
      return nil
    }
    return try? ServerEndpoint(host: host, port: port)
  }

  public var visibleLogEvents: [AgentRawEvent] {
    logEvents.filter(Self.isRelevantLogEvent)
  }

  public func connect() async {
    guard let endpoint = serverEndpoint else {
      connectionError = SymphonyClientError.invalidEndpoint.localizedDescription
      return
    }

    let selectionToRestore = selectedIssueID
    connectionError = nil
    isConnecting = true
    defer { isConnecting = false }

    do {
      health = try await client.health(endpoint: endpoint)
      issues = try await client.issues(endpoint: endpoint).items
      if let selectionToRestore,
        let summary = issues.first(where: { $0.issueID == selectionToRestore })
      {
        await selectIssue(summary)
      }
    } catch {
      health = nil
      issues = []
      connectionError = error.localizedDescription
    }
  }

  public func refresh() async {
    guard let endpoint = serverEndpoint else {
      connectionError = SymphonyClientError.invalidEndpoint.localizedDescription
      return
    }

    let selectionToRestore = selectedIssueID
    isRefreshing = true
    defer { isRefreshing = false }

    do {
      _ = try await client.refresh(endpoint: endpoint)
      issues = try await client.issues(endpoint: endpoint).items
      if let summary = selectedIssueSummary(restoring: selectionToRestore, in: issues) {
        await selectIssue(summary)
      }
    } catch {
      connectionError = error.localizedDescription
    }
  }

  public func selectIssue(_ summary: IssueSummary) async {
    selectedIssueID = summary.issueID
    guard let endpoint = serverEndpoint else {
      connectionError = SymphonyClientError.invalidEndpoint.localizedDescription
      return
    }

    do {
      let detail = try await client.issueDetail(endpoint: endpoint, issueID: summary.issueID)
      issueDetail = detail
      if let latestRun = detail.latestRun {
        await selectRun(latestRun.runID)
      } else {
        selectedRunID = nil
        runDetail = nil
        clearLogs()
      }
    } catch {
      connectionError = error.localizedDescription
    }
  }

  public func selectRun(_ runID: RunID) async {
    let previousRunID = selectedRunID
    let previousSessionID = runDetail?.sessionID
    let previousCursor = logCursor
    selectedRunID = runID
    guard let endpoint = serverEndpoint else {
      connectionError = SymphonyClientError.invalidEndpoint.localizedDescription
      return
    }

    do {
      let detail = try await client.runDetail(endpoint: endpoint, runID: runID)
      runDetail = detail

      guard let sessionID = detail.sessionID else {
        clearLogs()
        liveStatus = "No session"
        return
      }

      let historicalCursor =
        previousRunID == runID && previousSessionID == sessionID ? previousCursor : nil
      let page = try await client.logs(
        endpoint: endpoint, sessionID: sessionID, cursor: historicalCursor, limit: 100)
      if historicalCursor == nil {
        logEvents = page.items
      } else {
        mergeLogEvents(page.items)
      }
      logCursor = page.nextCursor ?? historicalCursor
      startLiveStream(endpoint: endpoint, sessionID: sessionID, cursor: logCursor)
    } catch {
      connectionError = error.localizedDescription
    }
  }

  private func clearLogs() {
    liveLogTask?.cancel()
    liveLogTask = nil
    logCursor = nil
    logEvents = []
    liveStatus = "Idle"
  }

  private func startLiveStream(endpoint: ServerEndpoint, sessionID: SessionID, cursor: EventCursor?)
  {
    liveLogTask?.cancel()
    liveStatus = "Connecting live stream"
    let client = self.client

    liveLogTask = Task { @MainActor [weak self, client] in
      do {
        let stream = try client.logStream(endpoint: endpoint, sessionID: sessionID, cursor: cursor)
        self?.setLiveStatus("Live")

        for try await event in stream {
          self?.appendLogEvent(event)
        }

        self?.setLiveStatus("Ended")
      } catch is CancellationError {
      } catch {
        self?.setLiveStatus(error.localizedDescription)
      }
    }
  }

  func testingAppendLogEvent(_ event: AgentRawEvent) {
    appendLogEvent(event)
  }

  func testingMergeLogEvents(_ events: [AgentRawEvent]) {
    mergeLogEvents(events)
  }

  var testingLogCursor: EventCursor? {
    logCursor
  }

  func testingSelectedIssueSummary(
    restoring selectionToRestore: IssueID?,
    in issues: [IssueSummary]
  ) -> IssueSummary? {
    selectedIssueSummary(restoring: selectionToRestore, in: issues)
  }

  private func selectedIssueSummary(
    restoring selectionToRestore: IssueID?,
    in issues: [IssueSummary]
  ) -> IssueSummary? {
    guard let selectionToRestore else {
      return nil
    }

    for summary in issues where summary.issueID == selectionToRestore {
      return summary
    }
    return nil
  }

  private func setLiveStatus(_ status: String) {
    liveStatus = status
  }

  private func appendLogEvent(_ event: AgentRawEvent) {
    mergeLogEvents([event])
    logCursor = EventCursor(sessionID: event.sessionID, lastDeliveredSequence: event.sequence)
  }

  private func mergeLogEvents(_ events: [AgentRawEvent]) {
    for event in events where !logEvents.contains(where: { $0.sequence == event.sequence }) {
      logEvents.append(event)
    }
    logEvents.sort { $0.sequence < $1.sequence }
  }

  private static func isRelevantLogEvent(_ event: AgentRawEvent) -> Bool {
    switch event.normalizedKind {
    case .message:
      if event.providerEventType.hasSuffix("/delta") {
        return false
      }
      return !SymphonyEventPresentation.isEmptyAgentMessageShell(event: event)
    case .toolCall, .toolResult, .approvalRequest, .error:
      return true
    case .status:
      return event.providerEventType != "skills/changed"
    case .usage, .unknown:
      return false
    }
  }
}

public struct SymphonyEventPresentation: Equatable {
  public enum RowStyle: Equatable {
    case message
    case tool
    case compact
    case callout
    case supplemental
  }

  public let rowStyle: RowStyle
  public let title: String
  public let detail: String
  public let metadata: String
  public let showsRawJSON: Bool

  public init(event: AgentRawEvent) {
    self.metadata = "\(event.provider) • #\(event.sequence.rawValue) • \(event.providerEventType)"

    switch event.normalizedKind {
    case .message:
      self.rowStyle = .message
      self.title = "Message"
      self.detail = Self.extractDisplayText(from: event) ?? event.providerEventType
      self.showsRawJSON = false
    case .toolCall:
      self.rowStyle = .tool
      self.title = "Tool Call"
      self.detail = Self.extractDisplayText(from: event) ?? event.providerEventType
      self.showsRawJSON = false
    case .toolResult:
      self.rowStyle = .tool
      self.title = "Tool Result"
      self.detail = Self.extractDisplayText(from: event) ?? event.providerEventType
      self.showsRawJSON = false
    case .status:
      self.rowStyle = .compact
      self.title = "Status"
      self.detail = Self.extractDisplayText(from: event) ?? event.providerEventType
      self.showsRawJSON = false
    case .usage:
      self.rowStyle = .compact
      self.title = "Usage"
      self.detail = Self.extractDisplayText(from: event) ?? event.rawJSON
      self.showsRawJSON = false
    case .approvalRequest:
      self.rowStyle = .callout
      self.title = "Approval Request"
      self.detail = Self.extractDisplayText(from: event) ?? event.rawJSON
      self.showsRawJSON = false
    case .error:
      self.rowStyle = .callout
      self.title = "Error"
      self.detail = Self.extractDisplayText(from: event) ?? event.rawJSON
      self.showsRawJSON = false
    case .unknown:
      self.rowStyle = .supplemental
      self.title = "Unknown Event"
      if let detail = Self.extractDisplayText(from: event) {
        self.detail = detail
      } else {
        self.detail = event.rawJSON
      }
      self.showsRawJSON = true
    }
  }

  static func isEmptyAgentMessageShell(event: AgentRawEvent) -> Bool {
    guard event.providerEventType == "item/started",
      let data = event.rawJSON.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data),
      let root = object as? [String: Any],
      let params = root["params"] as? [String: Any],
      let item = params["item"] as? [String: Any],
      (item["type"] as? String) == "agentMessage"
    else {
      return false
    }

    if let text = normalizedString(item["text"]), !text.isEmpty {
      return false
    }

    return true
  }

  private static func extractDisplayText(from event: AgentRawEvent) -> String? {
    extractText(from: event.rawJSON)
  }

  private static func extractText(from rawJSON: String) -> String? {
    guard let data = rawJSON.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data)
    else {
      return nil
    }
    return extractText(from: object)
  }

  private static func extractText(from object: Any) -> String? {
    if let text = normalizedString(object), !text.isEmpty {
      return text
    }
    if let dictionary = object as? [String: Any] {
      if let method = dictionary["method"] as? String,
        let params = dictionary["params"] as? [String: Any],
        let extracted = extractText(method: method, params: params)
      {
        return extracted
      }

      for key in preferredDisplayKeys {
        if let value = dictionary[key], let extracted = extractText(from: value) {
          return extracted
        }
      }

      for (key, value) in dictionary where !ignoredMetadataKeys.contains(key) {
        if let extracted = extractText(from: value) {
          return extracted
        }
      }
    }
    if let array = object as? [Any] {
      let extractedParts = array.compactMap(extractText(from:)).filter { !$0.isEmpty }
      if !extractedParts.isEmpty {
        return extractedParts.joined(separator: "\n")
      }
    }
    if let number = object as? NSNumber {
      return number.stringValue
    }
    return nil
  }

  static func extractText(method: String, params: [String: Any]) -> String? {
    switch method {
    case "item/agentMessage/delta":
      return extractText(from: params["delta"] as Any)
    case "item/commandExecution/requestApproval":
      return extractText(from: params["reason"] as Any)
    case "thread/status/changed":
      return extractText(from: params["status"] as Any)
    case "thread/started":
      if let thread = extractText(from: params["thread"] as Any) {
        return thread
      }
      return extractText(from: params["status"] as Any)
    case "turn/started":
      if let turn = extractText(from: params["turn"] as Any) {
        return turn
      }
      return extractText(from: params["status"] as Any)
    case "item/started", "item/completed":
      if let item = params["item"] as? [String: Any] {
        if let extracted = extractText(fromItem: item) {
          return extracted
        }
      }
      if let message = params["message"] {
        return extractText(from: message)
      }
      return nil
    default:
      return extractText(from: params as Any)
    }
  }

  static func extractText(fromItem item: [String: Any]) -> String? {
    let itemType = normalizedString(item["type"])

    switch itemType {
    case "agentMessage":
      if let text = extractText(from: item["text"] as Any) {
        return text
      }
      if let content = extractText(from: item["content"] as Any) {
        return content
      }
      return extractText(from: item["summary"] as Any)
    case "commandExecution":
      if let aggregatedOutput = normalizedString(item["aggregatedOutput"]),
        aggregatedOutput.count <= 240
      {
        return aggregatedOutput
      }
      if let command = extractText(from: item["command"] as Any) {
        return command
      }
      if let arguments = extractText(from: item["arguments"] as Any) {
        return arguments
      }
      if let result = extractText(from: item["result"] as Any) {
        return result
      }
      return extractText(from: item["status"] as Any)
    case "reasoning":
      if let summary = extractText(from: item["summary"] as Any) {
        return summary
      }
      if let content = extractText(from: item["content"] as Any) {
        return content
      }
      return humanizedItemType(itemType)
    default:
      for key in preferredDisplayKeys {
        if let extracted = extractText(from: item[key] as Any) {
          return extracted
        }
      }
      return humanizedItemType(itemType)
    }
  }

  static func humanizedItemType(_ itemType: String?) -> String? {
    guard let itemType, !itemType.isEmpty else {
      return nil
    }

    switch itemType {
    case "agentMessage":
      return "Message"
    case "commandExecution":
      return "Command execution"
    case "reasoning":
      return "Reasoning"
    default:
      return itemType
    }
  }

  private static func normalizedString(_ value: Any?) -> String? {
    guard let text = value as? String else {
      return nil
    }

    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static let preferredDisplayKeys = [
    "message",
    "text",
    "delta",
    "content",
    "output",
    "result",
    "arguments",
    "reason",
    "command",
    "name",
    "status",
    "type",
  ]

  private static let ignoredMetadataKeys: Set<String> = [
    "id",
    "itemId",
    "threadId",
    "turnId",
    "sessionId",
    "providerSessionID",
    "providerRunID",
    "providerThreadID",
    "providerTurnID",
    "method",
    "phase",
    "cwd",
    "path",
    "processId",
    "memoryCitation",
  ]

  static func extractText(from object: Any?) -> String? {
    guard let object else {
      return nil
    }
    return extractText(from: object)
  }
}
