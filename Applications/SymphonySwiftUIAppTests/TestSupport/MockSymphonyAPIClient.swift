import Foundation
import SymphonyShared

@testable import SymphonySwiftUIApp

// SAFETY: @unchecked Sendable — all mutable recording state protected by `lock`.
// Config properties (healthResponse, issuesResponse, etc.) are set before test
// execution starts and read during; the test lifecycle ensures no concurrent writes.
final class MockSymphonyAPIClient: SymphonyAPIClientProtocol, @unchecked Sendable {
  private let lock = NSLock()

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

  private var _recordedHosts = [String]()
  private var _refreshCallCount = 0
  private var _issueDetailRequests = [IssueID]()
  private var _issueProgressReportRequests = [IssueID]()
  private var _runDetailRequests = [RunID]()
  private var _logRequests = [(sessionID: SessionID, cursor: EventCursor?, limit: Int)]()
  private var _streamRequests = [(sessionID: SessionID, cursor: EventCursor?)]()
  private var _streamStartCount = 0
  private var _streamTerminationCount = 0
  private var _refreshContinuation: CheckedContinuation<Void, Never>?
  private var _issueProgressReportContinuation: CheckedContinuation<Void, Never>?

  var recordedHosts: [String] { lock.withLock { _recordedHosts } }
  var refreshCallCount: Int { lock.withLock { _refreshCallCount } }
  var issueDetailRequests: [IssueID] { lock.withLock { _issueDetailRequests } }
  var issueProgressReportRequests: [IssueID] { lock.withLock { _issueProgressReportRequests } }
  var runDetailRequests: [RunID] { lock.withLock { _runDetailRequests } }
  var logRequests: [(sessionID: SessionID, cursor: EventCursor?, limit: Int)] {
    lock.withLock { _logRequests }
  }
  var streamRequests: [(sessionID: SessionID, cursor: EventCursor?)] {
    lock.withLock { _streamRequests }
  }
  var streamStartCount: Int { lock.withLock { _streamStartCount } }
  var streamTerminationCount: Int { lock.withLock { _streamTerminationCount } }
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
    lock.withLock { _recordedHosts.append(endpoint.host) }
    return healthResponse
  }

  func issues(endpoint: ServerEndpoint) async throws -> IssuesResponse {
    if let issuesError {
      throw issuesError
    }
    lock.withLock { _recordedHosts.append(endpoint.host) }
    return issuesResponse
  }

  func issueDetail(endpoint: ServerEndpoint, issueID: IssueID) async throws -> IssueDetail {
    if let issueDetailError {
      throw issueDetailError
    }
    lock.withLock { _issueDetailRequests.append(issueID) }
    return issueDetailResponse
  }

  func issueProgressReport(endpoint: ServerEndpoint, issueID: IssueID) async throws
    -> IssueProgressReportResponse
  {
    if let issueDetailError {
      throw issueDetailError
    }
    lock.withLock { _issueProgressReportRequests.append(issueID) }
    await issueProgressReportRequestStream.yield(issueID)
    if suspendIssueProgressReport {
      await withCheckedContinuation { continuation in
        lock.withLock { _issueProgressReportContinuation = continuation }
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
    lock.withLock { _runDetailRequests.append(runID) }
    return runDetailResponse
  }

  func logs(endpoint: ServerEndpoint, sessionID: SessionID, cursor: EventCursor?, limit: Int)
    async throws -> LogEntriesResponse
  {
    if let logsError {
      throw logsError
    }
    lock.withLock { _logRequests.append((sessionID, cursor, limit)) }
    return logsResponse
  }

  func refresh(endpoint: ServerEndpoint) async throws -> RefreshResponse {
    if let refreshError {
      throw refreshError
    }
    lock.withLock { _refreshCallCount += 1 }
    if suspendRefresh {
      await withCheckedContinuation { continuation in
        lock.withLock { _refreshContinuation = continuation }
      }
    }
    return RefreshResponse(queued: true, requestedAt: "2026-03-24T12:00:00Z")
  }

  func resumeRefresh() {
    lock.withLock {
      _refreshContinuation?.resume()
      _refreshContinuation = nil
    }
  }

  func resumeIssueProgressReport() {
    lock.withLock {
      _issueProgressReportContinuation?.resume()
      _issueProgressReportContinuation = nil
    }
  }

  func nextIssueProgressReportRequest() async -> IssueID? {
    await issueProgressReportRequestStream.next()
  }

  func logStream(endpoint: ServerEndpoint, sessionID: SessionID, cursor: EventCursor?) throws
    -> AsyncThrowingStream<AgentRawEvent, Error>
  {
    lock.withLock {
      _streamRequests.append((sessionID, cursor))
      _streamStartCount += 1
    }
    return AsyncThrowingStream(AgentRawEvent.self) { continuation in
      continuation.onTermination = { [weak self] _ in
        guard let self else { return }
        self.lock.withLock { self._streamTerminationCount += 1 }
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
