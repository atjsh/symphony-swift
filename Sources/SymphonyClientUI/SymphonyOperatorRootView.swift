import SwiftUI
import SymphonyShared

public struct SymphonyOperatorRootView: View {
  @ObservedObject var model: SymphonyOperatorModel
  #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  #endif

  public init(model: SymphonyOperatorModel) {
    self.model = model
  }

  private var isCompact: Bool {
    #if os(iOS)
      return horizontalSizeClass == .compact
    #else
      return false
    #endif
  }

  public var body: some View {
    NavigationSplitView {
      ScrollView {
        VStack(alignment: .leading, spacing: isCompact ? 16 : 20) {
          connectionCard
          issuesSection
        }
        .padding(isCompact ? 12 : 20)
      }
      .navigationTitle("Symphony")
      .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
    } detail: {
      if model.selectedIssueID == nil {
        ContentUnavailableView {
          Label("No Issue Selected", systemImage: "sidebar.left")
        } description: {
          Text("Select an issue from the sidebar to view details, runs, and logs.")
        }
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: isCompact ? 16 : 20) {
            issueDetailSection
            runDetailSection
            logsSection
          }
          .padding(isCompact ? 12 : 20)
        }
        .navigationTitle("Operator")
      }
    }
  }

  private var connectionCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        Circle()
          .fill(connectionStatusColor)
          .frame(width: 8, height: 8)
          .accessibilityIdentifier("connection-status-indicator")
        Text("Connection")
          .font(.title2.weight(.semibold))
      }

      let layout =
        isCompact
        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout())
      layout {
        TextField("Host", text: $model.host)
          .textFieldStyle(.roundedBorder)
          .accessibilityIdentifier("connection-host")
        TextField("Port", text: $model.portText)
          .textFieldStyle(.roundedBorder)
          .frame(width: isCompact ? nil : 96)
          .accessibilityIdentifier("connection-port")
      }

      HStack {
        Button(model.isConnecting ? "Connecting…" : "Connect", action: makeConnectAction())
          .disabled(model.isConnecting)
          .accessibilityIdentifier("connect-button")

        Button(model.isRefreshing ? "Refreshing…" : "Refresh", action: makeRefreshAction())
          .disabled(model.isRefreshing || model.isConnecting)
          .accessibilityIdentifier("refresh-button")
      }

      if let health = model.health {
        Text("Connected to \(health.trackerKind) via \(model.host):\(model.portText)")
          .font(.callout)
          .foregroundStyle(.secondary)
      } else {
        Text("Default endpoint: localhost:8080")
          .font(.callout)
          .foregroundStyle(.secondary)
      }

      if let connectionError = model.connectionError {
        Text(connectionError)
          .font(.callout.weight(.semibold))
          .foregroundStyle(.red)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(
      connectionCardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous)
    )
    .accessibilityIdentifier("connection-card")
  }

  private var connectionStatusColor: Color {
    if model.health != nil { return .green }
    if model.connectionError != nil { return .red }
    return Color.secondary
  }

  private var connectionCardBackground: Color {
    if model.health != nil { return Color.green.opacity(0.06) }
    if model.connectionError != nil { return Color.red.opacity(0.06) }
    return Color.secondary.opacity(0.08)
  }

  private var issuesSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Issues")
        .font(.title3.weight(.semibold))

      if model.issues.isEmpty {
        VStack(spacing: 8) {
          Image(systemName: "tray")
            .font(.title2)
            .foregroundStyle(.secondary)
          Text("No Issues")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
          Text("Connect to a server to see tracked issues.")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .accessibilityIdentifier("issues-empty")
      } else {
        ForEach(model.issues, id: \.issueID.rawValue) { issue in
          Button(action: makeIssueSelectionAction(for: issue)) {
            VStack(alignment: .leading, spacing: 8) {
              HStack {
                Text(issue.identifier.rawValue)
                  .font(.headline)
                  .lineLimit(1)
                if let priority = issue.priority {
                  Text("P\(priority)")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15), in: Capsule())
                }
                Spacer()
                if let provider = issue.currentProvider {
                  ProviderBadge(label: provider)
                }
              }

              Text(issue.title)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)

              Text("\(formatState(issue.state)) \u{00B7} \(issue.issueState)")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
              model.selectedIssueID == issue.issueID
                ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08),
              in: RoundedRectangle(cornerRadius: 14, style: .continuous))
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("issue-row-\(issue.issueID.rawValue)")
        }
      }
    }
    .accessibilityIdentifier("issues-section")
  }

  private var issueDetailSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Issue Detail")
        .font(.title3.weight(.semibold))

      if let detail = model.issueDetail {
        Text(detail.issue.title)
          .font(.title2.weight(.semibold))

        HStack {
          Text(detail.issue.identifier.rawValue)
            .font(.system(.callout, design: .monospaced))
            .foregroundStyle(.secondary)
          if let urlString = detail.issue.url, let url = URL(string: urlString) {
            Link(destination: url) {
              Image(systemName: "arrow.up.right.square")
                .font(.callout)
            }
            .accessibilityIdentifier("issue-url-link")
          }
        }

        if let description = detail.issue.description {
          Text(description)
        }

        if !detail.issue.labels.isEmpty {
          issueLabels(detail.issue.labels)
        }

        if let createdAt = detail.issue.createdAt {
          Text("Created: \(formatTimestamp(createdAt))")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        if let updatedAt = detail.issue.updatedAt {
          Text("Updated: \(formatTimestamp(updatedAt))")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        if !detail.issue.blockedBy.isEmpty {
          blockersList(detail.issue.blockedBy)
        }

        if let workspacePath = detail.workspacePath {
          Text(workspacePath)
            .font(.system(.footnote, design: .monospaced))
            .foregroundStyle(.secondary)
        }

        if let latestRun = detail.latestRun {
          Button(action: makeRunSelectionAction(for: latestRun.runID)) {
            HStack {
              Text("Latest Run")
              Spacer()
              ProviderBadge(label: latestRun.provider)
            }
            .padding(12)
            .background(
              Color.secondary.opacity(0.08),
              in: RoundedRectangle(cornerRadius: 12, style: .continuous))
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("latest-run-button")
        }

        if !detail.recentSessions.isEmpty {
          recentSessionsList(detail.recentSessions)
        }
      } else {
        VStack(spacing: 8) {
          ProgressView()
          Text("Loading issue details\u{2026}")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
      }
    }
    .accessibilityIdentifier("issue-detail-section")
  }

  private func issueLabels(_ labels: [String]) -> some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 6) {
        ForEach(labels, id: \.self) { label in
          Text(label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.12), in: Capsule())
        }
      }
    }
  }

  private func blockersList(_ blockers: [BlockerReference]) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Blocked By")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.orange)
      ForEach(blockers, id: \.issueID.rawValue) { blocker in
        HStack {
          Text(blocker.identifier.rawValue)
            .font(.system(.caption, design: .monospaced))
          Text("(\(formatState(blocker.state)))")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  private func recentSessionsList(_ sessions: [AgentSession]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Recent Sessions")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      ForEach(sessions, id: \.sessionID.rawValue) { session in
        VStack(alignment: .leading, spacing: 6) {
          HStack {
            ProviderBadge(label: session.provider)
            Text(session.status)
              .font(.caption)
            Spacer()
            Text("Turns: \(session.turnCount)")
              .font(.caption)
              .foregroundStyle(.secondary)
            if let lastEventAt = session.lastEventAt {
              Text(formatTimestamp(lastEventAt))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
            }
          }

          metadataLine(label: "Session", value: session.sessionID.rawValue)

          if let providerSessionID = session.providerSessionID {
            metadataLine(label: "Provider session", value: providerSessionID)
          }

          if let providerThreadID = session.providerThreadID {
            metadataLine(label: "Provider thread", value: providerThreadID)
          }

          if let providerTurnID = session.providerTurnID {
            metadataLine(label: "Provider turn", value: providerTurnID)
          }

          if let providerRunID = session.providerRunID {
            metadataLine(label: "Provider run", value: providerRunID)
          }

          if recentSessionHasVisibleTokenUsage(session.tokenUsage) {
            tokenUsageView(session.tokenUsage)
          }

          if let rateLimitPayload = session.latestRateLimitPayload {
            Text(rateLimitPayload)
              .font(.system(.caption2, design: .monospaced))
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
          }
        }
        .padding(8)
        .background(
          Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
    }
    .accessibilityIdentifier("recent-sessions")
  }

  private var runDetailSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Run Detail")
        .font(.title3.weight(.semibold))

      if let runDetail = model.runDetail {
        HStack {
          Text(runDetail.runID.rawValue)
            .font(.system(.headline, design: .monospaced))
          Spacer()
          ProviderBadge(label: runDetail.provider)
        }

        Text("\(formatState(runDetail.status)) · attempt \(runDetail.attempt)")
          .foregroundStyle(.secondary)

        if let providerSessionID = runDetail.providerSessionID {
          Text("Provider session: \(providerSessionID)")
            .font(.system(.footnote, design: .monospaced))
            .foregroundStyle(.secondary)
        }

        if let providerRunID = runDetail.providerRunID {
          Text("Provider run: \(providerRunID)")
            .font(.system(.footnote, design: .monospaced))
            .foregroundStyle(.secondary)
        }

        tokenUsageView(runDetail.tokens)

        if let lastAgentEventType = runDetail.lastAgentEventType {
          Text("Last event: \(lastAgentEventType)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("run-last-event-type")
        }

        if let lastAgentMessage = runDetail.lastAgentMessage {
          Text(lastAgentMessage)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
              Color.secondary.opacity(0.08),
              in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .accessibilityIdentifier("run-last-message")
        }

        if let lastError = runDetail.lastError {
          Text(lastError)
            .font(.callout)
            .foregroundStyle(.red)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
              Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .accessibilityIdentifier("run-last-error")
        }

        Text("Turns: \(runDetail.turnCount) • Events: \(runDetail.logs.eventCount)")
          .font(.footnote)
          .foregroundStyle(.secondary)

        if let latestSequence = runDetail.logs.latestSequence {
          Text("Latest sequence: #\(latestSequence.rawValue)")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        if let endedAt = runDetail.endedAt {
          Text("Ended: \(formatTimestamp(endedAt))")
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("run-ended-at")
        }
      } else {
        VStack(spacing: 8) {
          Image(systemName: "play.circle")
            .font(.title2)
            .foregroundStyle(.secondary)
          Text("No Run Selected")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
      }
    }
    .accessibilityIdentifier("run-detail-section")
  }

  private func tokenUsageView(_ tokens: TokenUsage) -> some View {
    HStack(spacing: 12) {
      if let input = tokens.inputTokens {
        tokenPill(label: "Input", value: input)
      }
      if let output = tokens.outputTokens {
        tokenPill(label: "Output", value: output)
      }
      if let total = tokens.totalTokens {
        tokenPill(label: "Total", value: total)
      }
    }
    .accessibilityIdentifier("token-usage")
  }

  private func tokenPill(label: String, value: Int) -> some View {
    HStack(spacing: 4) {
      Text(label)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
      Text(value.formatted())
        .font(.caption.weight(.medium))
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(
      Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func metadataLine(label: String, value: String) -> some View {
    HStack(spacing: 6) {
      Text(label)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
      Text(value)
        .font(.system(.caption2, design: .monospaced))
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
    }
  }

  private var logsSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Live Log Viewer")
          .font(.title3.weight(.semibold))
        Spacer()
        Text(model.liveStatus)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("live-status")
      }

      if model.logEvents.isEmpty {
        VStack(spacing: 8) {
          Image(systemName: "text.alignleft")
            .font(.title2)
            .foregroundStyle(.secondary)
          Text("No Log Events")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .accessibilityIdentifier("logs-empty")
      } else {
        ForEach(model.logEvents, id: \.sequence.rawValue) { event in
          let presentation = SymphonyEventPresentation(event: event)
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text(presentation.title)
                .font(.headline)
              Spacer()
              ProviderBadge(label: event.provider)
            }

            Text(presentation.detail)
              .font(.body)

            Text(presentation.metadata)
              .font(.system(.caption, design: .monospaced))
              .foregroundStyle(.secondary)

            if presentation.showsRawJSON {
              Text(event.rawJSON)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(12)
          .background(
            eventBackground(for: event.normalizedKind),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
          )
          .accessibilityIdentifier("log-event-\(event.sequence.rawValue)")
        }
      }
    }
    .accessibilityIdentifier("logs-section")
  }

  private func eventBackground(for kind: NormalizedEventKind) -> Color {
    switch kind {
    case .error:
      return Color.red.opacity(0.08)
    case .approvalRequest:
      return Color.orange.opacity(0.08)
    default:
      return Color.secondary.opacity(0.08)
    }
  }
}

extension SymphonyOperatorRootView {
  func makeConnectAction() -> () -> Void {
    { triggerConnect() }
  }

  func makeRefreshAction() -> () -> Void {
    { triggerRefresh() }
  }

  func triggerConnect() {
    Task { await model.connect() }
  }

  func triggerRefresh() {
    Task { await model.refresh() }
  }

  func triggerIssueSelection(_ issue: IssueSummary) {
    Task { await model.selectIssue(issue) }
  }

  func triggerRunSelection(_ runID: RunID) {
    Task { await model.selectRun(runID) }
  }

  func makeIssueSelectionAction(for issue: IssueSummary) -> () -> Void {
    { triggerIssueSelection(issue) }
  }

  func makeRunSelectionAction(for runID: RunID) -> () -> Void {
    { triggerRunSelection(runID) }
  }
}

private struct ProviderBadge: View {
  let label: String

  var body: some View {
    Text(label.replacingOccurrences(of: "_", with: " ").uppercased())
      .font(.caption2.weight(.bold))
      .lineLimit(1)
      .fixedSize(horizontal: true, vertical: false)
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .background(Color.accentColor.opacity(0.12), in: Capsule())
  }
}

private func formatTimestamp(_ isoString: String) -> String {
  let formatter = ISO8601DateFormatter()
  guard let date = formatter.date(from: isoString) else { return isoString }
  let relative = RelativeDateTimeFormatter()
  relative.unitsStyle = .abbreviated
  return relative.localizedString(for: date, relativeTo: Date())
}

private func formatState(_ state: String) -> String {
  state.split(separator: "_")
    .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
    .joined(separator: " ")
}

func recentSessionHasVisibleTokenUsage(_ tokens: TokenUsage) -> Bool {
  if tokens.inputTokens != nil {
    return true
  }
  if tokens.outputTokens != nil {
    return true
  }
  return tokens.totalTokens != nil
}

#if DEBUG
  #Preview {
    SymphonyOperatorRootView(model: SymphonyOperatorModel())
  }
#endif
