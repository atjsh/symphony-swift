import Foundation
import SwiftUI
import SymphonyServerCore
import SymphonyShared

@MainActor
@Observable
public final class SymphonyOperatorModel {
  public var host: String
  public var portText: String
  public var issueSearchText: String
  public var health: HealthResponse?
  public var issues: [IssueSummary]
  public var selectedIssueID: IssueID?
  public var issueDetail: IssueDetail?
  public var selectedRunID: RunID?
  public var runDetail: RunDetail?
  public var logEvents: [AgentRawEvent]
  public var selectedDetailTab: OperatorDetailTab
  public var selectedLogFilter: OperatorLogFilter
  public var connectionError: String?
  public var isConnecting: Bool
  public var isRefreshing: Bool
  public var liveStatus: String
  let progressReportModel: OperatorProgressReportViewModel
  #if os(macOS)
    var localServerWorkflowPath: String
    var localServerSQLitePath: String
    var localServerEnvironmentEntries: [LocalServerEnvironmentEntry]
    var localServerLaunchState: LocalServerLaunchState
    var localServerFailure: String?
    var localServerTranscript: [String]
    var localWorkflowWizardStep: LocalWorkflowWizardStep
    var workflowAuthoringDraft: WorkflowAuthoringDraft
    var workflowAuthoringFailure: String?
  #endif

  @ObservationIgnored let client: any SymphonyAPIClientProtocol
  @ObservationIgnored var liveLogTask: Task<Void, Never>?
  @ObservationIgnored var logCursor: EventCursor?
  #if os(macOS)
    @ObservationIgnored let localServerServices: LocalServerServices?
  #endif

  #if os(macOS)
    init(
      client: (any SymphonyAPIClientProtocol)? = nil,
      initialEndpoint: ServerEndpoint? = nil,
      progressReportCache: (any OperatorProgressReportCaching)? = nil,
      localServerServices: LocalServerServices? = nil
    ) {
      let resolvedEndpoint = initialEndpoint ?? (try! ServerEndpoint())
      self.client = client ?? URLSessionSymphonyAPIClient()
      self.issueSearchText = ""
      self.health = nil
      self.issues = []
      self.selectedIssueID = nil
      self.issueDetail = nil
      self.selectedRunID = nil
      self.runDetail = nil
      self.logEvents = []
      self.selectedDetailTab = .overview
      self.selectedLogFilter = .all
      self.connectionError = nil
      self.isConnecting = false
      self.isRefreshing = false
      self.liveStatus = "Idle"
      self.progressReportModel = OperatorProgressReportViewModel(
        client: self.client,
        cache: progressReportCache ?? DefaultOperatorProgressReportCache.makeDefault()
      )
      self.host = resolvedEndpoint.host
      self.portText = String(resolvedEndpoint.port)
      self.localServerWorkflowPath = ""
      self.localServerSQLitePath = ""
      self.localServerEnvironmentEntries = []
      self.localServerLaunchState = localServerServices == nil ? .idle : .needsSetup
      self.localServerFailure = nil
      self.localServerTranscript = []
      self.localWorkflowWizardStep = .workflow
      self.workflowAuthoringDraft = WorkflowAuthoringDraft()
      self.workflowAuthoringFailure = nil
      self.localServerServices = localServerServices
      configureLocalServerServices()
    }
  #else
    init(
      client: (any SymphonyAPIClientProtocol)? = nil,
      initialEndpoint: ServerEndpoint? = nil,
      progressReportCache: (any OperatorProgressReportCaching)? = nil
    ) {
      let resolvedEndpoint = initialEndpoint ?? (try! ServerEndpoint())
      self.client = client ?? URLSessionSymphonyAPIClient()
      self.issueSearchText = ""
      self.health = nil
      self.issues = []
      self.selectedIssueID = nil
      self.issueDetail = nil
      self.selectedRunID = nil
      self.runDetail = nil
      self.logEvents = []
      self.selectedDetailTab = .overview
      self.selectedLogFilter = .all
      self.connectionError = nil
      self.isConnecting = false
      self.isRefreshing = false
      self.liveStatus = "Idle"
      self.progressReportModel = OperatorProgressReportViewModel(
        client: self.client,
        cache: progressReportCache ?? DefaultOperatorProgressReportCache.makeDefault()
      )
      self.host = resolvedEndpoint.host
      self.portText = String(resolvedEndpoint.port)
    }
  #endif

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

  public var filteredIssues: [IssueSummary] {
    let trimmedQuery = issueSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedQuery.isEmpty else {
      return issues
    }

    let normalizedQuery = trimmedQuery.lowercased()
    var filtered = issues.filter { issue in
      let providerMatches: Bool
      if let currentProvider = issue.currentProvider {
        providerMatches = currentProvider.lowercased().contains(normalizedQuery)
      } else {
        providerMatches = false
      }
      return issue.identifier.rawValue.lowercased().contains(normalizedQuery)
        || issue.title.lowercased().contains(normalizedQuery)
        || issue.state.lowercased().contains(normalizedQuery)
        || issue.issueState.lowercased().contains(normalizedQuery)
        || providerMatches
    }

    if let selectedIssueID,
      let selected = issues.first(where: { $0.issueID == selectedIssueID }),
      !filtered.contains(where: { $0.issueID == selectedIssueID })
    {
      filtered.insert(selected, at: 0)
    }

    return filtered
  }

  public var filteredVisibleLogEvents: [AgentRawEvent] {
    visibleLogEvents.filter(selectedLogFilter.matches(_:))
  }

  #if os(macOS)
    public var hasLocalServerSupport: Bool {
      localServerServices != nil
    }

    public var isLocalServerRunning: Bool {
      localServerLaunchState == .running
    }

    public var localServerPrimaryActionTitle: String {
      switch localServerLaunchState {
      case .running:
        return "Restart Local Server"
      case .starting, .waitingForHealth, .validating:
        return "Starting Local Server"
      case .idle, .needsSetup, .failed:
        return "Start Local Server"
      }
    }

    var workflowAuthoringPreview: WorkflowAuthoringPreviewState {
      WorkflowAuthoringRenderer.preview(draft: workflowAuthoringDraft)
    }
  #endif

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
    selectedDetailTab = .overview
    selectedLogFilter = .all
    progressReportModel.prepareForIssueSelection(issueID: summary.issueID)
    guard let endpoint = serverEndpoint else {
      connectionError = SymphonyClientError.invalidEndpoint.localizedDescription
      return
    }

    do {
      let detail = try await client.issueDetail(endpoint: endpoint, issueID: summary.issueID)
      issueDetail = detail
      progressReportModel.updateIssueContext(
        issueID: summary.issueID,
        workspacePath: detail.workspacePath
      )
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
}
