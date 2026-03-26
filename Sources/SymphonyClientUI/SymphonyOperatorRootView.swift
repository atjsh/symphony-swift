import Foundation
import SwiftUI
import SymphonyShared

public struct SymphonyOperatorRootView: View {
  @ObservedObject var model: SymphonyOperatorModel
  #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  #endif

  private var isCompact: Bool {
    #if os(iOS)
      return horizontalSizeClass == .compact
    #else
      return false
    #endif
  }

  private var theme: OperatorTheme {
    OperatorTheme(compact: isCompact)
  }

  public init(model: SymphonyOperatorModel) {
    self.model = model
  }

  public var body: some View {
    NavigationSplitView {
      sidebar
    } detail: {
      detailPane
    }
    .preferredColorScheme(.dark)
  }

  private var sidebar: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: theme.sectionSpacing) {
        ConnectionPanel(
          theme: theme,
          host: $model.host,
          portText: $model.portText,
          health: model.health,
          connectionError: model.connectionError,
          isConnecting: model.isConnecting,
          isRefreshing: model.isRefreshing,
          connectAction: makeConnectAction(),
          refreshAction: makeRefreshAction(),
          compact: isCompact
        )
        IssuesPanel(
          theme: theme,
          issues: model.issues,
          selectedIssueID: model.selectedIssueID,
          selectionAction: makeIssueSelectionAction(for:),
          emptyStateText: model.health == nil
            ? "Connect to a server to see tracked issues."
            : "No tracked issues are available right now."
        )
      }
      .padding(theme.pagePadding)
    }
    .background(theme.canvas.ignoresSafeArea())
    .foregroundStyle(theme.bodyText)
    .navigationTitle("Symphony")
    .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
  }

  @ViewBuilder
  private var detailPane: some View {
    if model.selectedIssueID == nil {
      ContentUnavailableView {
        Label("No Issue Selected", systemImage: "sidebar.left")
      } description: {
        Text("Select an issue from the sidebar to view details, runs, and logs.")
      }
      .background(theme.canvas.ignoresSafeArea())
      .foregroundStyle(theme.bodyText)
      .navigationTitle("Operator")
    } else {
      ScrollView {
        VStack(alignment: .leading, spacing: theme.sectionSpacing) {
          issueDetailSection
          runDetailSection
          logsSection
        }
        .padding(theme.pagePadding)
      }
      .background(theme.canvas.ignoresSafeArea())
      .foregroundStyle(theme.bodyText)
      .navigationTitle("Operator")
    }
  }

  private var issueDetailSection: some View {
    VStack(alignment: .leading, spacing: theme.blockSpacing) {
      SectionHeader(title: "Issue Detail")

      if let detail = model.issueDetail {
        IssueOverviewPanel(
          theme: theme,
          detail: detail,
          latestRunSelected: detail.latestRun?.runID == model.selectedRunID,
          runSelectionAction: detail.latestRun.map { latestRun in
            makeRunSelectionAction(for: latestRun.runID)
          },
          compact: isCompact
        )

        if !detail.recentSessions.isEmpty {
          RecentSessionsPanel(theme: theme, sessions: detail.recentSessions)
        }
      } else {
        LoadingStatePanel(
          theme: theme,
          systemImage: "arrow.triangle.2.circlepath",
          title: "Loading issue details…"
        )
      }
    }
    .accessibilityIdentifier("issue-detail-section")
  }

  private var runDetailSection: some View {
    VStack(alignment: .leading, spacing: theme.blockSpacing) {
      SectionHeader(title: "Run Detail")

      if let runDetail = model.runDetail {
        RunOverviewPanel(theme: theme, runDetail: runDetail)
      } else {
        EmptyStatePanel(theme: theme, systemImage: "play.circle", title: "No Run Selected")
      }
    }
    .accessibilityIdentifier("run-detail-section")
  }

  private var logsSection: some View {
    VStack(alignment: .leading, spacing: theme.blockSpacing) {
      HStack(alignment: .center, spacing: 12) {
        SectionHeader(title: "Live Log Viewer")
        Spacer()
        StatePill(theme: theme, text: model.liveStatus, tint: liveStatusTint(model.liveStatus))
          .accessibilityIdentifier("live-status")
      }

      LogTimelinePanel(theme: theme, logEvents: model.visibleLogEvents)
        .accessibilityIdentifier("logs-section")
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
    if model.selectedRunID == runID, model.runDetail?.runID == runID {
      return
    }
    Task { await model.selectRun(runID) }
  }

  func makeIssueSelectionAction(for issue: IssueSummary) -> () -> Void {
    { triggerIssueSelection(issue) }
  }

  func makeRunSelectionAction(for runID: RunID) -> () -> Void {
    { triggerRunSelection(runID) }
  }
}

struct OperatorTheme {
  let compact: Bool

  var pagePadding: CGFloat { compact ? 12 : 18 }
  var sectionSpacing: CGFloat { compact ? 16 : 20 }
  var blockSpacing: CGFloat { compact ? 10 : 12 }
  var panelPadding: CGFloat { compact ? 13 : 16 }
  var itemPadding: CGFloat { compact ? 9 : 11 }
  var rowSpacing: CGFloat { compact ? 8 : 10 }
  var panelCornerRadius: CGFloat { compact ? 16 : 18 }
  var itemCornerRadius: CGFloat { compact ? 11 : 13 }
  var canvas: Color { Color(red: 0.105, green: 0.109, blue: 0.113) }
  var panelFill: Color { Color(red: 0.142, green: 0.146, blue: 0.151) }
  var insetFill: Color { Color(red: 0.163, green: 0.168, blue: 0.173) }
  var panelBorder: Color { Color.white.opacity(0.055) }
  var bodyText: Color { Color(red: 0.925, green: 0.928, blue: 0.935) }
  var quietText: Color { Color(red: 0.655, green: 0.667, blue: 0.694) }
  var subduedText: Color { Color(red: 0.776, green: 0.784, blue: 0.806) }
  var emphasisFill: Color { Color(red: 0.192, green: 0.231, blue: 0.291) }
  var emphasisBorder: Color { Color(red: 0.318, green: 0.381, blue: 0.469) }
  var accentTint: Color { Color(red: 0.541, green: 0.655, blue: 0.812) }
  var toolTint: Color { Color(red: 0.493, green: 0.607, blue: 0.724) }
  var successTint: Color { Color(red: 0.492, green: 0.725, blue: 0.576) }
  var warningTint: Color { Color(red: 0.786, green: 0.639, blue: 0.437) }
  var errorTint: Color { Color(red: 0.812, green: 0.498, blue: 0.498) }
  var timeline: Color { Color.white.opacity(0.07) }
  var badgeFill: Color { Color.white.opacity(0.045) }
  var badgeBorder: Color { Color.white.opacity(0.05) }
}

private struct SectionHeader: View {
  let title: String

  var body: some View {
    Text(title)
      .font(.headline.weight(.semibold))
      .foregroundStyle(.white.opacity(0.92))
  }
}

private struct ConnectionPanel: View {
  let theme: OperatorTheme
  @Binding var host: String
  @Binding var portText: String
  let health: HealthResponse?
  let connectionError: String?
  let isConnecting: Bool
  let isRefreshing: Bool
  let connectAction: () -> Void
  let refreshAction: () -> Void
  let compact: Bool

  private var statusTint: Color {
    if health != nil { return .green }
    if connectionError != nil { return .red }
    return .secondary
  }

  var body: some View {
    VStack(alignment: .leading, spacing: theme.blockSpacing) {
      HStack(spacing: 8) {
        Circle()
          .fill(statusTint)
          .frame(width: 8, height: 8)
          .accessibilityIdentifier("connection-status-indicator")
        Text("Connection")
          .font(.title3.weight(.semibold))
        Spacer()
        if health != nil {
          Text("Ready")
            .font(.caption.weight(.medium))
            .foregroundStyle(theme.quietText)
        }
      }

      let layout =
        compact
        ? AnyLayout(VStackLayout(alignment: .leading, spacing: theme.rowSpacing))
        : AnyLayout(HStackLayout(alignment: .center, spacing: theme.rowSpacing))

      layout {
        TextField("Host", text: $host)
          .textFieldStyle(.roundedBorder)
          .accessibilityIdentifier("connection-host")
        TextField("Port", text: $portText)
          .textFieldStyle(.roundedBorder)
          .frame(width: compact ? nil : 96)
          .accessibilityIdentifier("connection-port")
      }

      HStack(spacing: 10) {
        Button(isConnecting ? "Connecting…" : "Connect", action: connectAction)
          .buttonStyle(.bordered)
          .tint(theme.accentTint)
          .controlSize(.small)
          .disabled(isConnecting)
          .accessibilityIdentifier("connect-button")

        Button(isRefreshing ? "Refreshing…" : "Refresh", action: refreshAction)
          .buttonStyle(.bordered)
          .controlSize(.small)
          .disabled(isRefreshing || isConnecting)
          .accessibilityIdentifier("refresh-button")
      }

      if let health {
        Text("Connected to \(health.trackerKind) via \(host):\(portText)")
          .font(.callout)
          .foregroundStyle(theme.quietText)
      } else {
        Text("Default endpoint: localhost:8080")
          .font(.callout)
          .foregroundStyle(theme.quietText)
      }

      if let connectionError {
        Text(connectionError)
          .font(.callout.weight(.semibold))
          .foregroundStyle(.red)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .operatorPanel(theme)
    .accessibilityIdentifier("connection-card")
  }
}

private struct IssuesPanel: View {
  let theme: OperatorTheme
  let issues: [IssueSummary]
  let selectedIssueID: IssueID?
  let selectionAction: (IssueSummary) -> () -> Void
  let emptyStateText: String

  var body: some View {
    VStack(alignment: .leading, spacing: theme.blockSpacing) {
      HStack(alignment: .center) {
        Text("Issues")
          .font(.title3.weight(.semibold))
        Spacer()
        if !issues.isEmpty {
          Text("\(issues.count)")
            .font(.caption.weight(.medium))
            .foregroundStyle(theme.quietText)
        }
      }

      if issues.isEmpty {
        EmptyStatePanel(
          theme: theme,
          systemImage: "tray",
          title: "No Issues",
          detail: emptyStateText
        )
        .accessibilityIdentifier("issues-empty")
      } else {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(Array(issues.enumerated()), id: \.element.issueID.rawValue) { index, issue in
            Button(action: selectionAction(issue)) {
              IssueRow(
                theme: theme,
                issue: issue,
                isSelected: issue.issueID == selectedIssueID
              )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("issue-row-\(issue.issueID.rawValue)")

            if index != issues.index(before: issues.endIndex) {
              Divider()
                .overlay(theme.panelBorder)
            }
          }
        }
      }
    }
    .operatorPanel(theme)
    .accessibilityIdentifier("issues-section")
  }
}

private struct IssueRow: View {
  let theme: OperatorTheme
  let issue: IssueSummary
  let isSelected: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(issue.identifier.rawValue)
          .font(.headline.weight(.semibold))
          .foregroundStyle(theme.bodyText)
          .lineLimit(1)
        Spacer(minLength: 12)
        if let provider = issue.currentProvider {
          ProviderBadge(theme: theme, label: provider)
        }
      }

      Text(issue.title)
        .font(.subheadline)
        .foregroundStyle(.primary)
        .lineLimit(2)

      HStack(spacing: 6) {
        StatePill(theme: theme, text: formatState(issue.state), tint: statusTint(issue.state))
        QuietBadge(theme: theme, text: issue.issueState)
        if let priority = issue.priority {
          PriorityBadge(theme: theme, priority: priority)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(theme.itemPadding)
    .background(
      isSelected ? theme.emphasisFill : Color.clear,
      in: RoundedRectangle(cornerRadius: theme.itemCornerRadius, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: theme.itemCornerRadius, style: .continuous)
        .stroke(isSelected ? theme.emphasisBorder : .clear, lineWidth: 1)
    )
  }
}

struct IssueOverviewPanel: View {
  let theme: OperatorTheme
  let detail: IssueDetail
  let latestRunSelected: Bool
  let runSelectionAction: (() -> Void)?
  let compact: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: theme.blockSpacing) {
      header

      if let description = detail.issue.description, !description.isEmpty {
        Text(description)
          .font(.body)
          .fixedSize(horizontal: false, vertical: true)
      }

      if !detail.issue.labels.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 6) {
            ForEach(detail.issue.labels, id: \.self) { label in
              QuietBadge(theme: theme, text: label)
            }
          }
        }
      }

      VStack(alignment: .leading, spacing: 10) {
        if let createdAt = detail.issue.createdAt {
          DetailLine(label: "Created", value: formatTimestamp(createdAt))
        }

        if let updatedAt = detail.issue.updatedAt {
          DetailLine(label: "Updated", value: formatTimestamp(updatedAt))
        }

        if let workspacePath = detail.workspacePath {
          DetailLine(label: "Workspace", value: workspacePath, monospaced: true)
        }
      }

      if !detail.issue.blockedBy.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Text("Blocked By")
            .font(.caption.weight(.semibold))
            .foregroundStyle(theme.quietText)

          ForEach(detail.issue.blockedBy, id: \.issueID.rawValue) { blocker in
            HStack(spacing: 8) {
              Text(blocker.identifier.rawValue)
                .font(.system(.caption, design: .monospaced))
              StatePill(
                theme: theme, text: formatState(blocker.state), tint: statusTint(blocker.state))
            }
          }
        }
      }
    }
    .operatorPanel(theme)
  }

  @ViewBuilder
  private var header: some View {
    if compact {
      VStack(alignment: .leading, spacing: theme.blockSpacing) {
        headerSummary
        latestRunButton
      }
    } else {
      HStack(alignment: .top, spacing: theme.blockSpacing) {
        headerSummary
        Spacer(minLength: theme.blockSpacing)
        latestRunButton
      }
    }
  }

  private var headerSummary: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Text(detail.issue.identifier.rawValue)
          .font(.system(.caption, design: .monospaced))
          .foregroundStyle(theme.quietText)

        if let urlString = detail.issue.url, let url = URL(string: urlString) {
          Link(destination: url) {
            Image(systemName: "arrow.up.right.square")
              .font(.caption.weight(.medium))
          }
          .accessibilityIdentifier("issue-url-link")
        }
      }

      Text(detail.issue.title)
        .font(.title2.weight(.semibold))
        .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: 6) {
        StatePill(
          theme: theme, text: formatState(detail.issue.state), tint: statusTint(detail.issue.state))
        QuietBadge(theme: theme, text: detail.issue.issueState)
        if let priority = detail.issue.priority {
          PriorityBadge(theme: theme, priority: priority)
        }
      }
    }
  }

  @ViewBuilder
  private var latestRunButton: some View {
    if let latestRun = detail.latestRun, let runSelectionAction {
      Button(action: runSelectionAction) {
        HStack(spacing: 8) {
          Text("Latest Run")
            .font(.subheadline.weight(.semibold))
          ProviderBadge(theme: theme, label: latestRun.provider)
        }
        .frame(maxWidth: compact ? .infinity : nil, alignment: .center)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
          latestRunSelected ? theme.emphasisFill : theme.insetFill,
          in: RoundedRectangle(cornerRadius: theme.itemCornerRadius, style: .continuous)
        )
        .overlay(
          RoundedRectangle(cornerRadius: theme.itemCornerRadius, style: .continuous)
            .stroke(latestRunSelected ? theme.emphasisBorder : theme.panelBorder, lineWidth: 1)
        )
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("latest-run-button")
    }
  }
}

private struct RecentSessionsPanel: View {
  let theme: OperatorTheme
  let sessions: [AgentSession]

  var body: some View {
    VStack(alignment: .leading, spacing: theme.blockSpacing) {
      HStack {
        Text("Recent Sessions")
          .font(.caption.weight(.semibold))
          .foregroundStyle(theme.quietText)
        Spacer()
      }

      ForEach(sessions, id: \.sessionID.rawValue) { session in
        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 8) {
            ProviderBadge(theme: theme, label: session.provider)
            Text(formatState(session.status))
              .font(.subheadline.weight(.medium))
            Spacer()
            Text("\(session.turnCount) turns")
              .font(.caption)
              .foregroundStyle(theme.quietText)
            if let lastEventAt = session.lastEventAt {
              Text(formatTimestamp(lastEventAt))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(theme.quietText)
            }
          }

          DetailLine(label: "Session", value: session.sessionID.rawValue, monospaced: true)

          if let providerSessionID = session.providerSessionID {
            DetailLine(label: "Provider session", value: providerSessionID, monospaced: true)
          }

          if let providerThreadID = session.providerThreadID {
            DetailLine(label: "Thread", value: providerThreadID, monospaced: true)
          }

          if let providerTurnID = session.providerTurnID {
            DetailLine(label: "Turn", value: providerTurnID, monospaced: true)
          }

          if let providerRunID = session.providerRunID {
            DetailLine(label: "Run", value: providerRunID, monospaced: true)
          }

          if recentSessionHasVisibleTokenUsage(session.tokenUsage) {
            TokenUsageStrip(theme: theme, tokens: session.tokenUsage)
          }

          if let rateLimitPayload = session.latestRateLimitPayload {
            Text(rateLimitPayload)
              .font(.system(.caption2, design: .monospaced))
              .foregroundStyle(theme.quietText)
              .textSelection(.enabled)
              .padding(10)
              .operatorInset(theme)
          }
        }
        .padding(theme.itemPadding)
        .operatorInset(theme)
      }
    }
    .operatorPanel(theme)
    .accessibilityIdentifier("recent-sessions")
  }
}

private struct RunOverviewPanel: View {
  let theme: OperatorTheme
  let runDetail: RunDetail

  var body: some View {
    VStack(alignment: .leading, spacing: theme.blockSpacing) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 8) {
          Text(runDetail.runID.rawValue)
            .font(.system(.headline, design: .monospaced))

          HStack(spacing: 6) {
            StatePill(
              theme: theme, text: formatState(runDetail.status), tint: statusTint(runDetail.status))
            QuietBadge(theme: theme, text: "Attempt \(runDetail.attempt)")
          }
        }

        Spacer(minLength: 12)

        ProviderBadge(theme: theme, label: runDetail.provider)
      }

      TokenUsageStrip(theme: theme, tokens: runDetail.tokens)

      MetricsStrip(
        theme: theme,
        metrics: [
          ("Turns", "\(runDetail.turnCount)"),
          ("Events", "\(runDetail.logs.eventCount)"),
          ("Sequence", runDetail.logs.latestSequence.map { "#\($0.rawValue)" } ?? "—"),
        ]
      )

      VStack(alignment: .leading, spacing: 10) {
        if let providerSessionID = runDetail.providerSessionID {
          DetailLine(label: "Provider session", value: providerSessionID, monospaced: true)
        }

        if let providerRunID = runDetail.providerRunID {
          DetailLine(label: "Provider run", value: providerRunID, monospaced: true)
        }

        if let lastAgentEventType = runDetail.lastAgentEventType {
          DetailLine(label: "Last event", value: lastAgentEventType)
            .accessibilityIdentifier("run-last-event-type")
        }

        if let endedAt = runDetail.endedAt {
          DetailLine(label: "Ended", value: formatTimestamp(endedAt))
            .accessibilityIdentifier("run-ended-at")
        }
      }

      if let lastAgentMessage = runDetail.lastAgentMessage {
        VStack(alignment: .leading, spacing: 6) {
          Text("Latest Message")
            .font(.caption.weight(.semibold))
            .foregroundStyle(theme.quietText)
          MarkdownMessageText(theme: theme, text: lastAgentMessage)
            .padding(theme.itemPadding)
            .operatorInset(theme)
        }
        .accessibilityIdentifier("run-last-message")
      }

      if let lastError = runDetail.lastError {
        VStack(alignment: .leading, spacing: 6) {
          Text("Last Error")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.red)
          Text(lastError)
            .font(.callout)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .padding(theme.itemPadding)
            .background(
              Color.red.opacity(0.10),
              in: RoundedRectangle(cornerRadius: theme.itemCornerRadius, style: .continuous)
            )
        }
        .accessibilityIdentifier("run-last-error")
      }
    }
    .operatorPanel(theme)
  }
}

struct LogTimelinePanel: View {
  let theme: OperatorTheme
  let logEvents: [AgentRawEvent]

  var body: some View {
    if logEvents.isEmpty {
      EmptyStatePanel(
        theme: theme,
        systemImage: "text.alignleft",
        title: "No Relevant Log Events"
      )
      .accessibilityIdentifier("logs-empty")
    } else {
      VStack(alignment: .leading, spacing: theme.blockSpacing) {
        ForEach(Array(logEvents.enumerated()), id: \.element.sequence.rawValue) { index, event in
          LogEventRow(
            theme: theme,
            event: event,
            presentation: SymphonyEventPresentation(event: event),
            isLast: index == logEvents.index(before: logEvents.endIndex)
          )
          .accessibilityIdentifier("log-event-\(event.sequence.rawValue)")
        }
      }
      .operatorPanel(theme)
    }
  }
}

struct LogEventRow: View {
  let theme: OperatorTheme
  let event: AgentRawEvent
  let presentation: SymphonyEventPresentation
  let isLast: Bool

  var body: some View {
    HStack(alignment: .top, spacing: theme.blockSpacing) {
      TimelineMarker(
        theme: theme, rowStyle: presentation.rowStyle, tint: markerTint, isLast: isLast)

      switch presentation.rowStyle {
      case .message:
        messageContent
      case .tool:
        toolContent
      case .compact:
        compactContent
      case .callout:
        calloutContent
      case .supplemental:
        supplementalContent
      }
    }
  }

  private var markerTint: Color {
    switch presentation.rowStyle {
    case .message:
      return theme.accentTint
    case .tool:
      return theme.toolTint
    case .compact:
      return statusTint(presentation.detail)
    case .callout:
      return event.normalizedKind == .error ? theme.errorTint : theme.warningTint
    case .supplemental:
      return .secondary
    }
  }

  private var messageContent: some View {
    VStack(alignment: .leading, spacing: 6) {
      EventMetaLine(theme: theme, title: presentation.title, metadata: presentation.metadata)
      MarkdownMessageText(theme: theme, text: presentation.detail)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var toolContent: some View {
    VStack(alignment: .leading, spacing: 8) {
      EventMetaLine(theme: theme, title: presentation.title, metadata: presentation.metadata)
      Text(presentation.detail)
        .font(.system(.callout, design: .monospaced))
        .foregroundStyle(theme.subduedText)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
        .padding(theme.itemPadding)
        .operatorInset(theme)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var compactContent: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      EventTag(theme: theme, text: presentation.title, tint: markerTint)
      Text(presentation.detail)
        .font(.subheadline.weight(.medium))
        .foregroundStyle(theme.bodyText)
      Spacer(minLength: 8)
      Text(presentation.metadata)
        .font(.system(.caption2, design: .monospaced))
        .foregroundStyle(theme.quietText)
        .multilineTextAlignment(.trailing)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(theme.itemPadding)
    .operatorInset(theme)
  }

  private var calloutContent: some View {
    VStack(alignment: .leading, spacing: 8) {
      EventMetaLine(
        theme: theme, title: presentation.title, metadata: presentation.metadata, tint: markerTint)
      Text(presentation.detail)
        .font(.body)
        .foregroundStyle(theme.bodyText)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(theme.itemPadding)
    .background(
      markerTint.opacity(0.09),
      in: RoundedRectangle(cornerRadius: theme.itemCornerRadius, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: theme.itemCornerRadius, style: .continuous)
        .stroke(markerTint.opacity(0.16), lineWidth: 1)
    )
  }

  private var supplementalContent: some View {
    VStack(alignment: .leading, spacing: 8) {
      EventMetaLine(theme: theme, title: presentation.title, metadata: presentation.metadata)
      Text(presentation.detail)
        .font(.subheadline.weight(.medium))
        .foregroundStyle(theme.subduedText)
        .fixedSize(horizontal: false, vertical: true)

      if presentation.showsRawJSON {
        Text(event.rawJSON)
          .font(.system(.caption, design: .monospaced))
          .foregroundStyle(theme.quietText)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
          .padding(theme.itemPadding)
          .operatorInset(theme)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(theme.itemPadding)
    .operatorInset(theme)
  }
}

private struct TimelineMarker: View {
  let theme: OperatorTheme
  let rowStyle: SymphonyEventPresentation.RowStyle
  let tint: Color
  let isLast: Bool

  var body: some View {
    VStack(spacing: 0) {
      if rowStyle == .tool {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
          .fill(tint)
          .frame(width: 8, height: 8)
      } else if rowStyle == .callout {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .fill(tint)
          .frame(width: 7, height: 7)
      } else {
        Circle()
          .fill(tint)
          .frame(width: 7, height: 7)
      }

      Rectangle()
        .fill(theme.timeline)
        .frame(width: 1)
        .frame(maxHeight: .infinity)
        .opacity(isLast ? 0 : 1)
    }
    .frame(width: 12)
    .padding(.top, 4)
  }
}

private struct EventMetaLine: View {
  let theme: OperatorTheme
  let title: String
  let metadata: String
  var tint: Color = .secondary

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      EventTag(theme: theme, text: title, tint: tint)
      Text(metadata)
        .font(.system(.caption2, design: .monospaced))
        .foregroundStyle(theme.quietText)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct EventTag: View {
  let theme: OperatorTheme
  let text: String
  let tint: Color

  var body: some View {
    Text(text)
      .font(.caption2.weight(.medium))
      .padding(.horizontal, 7)
      .padding(.vertical, 3)
      .background(theme.badgeFill, in: Capsule())
      .foregroundStyle(tint)
      .overlay(
        Capsule()
          .stroke(theme.badgeBorder, lineWidth: 1)
      )
  }
}

private struct StatePill: View {
  let theme: OperatorTheme
  let text: String
  let tint: Color

  var body: some View {
    Text(text)
      .font(.caption.weight(.medium))
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(tint.opacity(0.12), in: Capsule())
      .foregroundStyle(tint)
      .overlay(
        Capsule()
          .stroke(tint.opacity(0.18), lineWidth: 1)
      )
  }
}

private struct QuietBadge: View {
  let theme: OperatorTheme
  let text: String

  var body: some View {
    Text(text)
      .font(.caption.weight(.medium))
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(theme.badgeFill, in: Capsule())
      .foregroundStyle(theme.quietText)
      .overlay(
        Capsule()
          .stroke(theme.badgeBorder, lineWidth: 1)
      )
  }
}

private struct PriorityBadge: View {
  let theme: OperatorTheme
  let priority: Int

  var body: some View {
    Text("P\(priority)")
      .font(.caption.weight(.semibold))
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(theme.warningTint.opacity(0.11), in: Capsule())
      .foregroundStyle(theme.warningTint)
      .overlay(
        Capsule()
          .stroke(theme.warningTint.opacity(0.16), lineWidth: 1)
      )
  }
}

private struct ProviderBadge: View {
  let theme: OperatorTheme
  let label: String

  var body: some View {
    Text(label.replacingOccurrences(of: "_", with: " ").uppercased())
      .font(.caption2.weight(.semibold))
      .lineLimit(1)
      .fixedSize(horizontal: true, vertical: false)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(theme.accentTint.opacity(0.11), in: Capsule())
      .foregroundStyle(theme.accentTint)
      .overlay(
        Capsule()
          .stroke(theme.accentTint.opacity(0.18), lineWidth: 1)
      )
  }
}

private struct DetailLine: View {
  let label: String
  let value: String
  var monospaced: Bool = false

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(label)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      Text(value)
        .font(monospaced ? .system(.caption, design: .monospaced) : .caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .modifier(MonospacedSelectionModifier(enabled: monospaced))
    }
  }
}

private struct MonospacedSelectionModifier: ViewModifier {
  let enabled: Bool

  @ViewBuilder
  func body(content: Content) -> some View {
    if enabled {
      content.textSelection(.enabled)
    } else {
      content
    }
  }
}

struct OperatorMarkdownContent: Equatable {
  let attributedText: AttributedString
  let renderedWithMarkdown: Bool
}

enum OperatorMarkdownRenderer {
  typealias Parser = (String) throws -> AttributedString

  static func makeContent(
    from source: String,
    parser: Parser = parseNativeMarkdown
  ) -> OperatorMarkdownContent {
    do {
      return OperatorMarkdownContent(
        attributedText: try parser(source),
        renderedWithMarkdown: true
      )
    } catch {
      return OperatorMarkdownContent(
        attributedText: AttributedString(source),
        renderedWithMarkdown: false
      )
    }
  }

  static func parseNativeMarkdown(_ source: String) throws -> AttributedString {
    try AttributedString(markdown: source)
  }
}

private struct MarkdownMessageText: View {
  let theme: OperatorTheme
  let text: String

  private var renderedContent: OperatorMarkdownContent {
    OperatorMarkdownRenderer.makeContent(from: text)
  }

  var body: some View {
    Text(renderedContent.attributedText)
      .foregroundStyle(theme.bodyText)
      .tint(theme.accentTint)
      .lineSpacing(3)
      .fixedSize(horizontal: false, vertical: true)
      .textSelection(.enabled)
  }
}

private struct MetricsStrip: View {
  let theme: OperatorTheme
  let metrics: [(String, String)]

  var body: some View {
    HStack(spacing: 8) {
      ForEach(metrics, id: \.0) { metric in
        MetricChip(theme: theme, label: metric.0, value: metric.1)
      }
    }
  }
}

private struct TokenUsageStrip: View {
  let theme: OperatorTheme
  let tokens: TokenUsage

  var body: some View {
    HStack(spacing: 8) {
      if let input = tokens.inputTokens {
        MetricChip(theme: theme, label: "Input", value: input.formatted())
      }

      if let output = tokens.outputTokens {
        MetricChip(theme: theme, label: "Output", value: output.formatted())
      }

      if let total = tokens.totalTokens {
        MetricChip(theme: theme, label: "Total", value: total.formatted())
      }
    }
    .accessibilityIdentifier("token-usage")
  }
}

private struct MetricChip: View {
  let theme: OperatorTheme
  let label: String
  let value: String

  var body: some View {
    HStack(spacing: 4) {
      Text(label)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
      Text(value)
        .font(.caption.weight(.medium))
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(
      theme.badgeFill,
      in: RoundedRectangle(cornerRadius: 8, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(theme.badgeBorder, lineWidth: 1)
    )
  }
}

private struct EmptyStatePanel: View {
  let theme: OperatorTheme
  let systemImage: String
  let title: String
  var detail: String? = nil

  var body: some View {
    VStack(spacing: 8) {
      Image(systemName: systemImage)
        .font(.title2)
        .foregroundStyle(theme.quietText)
      Text(title)
        .font(.subheadline.weight(.medium))
        .foregroundStyle(theme.quietText)
      if let detail {
        Text(detail)
          .font(.caption)
          .foregroundStyle(theme.subduedText)
          .multilineTextAlignment(.center)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, theme.compact ? 18 : 24)
    .operatorPanel(theme)
  }
}

private struct LoadingStatePanel: View {
  let theme: OperatorTheme
  let systemImage: String
  let title: String

  var body: some View {
    VStack(spacing: 8) {
      ProgressView()
      Image(systemName: systemImage)
        .font(.title3)
        .foregroundStyle(theme.quietText)
      Text(title)
        .font(.subheadline)
        .foregroundStyle(theme.quietText)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, theme.compact ? 18 : 24)
    .operatorPanel(theme)
  }
}

extension View {
  fileprivate func operatorPanel(_ theme: OperatorTheme) -> some View {
    self
      .padding(theme.panelPadding)
      .background(
        theme.panelFill,
        in: RoundedRectangle(cornerRadius: theme.panelCornerRadius, style: .continuous)
      )
      .overlay(
        RoundedRectangle(cornerRadius: theme.panelCornerRadius, style: .continuous)
          .stroke(theme.panelBorder, lineWidth: 1)
      )
  }

  fileprivate func operatorInset(_ theme: OperatorTheme) -> some View {
    self
      .background(
        theme.insetFill,
        in: RoundedRectangle(cornerRadius: theme.itemCornerRadius, style: .continuous)
      )
      .overlay(
        RoundedRectangle(cornerRadius: theme.itemCornerRadius, style: .continuous)
          .stroke(theme.panelBorder.opacity(0.72), lineWidth: 1)
      )
  }
}

func formatTimestamp(_ isoString: String) -> String {
  let formatter = ISO8601DateFormatter()
  guard let date = formatter.date(from: isoString) else { return isoString }
  let relative = RelativeDateTimeFormatter()
  relative.unitsStyle = .abbreviated
  return relative.localizedString(for: date, relativeTo: Date())
}

func formatState(_ state: String) -> String {
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

func statusTint(_ state: String) -> Color {
  let normalized = state.lowercased()
  let errorTint = Color(red: 0.812, green: 0.498, blue: 0.498)
  let warningTint = Color(red: 0.786, green: 0.639, blue: 0.437)
  let successTint = Color(red: 0.492, green: 0.725, blue: 0.576)
  let activeTint = Color(red: 0.541, green: 0.655, blue: 0.812)
  let neutralTint = Color(red: 0.655, green: 0.667, blue: 0.694)

  if normalized.contains("error") || normalized.contains("fail") {
    return errorTint
  }
  if normalized.contains("approve") || normalized.contains("queue") || normalized.contains("wait")
    || normalized.contains("backlog") || normalized.contains("pending")
  {
    return warningTint
  }
  if normalized.contains("done") || normalized.contains("success") || normalized.contains("ready")
    || normalized.contains("complete") || normalized.contains("ended")
  {
    return successTint
  }
  if normalized.contains("live") || normalized.contains("run") || normalized.contains("active")
    || normalized.contains("progress") || normalized.contains("stream")
  {
    return activeTint
  }
  return neutralTint
}

private func liveStatusTint(_ status: String) -> Color {
  statusTint(status)
}

#if DEBUG
  #Preview {
    SymphonyOperatorRootView(model: SymphonyOperatorModel())
  }
#endif
