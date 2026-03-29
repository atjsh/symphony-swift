import Foundation
import SwiftUI
import SymphonyServerCore
import SymphonyShared

@MainActor
public final class SymphonyOperatorModel: ObservableObject {
  @Published public var host: String
  @Published public var portText: String
  @Published public var issueSearchText: String
  @Published public var health: HealthResponse?
  @Published public var issues: [IssueSummary]
  @Published public var selectedIssueID: IssueID?
  @Published public var issueDetail: IssueDetail?
  @Published public var selectedRunID: RunID?
  @Published public var runDetail: RunDetail?
  @Published public var logEvents: [AgentRawEvent]
  @Published public var selectedDetailTab: OperatorDetailTab
  @Published public var selectedLogFilter: OperatorLogFilter
  @Published public var connectionError: String?
  @Published public var isConnecting: Bool
  @Published public var isRefreshing: Bool
  @Published public var liveStatus: String
  #if os(macOS)
    @Published var localServerWorkflowPath: String
    @Published var localServerSQLitePath: String
    @Published var localServerEnvironmentEntries: [LocalServerEnvironmentEntry]
    @Published var localServerLaunchState: LocalServerLaunchState
    @Published var localServerFailure: String?
    @Published var localServerTranscript: [String]
    @Published var localWorkflowWizardStep: LocalWorkflowWizardStep
    @Published var workflowAuthoringDraft: WorkflowAuthoringDraft
    @Published var workflowAuthoringFailure: String?
  #endif

  private let client: any SymphonyAPIClientProtocol
  private var liveLogTask: Task<Void, Never>?
  private var logCursor: EventCursor?
  #if os(macOS)
    private let localServerServices: LocalServerServices?
  #endif

  #if os(macOS)
    init(
      client: (any SymphonyAPIClientProtocol)? = nil,
      initialEndpoint: ServerEndpoint? = nil,
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
      initialEndpoint: ServerEndpoint? = nil
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

  #if os(macOS)
    func testingMakeLocalServerLaunchRequest() throws -> LocalServerLaunchRequest {
      try makeLocalServerLaunchRequest()
    }

    func testingPersistLocalServerDraft() throws {
      try persistLocalServerDraft()
    }

    func testingWorkflowAuthoringPreview() -> WorkflowAuthoringPreviewState {
      workflowAuthoringPreview
    }

    func prepareLocalServerEditor(mode: ServerEditorMode) {
      guard mode == .localServer else {
        return
      }

      workflowAuthoringFailure = nil
      if let workflowURL = try? currentLocalWorkflowURL() {
        loadWorkflowAuthoringDraft(from: workflowURL)
        localWorkflowWizardStep = .localServer
      } else {
        synchronizeWorkflowAuthoringDraftFromLocalServerFields()
        localWorkflowWizardStep = .workflow
      }
    }

    func showWorkflowAuthoringStep() {
      workflowAuthoringFailure = nil
      if let workflowURL = try? currentLocalWorkflowURL() {
        loadWorkflowAuthoringDraft(from: workflowURL)
      } else {
        synchronizeWorkflowAuthoringDraftFromLocalServerFields()
      }
      localWorkflowWizardStep = .workflow
    }

    func updateWorkflowAuthoringDraft<Value>(
      _ keyPath: WritableKeyPath<WorkflowAuthoringDraft, Value>,
      value: Value
    ) {
      var updatedDraft = workflowAuthoringDraft
      updatedDraft[keyPath: keyPath] = value
      workflowAuthoringDraft = updatedDraft
      synchronizeLocalServerFieldsFromWorkflowDraft()
    }

    func applyWorkflowPromptPreset(_ preset: WorkflowPromptPreset) {
      var updatedDraft = workflowAuthoringDraft
      updatedDraft.promptPreset = preset
      updatedDraft.promptBody = preset.seededPrompt
      workflowAuthoringDraft = updatedDraft
    }

    func saveGeneratedWorkflow() {
      guard let services = localServerServices else {
        return
      }

      workflowAuthoringFailure = nil
      localServerFailure = nil
      synchronizeLocalServerFieldsFromWorkflowDraft()

      do {
        let content = try WorkflowAuthoringRenderer.validatedContent(draft: workflowAuthoringDraft)
        let suggestedDirectoryURL =
          try? currentLocalWorkflowURL().deletingLastPathComponent()
        guard
          let savedWorkflowURL = try services.workflowSaver.saveWorkflow(
            named: WorkflowAuthoringDraft.defaultWorkflowFileName,
            suggestedDirectoryURL: suggestedDirectoryURL,
            content: content
          )
        else {
          return
        }

        localServerWorkflowPath = savedWorkflowURL.path
        loadWorkflowAuthoringDraft(from: savedWorkflowURL)

        let variables = try services.variableScanner.scanVariables(at: savedWorkflowURL)
        mergeLocalEnvironmentEntries(requiredKeys: variables)
        try persistLocalServerDraft()
        localServerLaunchState = .idle
        localWorkflowWizardStep = .localServer
      } catch {
        workflowAuthoringFailure = error.localizedDescription
      }
    }

    func loadLocalServerProfile() {
      guard let services = localServerServices,
        let profile = services.profileStore.loadProfile()
      else {
        localServerLaunchState = hasLocalServerSupport ? .needsSetup : .idle
        return
      }

      if let workflowURL = profile.resolvedWorkflowURL() {
        localServerWorkflowPath = workflowURL.path
      } else {
        localServerWorkflowPath = profile.workflowPath ?? ""
      }
      host = profile.host
      portText = String(profile.port)
      localServerSQLitePath = profile.sqlitePath ?? ""
      localServerEnvironmentEntries = profile.environmentKeys.map { key in
        LocalServerEnvironmentEntry(
          name: key,
          value: services.secretStore.secret(for: key) ?? "",
          isRequired: true
        )
      }
      if let workflowURL = profile.resolvedWorkflowURL(),
        let definition = try? WorkflowParser.parse(contentsOf: workflowURL)
      {
        applyWorkflowDefinition(definition)
      }
      if localServerWorkflowPath.isEmpty {
        localServerLaunchState = .needsSetup
        localWorkflowWizardStep = .workflow
      } else {
        localWorkflowWizardStep = .localServer
      }
    }

    func chooseLocalWorkflow() {
      guard let services = localServerServices,
        let workflowURL = services.workflowSelector.selectWorkflowURL()
      else {
        return
      }

      localServerWorkflowPath = workflowURL.path
      localServerFailure = nil
      workflowAuthoringFailure = nil
      do {
        loadWorkflowAuthoringDraft(from: workflowURL)
        let variables = try services.variableScanner.scanVariables(at: workflowURL)
        mergeLocalEnvironmentEntries(requiredKeys: variables)
        try persistLocalServerDraft()
        localServerLaunchState = .idle
        localWorkflowWizardStep = .localServer
      } catch {
        localServerLaunchState = .failed
        localServerFailure = error.localizedDescription
      }
    }

    func addLocalServerEnvironmentEntry() {
      localServerEnvironmentEntries.append(LocalServerEnvironmentEntry(name: ""))
    }

    func removeLocalServerEnvironmentEntry(id: UUID) {
      localServerEnvironmentEntries.removeAll { $0.id == id }
    }

    public func startLocalServer() async {
      guard let services = localServerServices else {
        return
      }

      do {
        localServerLaunchState = .validating
        localServerFailure = nil
        let request = try makeLocalServerLaunchRequest()
        try persistLocalServerDraft()
        await services.manager.start(request: request)
        if services.manager.statusSnapshot.state == .running {
          host = request.endpoint.host
          portText = String(request.endpoint.port)
          connectionError = nil
          await connect()
        }
      } catch let error as LocalServerLaunchError {
        localServerFailure = error.localizedDescription
        localServerLaunchState =
          switch error {
          case .workflowNotConfigured, .workflowMissing, .invalidPort, .missingEnvironmentKeys:
            .needsSetup
          case .helperUnavailable, .startupFailed, .helperExitedBeforeReady, .healthTimedOut,
            .occupiedPort:
            .failed
          }
      } catch {
        localServerFailure = error.localizedDescription
        localServerLaunchState = .failed
      }
    }

    public func restartLocalServer() async {
      guard let services = localServerServices else {
        return
      }

      do {
        localServerLaunchState = .validating
        localServerFailure = nil
        let request = try makeLocalServerLaunchRequest()
        try persistLocalServerDraft()
        await services.manager.restart(request: request)
        if services.manager.statusSnapshot.state == .running {
          host = request.endpoint.host
          portText = String(request.endpoint.port)
          connectionError = nil
          await connect()
        }
      } catch {
        localServerFailure = error.localizedDescription
        localServerLaunchState = .failed
      }
    }

    public func stopLocalServer() async {
      guard let services = localServerServices else {
        return
      }

      await services.manager.stop()
      disconnectFromServer()
    }

    private func configureLocalServerServices() {
      guard let localServerServices else {
        return
      }

      localServerServices.manager.onStatusChange = { [weak self] snapshot in
        self?.applyLocalServerStatus(snapshot)
      }
      applyLocalServerStatus(localServerServices.manager.statusSnapshot)
      loadLocalServerProfile()
    }

    private func applyLocalServerStatus(_ snapshot: LocalServerStatusSnapshot) {
      localServerLaunchState = snapshot.state
      localServerTranscript = snapshot.transcript
      localServerFailure = snapshot.failureDescription
      if snapshot.state == .running {
        host = snapshot.endpoint.host
        portText = String(snapshot.endpoint.port)
      }
    }

    private func persistLocalServerDraft() throws {
      guard let services = localServerServices else {
        return
      }

      let workflowURL = try currentLocalWorkflowURL()
      let port = try resolvedLocalServerPort()
      let environmentEntries = sanitizedLocalEnvironmentEntries()
      let profile = LocalServerProfile(
        workflowBookmarkData: try? LocalServerProfile.bookmarkData(for: workflowURL),
        workflowPath: workflowURL.path,
        host: resolvedLocalServerHost(),
        port: port,
        sqlitePath: normalizedOptionalText(localServerSQLitePath),
        environmentKeys: environmentEntries.map(\.name)
      )

      let previousKeys = Set(services.profileStore.loadProfile()?.environmentKeys ?? [])
      let nextKeys = Set(profile.environmentKeys)
      try services.profileStore.saveProfile(profile)
      for entry in environmentEntries {
        try services.secretStore.setSecret(entry.value, for: entry.name)
      }
      for removedKey in previousKeys.subtracting(nextKeys) {
        try services.secretStore.removeSecret(for: removedKey)
      }
    }

    private func makeLocalServerLaunchRequest() throws -> LocalServerLaunchRequest {
      guard let services = localServerServices else {
        throw LocalServerLaunchError.startupFailed("Local server support is unavailable.")
      }

      let workflowURL = try currentLocalWorkflowURL()
      let helperURL = try services.helperLocator.helperURL()
      let port = try resolvedLocalServerPort()
      let host = resolvedLocalServerHost()
      let endpoint = BootstrapServerEndpoint(scheme: "http", host: host, port: port)
      let environmentEntries = sanitizedLocalEnvironmentEntries()
      let missingKeys = environmentEntries.filter {
        $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
          && $0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }.map(\.name)

      if !missingKeys.isEmpty {
        throw LocalServerLaunchError.missingEnvironmentKeys(missingKeys)
      }

      var environment = services.environmentProvider()
      for entry in environmentEntries {
        environment[entry.name] = entry.value
      }
      environment[BootstrapEnvironment.serverHostKey] = host
      environment[BootstrapEnvironment.serverPortKey] = String(port)
      environment[SymphonyServerBootstrapEnvironment.workflowPathKey] = workflowURL.path
      if let sqlitePath = normalizedOptionalText(localServerSQLitePath) {
        environment[SymphonyServerBootstrapEnvironment.serverSQLitePathKey] = sqlitePath
      }

      return LocalServerLaunchRequest(
        helperURL: helperURL,
        workflowURL: workflowURL,
        currentDirectoryURL: workflowURL.deletingLastPathComponent(),
        endpoint: endpoint,
        environment: environment
      )
    }

    private func currentLocalWorkflowURL() throws -> URL {
      let trimmedPath = localServerWorkflowPath.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmedPath.isEmpty else {
        throw LocalServerLaunchError.workflowNotConfigured
      }

      let workflowURL = URL(fileURLWithPath: NSString(string: trimmedPath).expandingTildeInPath)
      guard FileManager.default.fileExists(atPath: workflowURL.path) else {
        throw LocalServerLaunchError.workflowMissing(workflowURL.path)
      }
      return workflowURL
    }

    private func sanitizedLocalEnvironmentEntries() -> [LocalServerEnvironmentEntry] {
      var ordered = [LocalServerEnvironmentEntry]()
      var seen = Set<String>()

      for entry in localServerEnvironmentEntries {
        let trimmedName = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !seen.contains(trimmedName) else {
          continue
        }
        seen.insert(trimmedName)
        ordered.append(
          LocalServerEnvironmentEntry(
            id: entry.id,
            name: trimmedName,
            value: entry.value.trimmingCharacters(in: .whitespacesAndNewlines),
            isRequired: entry.isRequired
          )
        )
      }
      return ordered
    }

    private func mergeLocalEnvironmentEntries(requiredKeys: [String]) {
      let existingByName = Dictionary(uniqueKeysWithValues: localServerEnvironmentEntries.map {
        ($0.name, $0)
      })
      var merged = [LocalServerEnvironmentEntry]()
      for key in requiredKeys {
        if var existing = existingByName[key] {
          existing.isRequired = true
          merged.append(existing)
        } else {
          merged.append(LocalServerEnvironmentEntry(name: key, isRequired: true))
        }
      }

      for entry in localServerEnvironmentEntries {
        let trimmedName = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !requiredKeys.contains(trimmedName) else {
          continue
        }
        merged.append(
          LocalServerEnvironmentEntry(
            id: entry.id,
            name: trimmedName,
            value: entry.value,
            isRequired: false
          )
        )
      }
      localServerEnvironmentEntries = merged
    }

    private func resolvedLocalServerPort() throws -> Int {
      let trimmedPort = portText.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let port = Int(trimmedPort), (1...65535).contains(port) else {
        throw LocalServerLaunchError.invalidPort(trimmedPort)
      }
      return port
    }

    private func resolvedLocalServerHost() -> String {
      let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmedHost.isEmpty ? BootstrapServerEndpoint.defaultEndpoint.host : trimmedHost
    }

    private func normalizedOptionalText(_ value: String) -> String? {
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }

    private func synchronizeLocalServerFieldsFromWorkflowDraft() {
      host = workflowAuthoringDraft.serverHost.trimmingCharacters(in: .whitespacesAndNewlines)
      portText = workflowAuthoringDraft.serverPort.trimmingCharacters(in: .whitespacesAndNewlines)
      localServerSQLitePath = workflowAuthoringDraft.storageSQLitePath
    }

    private func synchronizeWorkflowAuthoringDraftFromLocalServerFields() {
      var updatedDraft = workflowAuthoringDraft
      updatedDraft.serverHost = resolvedLocalServerHost()
      updatedDraft.serverPort = portText.trimmingCharacters(in: .whitespacesAndNewlines)
      updatedDraft.storageSQLitePath = localServerSQLitePath
      workflowAuthoringDraft = updatedDraft
    }

    private func loadWorkflowAuthoringDraft(from workflowURL: URL) {
      guard let definition = try? WorkflowParser.parse(contentsOf: workflowURL) else {
        synchronizeWorkflowAuthoringDraftFromLocalServerFields()
        return
      }
      applyWorkflowDefinition(definition)
    }

    private func applyWorkflowDefinition(_ definition: WorkflowDefinition) {
      var updatedDraft = WorkflowAuthoringDraft(definition: definition)
      updatedDraft.serverHost = resolvedLocalServerHost()
      updatedDraft.serverPort =
        portText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? String(definition.config.server.port) : portText.trimmingCharacters(in: .whitespacesAndNewlines)
      updatedDraft.storageSQLitePath = localServerSQLitePath
      workflowAuthoringDraft = updatedDraft
    }

    private func disconnectFromServer() {
      health = nil
      issues = []
      selectedIssueID = nil
      issueDetail = nil
      selectedRunID = nil
      runDetail = nil
      connectionError = nil
      clearLogs()
    }
  #endif
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

  init(
    rowStyle: RowStyle,
    title: String,
    detail: String,
    metadata: String,
    showsRawJSON: Bool
  ) {
    self.rowStyle = rowStyle
    self.title = title
    self.detail = detail
    self.metadata = metadata
    self.showsRawJSON = showsRawJSON
  }

  public init(event: AgentRawEvent) {
    self.metadata =
      "\(Self.displayMetadataToken(event.provider)) • #\(event.sequence.rawValue) • \(Self.displayMetadataToken(event.providerEventType))"

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

  private static func displayMetadataToken(_ value: String) -> String {
    value.replacingOccurrences(of: "_", with: " ")
  }
}
