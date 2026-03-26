import SwiftUI
import SymphonyShared

struct OperatorDetailView: View {
  @ObservedObject var model: SymphonyOperatorModel
  let theme: OperatorTheme
  let selectRun: (RunID) -> Void

  var body: some View {
    Group {
      if model.selectedIssueID == nil {
        ContentUnavailableView {
          Label("No Issue Selected", systemImage: "sidebar.left")
        } description: {
          Text(
            "Choose an issue from the sidebar to inspect orchestration state, runs, sessions, and logs."
          )
        }
      } else if let detail = model.issueDetail {
        VStack(alignment: .leading, spacing: theme.sectionSpacing) {
          OperatorDetailSummaryView(
            model: model,
            theme: theme,
            detail: detail,
            selectRun: selectRun
          )
          .accessibilityIdentifier("detail-summary")

          OperatorDetailTabBar(theme: theme, selection: $model.selectedDetailTab)

          currentTabContent(detail: detail)
        }
        .padding(theme.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      } else {
        LoadingStatePanel(
          theme: theme,
          systemImage: "arrow.triangle.2.circlepath",
          title: "Loading issue details…"
        )
      }
    }
    .navigationTitle(model.issueDetail?.issue.identifier.rawValue ?? "Inspector")
  }

  @ViewBuilder
  private func currentTabContent(detail: IssueDetail) -> some View {
    switch model.selectedDetailTab {
    case .overview:
      ScrollView {
        VStack(alignment: .leading, spacing: theme.sectionSpacing) {
          IssueOverviewPanel(
            theme: theme,
            detail: detail,
            latestRunSelected: detail.latestRun?.runID == model.selectedRunID,
            runSelectionAction: makeIssueOverviewRunSelectionAction(
              latestRun: detail.latestRun,
              selectRun: selectRun
            ),
            compact: theme.compact
          )
          .accessibilityIdentifier("issue-detail-section")

          if let runDetail = model.runDetail {
            RunOverviewPanel(theme: theme, runDetail: runDetail)
              .accessibilityIdentifier("run-detail-section")
          } else {
            EmptyStatePanel(
              theme: theme,
              systemImage: "play.circle",
              title: "No Run Selected",
              detail: "Select a run to inspect the latest attempt and its results."
            )
            .accessibilityIdentifier("run-detail-section")
          }
        }
      }
    case .sessions:
      ScrollView {
        if detail.recentSessions.isEmpty {
          EmptyStatePanel(
            theme: theme,
            systemImage: "person.2",
            title: "No Recent Sessions",
            detail: "Session history will appear here after the provider has started work."
          )
        } else {
          RecentSessionsPanel(theme: theme, sessions: detail.recentSessions)
        }
      }
    case .logs:
      OperatorLogsPane(model: model, theme: theme)
    }
  }
}

private struct OperatorDetailSummaryView: View {
  @ObservedObject var model: SymphonyOperatorModel
  let theme: OperatorTheme
  let detail: IssueDetail
  let selectRun: (RunID) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: theme.blockSpacing) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 8) {
          Text(detail.issue.identifier.rawValue)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)

          Text(detail.issue.title)
            .font(.title2)
            .bold()
            .fixedSize(horizontal: false, vertical: true)

          HStack(spacing: 6) {
            StatePill(
              theme: theme, text: formatState(detail.issue.state),
              tint: statusTint(detail.issue.state))
            QuietBadge(theme: theme, text: detail.issue.issueState)
            if let priority = detail.issue.priority {
              PriorityBadge(theme: theme, priority: priority)
            }
            StatePill(theme: theme, text: model.liveStatus, tint: statusTint(model.liveStatus))
          }
        }

        Spacer(minLength: 16)

        if detail.latestRun != nil {
          Button(
            "Latest Run",
            systemImage: "play.rectangle.on.rectangle",
            action: makeOperatorSelectLatestRunAction(detail: detail, selectRun: selectRun)
          )
          .buttonStyle(.glass)
          .accessibilityIdentifier("latest-run-button")
        }
      }

      if let description = detail.issue.description, !description.isEmpty {
        Text(description)
          .font(.body)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .operatorPanel(theme)
  }
}

private struct OperatorDetailTabBar: View {
  let theme: OperatorTheme
  @Binding var selection: OperatorDetailTab

  var body: some View {
    GlassEffectContainer(spacing: 10) {
      HStack(spacing: 10) {
        ForEach(OperatorDetailTab.allCases, id: \.rawValue) { tab in
          tabButton(for: tab)
        }
      }
    }
  }

  @ViewBuilder
  private func tabButton(for tab: OperatorDetailTab) -> some View {
    if selection == tab {
      Button(
        tab.title,
        systemImage: tab.systemImage,
        action: makeOperatorDetailTabAction(selection: $selection, tab: tab)
      )
      .buttonStyle(.glassProminent)
      .accessibilityIdentifier("detail-tab-\(tab.rawValue)")
    } else {
      Button(
        tab.title,
        systemImage: tab.systemImage,
        action: makeOperatorDetailTabAction(selection: $selection, tab: tab)
      )
      .buttonStyle(.glass)
      .accessibilityIdentifier("detail-tab-\(tab.rawValue)")
    }
  }
}

@MainActor
func operatorSelectLatestRun(detail: IssueDetail, selectRun: (RunID) -> Void) {
  guard let latestRun = detail.latestRun else {
    return
  }

  selectRun(latestRun.runID)
}

@MainActor
func makeOperatorSelectLatestRunAction(detail: IssueDetail, selectRun: @escaping (RunID) -> Void)
  -> () -> Void
{
  {
    operatorSelectLatestRun(detail: detail, selectRun: selectRun)
  }
}

@MainActor
func operatorSetDetailTab(selection: Binding<OperatorDetailTab>, tab: OperatorDetailTab) {
  selection.wrappedValue = tab
}

@MainActor
func makeOperatorDetailTabAction(
  selection: Binding<OperatorDetailTab>,
  tab: OperatorDetailTab
) -> () -> Void {
  {
    operatorSetDetailTab(selection: selection, tab: tab)
  }
}

@MainActor
func makeIssueOverviewRunSelectionAction(
  latestRun: RunSummary?,
  selectRun: @escaping (RunID) -> Void
) -> (() -> Void)? {
  guard let latestRun else {
    return nil
  }

  return {
    selectRun(latestRun.runID)
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
      SectionHeader(title: "Issue Overview")

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
            .font(.caption)
            .bold()
            .foregroundStyle(.secondary)

          ForEach(detail.issue.blockedBy, id: \.issueID.rawValue) { blocker in
            HStack(spacing: 8) {
              Text(blocker.identifier.rawValue)
                .font(.caption.monospaced())
              StatePill(
                theme: theme, text: formatState(blocker.state), tint: statusTint(blocker.state))
            }
          }
        }
      }
    }
    .operatorPanel(theme)
  }
}

struct RecentSessionsPanel: View {
  let theme: OperatorTheme
  let sessions: [AgentSession]

  var body: some View {
    VStack(alignment: .leading, spacing: theme.blockSpacing) {
      SectionHeader(title: "Recent Sessions")

      ForEach(sessions, id: \.sessionID.rawValue) { session in
        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 8) {
            ProviderBadge(theme: theme, label: session.provider)
            Text(formatState(session.status))
              .font(.subheadline)
              .bold()

            Spacer()

            Text("\(session.turnCount) turns")
              .font(.caption)
              .foregroundStyle(.secondary)
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
              .font(.caption.monospaced())
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
              .padding(theme.itemPadding)
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

struct RunOverviewPanel: View {
  let theme: OperatorTheme
  let runDetail: RunDetail

  var body: some View {
    VStack(alignment: .leading, spacing: theme.blockSpacing) {
      SectionHeader(title: "Run Overview")

      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 8) {
          Text(runDetail.runID.rawValue)
            .font(.headline.monospaced())

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
            .font(.caption)
            .bold()
            .foregroundStyle(.secondary)
          MarkdownMessageText(theme: theme, text: lastAgentMessage)
            .padding(theme.itemPadding)
            .operatorInset(theme)
        }
        .accessibilityIdentifier("run-last-message")
      }

      if let lastError = runDetail.lastError {
        VStack(alignment: .leading, spacing: 6) {
          Text("Last Error")
            .font(.caption)
            .bold()
            .foregroundStyle(.red)
          Text(lastError)
            .font(.body)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .padding(theme.itemPadding)
            .background(
              .red.opacity(0.08), in: RoundedRectangle(cornerRadius: theme.itemCornerRadius))
        }
        .accessibilityIdentifier("run-last-error")
      }
    }
    .operatorPanel(theme)
  }
}
