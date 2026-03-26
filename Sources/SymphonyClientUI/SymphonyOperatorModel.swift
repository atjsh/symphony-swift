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
}

public struct SymphonyEventPresentation: Equatable {
  public let title: String
  public let detail: String
  public let metadata: String
  public let showsRawJSON: Bool

  public init(event: AgentRawEvent) {
    self.metadata = "\(event.provider) • #\(event.sequence.rawValue) • \(event.providerEventType)"

    switch event.normalizedKind {
    case .message:
      self.title = "Message"
      self.detail = Self.extractText(from: event.rawJSON) ?? event.providerEventType
      self.showsRawJSON = false
    case .toolCall:
      self.title = "Tool Call"
      self.detail = Self.extractText(from: event.rawJSON) ?? event.providerEventType
      self.showsRawJSON = false
    case .toolResult:
      self.title = "Tool Result"
      self.detail = Self.extractText(from: event.rawJSON) ?? event.providerEventType
      self.showsRawJSON = false
    case .status:
      self.title = "Status"
      self.detail = Self.extractText(from: event.rawJSON) ?? event.providerEventType
      self.showsRawJSON = false
    case .usage:
      self.title = "Usage"
      self.detail = Self.extractText(from: event.rawJSON) ?? event.rawJSON
      self.showsRawJSON = false
    case .approvalRequest:
      self.title = "Approval Request"
      self.detail = Self.extractText(from: event.rawJSON) ?? event.rawJSON
      self.showsRawJSON = false
    case .error:
      self.title = "Error"
      self.detail = Self.extractText(from: event.rawJSON) ?? event.rawJSON
      self.showsRawJSON = false
    case .unknown:
      self.title = "Unknown Event"
      self.detail = event.rawJSON
      self.showsRawJSON = true
    }
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
    if let text = object as? String, !text.isEmpty {
      return text
    }
    if let dictionary = object as? [String: Any] {
      for key in ["message", "text", "content", "output", "result", "arguments", "name", "type"] {
        if let value = dictionary[key], let extracted = extractText(from: value) {
          return extracted
        }
      }
      for value in dictionary.values {
        if let extracted = extractText(from: value) {
          return extracted
        }
      }
    }
    if let array = object as? [Any] {
      for value in array {
        if let extracted = extractText(from: value) {
          return extracted
        }
      }
    }
    if let number = object as? NSNumber {
      return number.stringValue
    }
    return nil
  }
}
