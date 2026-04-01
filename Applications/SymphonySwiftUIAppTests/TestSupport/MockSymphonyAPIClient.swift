import Foundation
import SymphonyShared

@testable import SymphonySwiftUIApp

final class MockSymphonyAPIClient: SymphonyAPIClientProtocol, @unchecked Sendable {
  var healthResponse: HealthResponse
  var issuesResponse: IssuesResponse
  var issueDetailResponse: IssueDetail
  var issueProgressReportResponse: IssueProgressReportResponse
  var runDetailResponse: RunDetail
  var logsResponse: LogEntriesResponse
  var liveEvents = [AgentRawEvent]()
  var healthError: Error?
  var issuesError: Error?
  var issueDetailError: Error?
  var runDetailError: Error?
  var logsError: Error?
  var refreshError: Error?
  var streamError: Error?
  var suspendStream = false
  var suspendRefresh = false
  var suspendIssueProgressReport = false

  private(set) var recordedHosts = [String]()
  private(set) var refreshCallCount = 0
  private(set) var issueDetailRequests = [IssueID]()
  private(set) var issueProgressReportRequests = [IssueID]()
  private(set) var runDetailRequests = [RunID]()
  private(set) var logRequests = [(sessionID: SessionID, cursor: EventCursor?, limit: Int)]()
  private(set) var streamRequests = [(sessionID: SessionID, cursor: EventCursor?)]()
  private(set) var streamStartCount = 0
  private(set) var streamTerminationCount = 0
  private var refreshContinuation: CheckedContinuation<Void, Never>?
  private var issueProgressReportContinuation: CheckedContinuation<Void, Never>?
  let issueProgressReportRequestStream = IssueProgressReportRequestStream()

  init() {
    self.healthResponse = HealthResponse(status: "ok", serverTime: "", version: "", trackerKind: "")
    self.issuesResponse = IssuesResponse(items: [])
    let issue = SymphonyShared.Issue(
      id: IssueID("issue-0"),
      identifier: try! IssueIdentifier(validating: "atjsh/example#1"),
      repository: "atjsh/example",
      number: 1,
      title: "",
      description: nil,
      priority: nil,
      state: "queued",
      issueState: "OPEN",
      projectItemID: nil,
      url: nil,
      labels: [],
      blockedBy: [],
      createdAt: nil,
      updatedAt: nil
    )
    self.issueDetailResponse = IssueDetail(
      issue: issue, latestRun: nil, workspacePath: nil, recentSessions: [])
    self.issueProgressReportResponse = makeIssueProgressReport(issueID: IssueID("issue-0"))
    self.runDetailResponse = RunDetail(
      runID: RunID("run-0"),
      issueID: IssueID("issue-0"),
      issueIdentifier: try! IssueIdentifier(validating: "atjsh/example#1"),
      attempt: 1,
      status: "queued",
      provider: "claude_code",
      providerSessionID: nil,
      providerRunID: nil,
      startedAt: "2026-03-24T00:00:00Z",
      endedAt: nil,
      workspacePath: "/tmp",
      sessionID: nil,
      lastError: nil,
      issue: issue,
      turnCount: 0,
      lastAgentEventType: nil,
      lastAgentMessage: nil,
      tokens: try! TokenUsage(),
      logs: RunLogStats(eventCount: 0, latestSequence: nil)
    )
    self.logsResponse = LogEntriesResponse(
      sessionID: SessionID("session-0"), provider: "claude_code", items: [], nextCursor: nil,
      hasMore: false)
  }

  func health(endpoint: ServerEndpoint) async throws -> HealthResponse {
    if let healthError {
      throw healthError
    }
    recordedHosts.append(endpoint.host)
    return healthResponse
  }

  func issues(endpoint: ServerEndpoint) async throws -> IssuesResponse {
    if let issuesError {
      throw issuesError
    }
    recordedHosts.append(endpoint.host)
    return issuesResponse
  }

  func issueDetail(endpoint: ServerEndpoint, issueID: IssueID) async throws -> IssueDetail {
    if let issueDetailError {
      throw issueDetailError
    }
    issueDetailRequests.append(issueID)
    return issueDetailResponse
  }

  func issueProgressReport(endpoint: ServerEndpoint, issueID: IssueID) async throws
    -> IssueProgressReportResponse
  {
    if let issueDetailError {
      throw issueDetailError
    }
    issueProgressReportRequests.append(issueID)
    await issueProgressReportRequestStream.yield(issueID)
    if suspendIssueProgressReport {
      await withCheckedContinuation { continuation in
        issueProgressReportContinuation = continuation
      }
    }
    if issueProgressReportResponse.issueID == issueID {
      return issueProgressReportResponse
    }
    return IssueProgressReportResponse(
      issueID: issueID,
      generatedAt: issueProgressReportResponse.generatedAt,
      report: issueProgressReportResponse.report,
      syntaxHealth: issueProgressReportResponse.syntaxHealth
    )
  }

  func runDetail(endpoint: ServerEndpoint, runID: RunID) async throws -> RunDetail {
    if let runDetailError {
      throw runDetailError
    }
    runDetailRequests.append(runID)
    return runDetailResponse
  }

  func logs(endpoint: ServerEndpoint, sessionID: SessionID, cursor: EventCursor?, limit: Int)
    async throws -> LogEntriesResponse
  {
    if let logsError {
      throw logsError
    }
    logRequests.append((sessionID, cursor, limit))
    return logsResponse
  }

  func refresh(endpoint: ServerEndpoint) async throws -> RefreshResponse {
    if let refreshError {
      throw refreshError
    }
    refreshCallCount += 1
    if suspendRefresh {
      await withCheckedContinuation { continuation in
        refreshContinuation = continuation
      }
    }
    return RefreshResponse(queued: true, requestedAt: "2026-03-24T12:00:00Z")
  }

  func resumeRefresh() {
    refreshContinuation?.resume()
    refreshContinuation = nil
  }

  func resumeIssueProgressReport() {
    issueProgressReportContinuation?.resume()
    issueProgressReportContinuation = nil
  }

  func nextIssueProgressReportRequest() async -> IssueID? {
    await issueProgressReportRequestStream.next()
  }

  func logStream(endpoint: ServerEndpoint, sessionID: SessionID, cursor: EventCursor?) throws
    -> AsyncThrowingStream<AgentRawEvent, Error>
  {
    streamRequests.append((sessionID, cursor))
    streamStartCount += 1
    return AsyncThrowingStream(AgentRawEvent.self) { continuation in
      continuation.onTermination = { [weak self] _ in
        self?.streamTerminationCount += 1
      }
      if let streamError {
        continuation.finish(throwing: streamError)
        return
      }
      if suspendStream {
        return
      }
      for event in liveEvents {
        continuation.yield(event)
      }
      continuation.finish()
    }
  }
}

actor IssueProgressReportRequestStream {
  private var bufferedIssueIDs = [IssueID]()
  private var pendingContinuations = [CheckedContinuation<IssueID?, Never>]()

  func yield(_ issueID: IssueID) {
    if pendingContinuations.isEmpty {
      bufferedIssueIDs.append(issueID)
      return
    }

    let continuation = pendingContinuations.removeFirst()
    continuation.resume(returning: issueID)
  }

  func next() async -> IssueID? {
    if bufferedIssueIDs.isEmpty == false {
      return bufferedIssueIDs.removeFirst()
    }

    return await withCheckedContinuation { continuation in
      pendingContinuations.append(continuation)
    }
  }
}

enum TestModelFailure: LocalizedError {
  case failed(String)

  var errorDescription: String? {
    switch self {
    case .failed(let message):
      return message
    }
  }
}
