import SwiftUI
import SymphonyShared

struct OperatorDetailView: View {
  @ObservedObject var model: SymphonyOperatorModel
  let theme: OperatorTheme
  let selectRun: (RunID) -> Void

  var body: some View {
    Group {
      if model.selectedIssueID == nil {
        VStack(spacing: theme.blockSpacing) {
          Image(systemName: "sidebar.left")
            .font(.system(size: 36, weight: .semibold))
            .foregroundStyle(theme.quietText)

          Text("No Issue Selected")
            .font(theme.summaryTitleFont)
            .foregroundStyle(theme.bodyText)

          Text(
            "Choose an issue from the sidebar to inspect orchestration state, runs, sessions, and logs."
          )
          .font(.body)
          .foregroundStyle(theme.bodyText)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let detail = model.issueDetail {
        VStack(alignment: .leading, spacing: theme.sectionSpacing) {
          OperatorDetailSummaryView(
            model: model,
            theme: theme,
            detail: detail,
            selectRun: selectRun
          )

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
    .operatorDetailTitleDisplayPreference(
      operatorDetailNavigationTitleDisplayPreference(isCompact: theme.compact)
    )
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

          if let runDetail = model.runDetail {
            RunOverviewPanel(theme: theme, runDetail: runDetail)
          } else {
            EmptyStatePanel(
              theme: theme,
              systemImage: "play.circle",
              title: "No Run Selected",
              detail: "Select a run to inspect the latest attempt and its results."
            )
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

  private var detailIdentifierDisplayText: String {
    detail.issue.identifier.rawValue
      .replacingOccurrences(of: "/", with: "/\u{200B}")
      .replacingOccurrences(of: "#", with: "\u{200B}#")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: theme.blockSpacing) {
      if operatorSummaryActionPlacement(isCompact: theme.compact) == .trailing {
        HStack(alignment: .top, spacing: 12) {
          summaryTextBlock

          Spacer(minLength: 16)

          latestRunButton
        }
      } else {
        VStack(alignment: .leading, spacing: theme.blockSpacing) {
          summaryTextBlock
          latestRunButton
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

  private var summaryTextBlock: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(verbatim: detailIdentifierDisplayText)
        .font(.caption.monospaced())
        .foregroundStyle(theme.bodyText)
        .lineLimit(2)
        .minimumScaleFactor(0.75)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel(detail.issue.identifier.rawValue)

      Text(detail.issue.title)
        .font(theme.summaryTitleFont)
        .fixedSize(horizontal: false, vertical: true)

      OperatorFlowLayout(spacing: 6, rowSpacing: 6) {
        StatePill(
          theme: theme,
          text: formatState(detail.issue.state),
          tint: statusTint(detail.issue.state)
        )
        QuietBadge(theme: theme, text: detail.issue.issueState)
        if let priority = detail.issue.priority {
          PriorityBadge(theme: theme, priority: priority)
        }
        StatePill(theme: theme, text: model.liveStatus, tint: statusTint(model.liveStatus))
      }
    }
  }

  @ViewBuilder
  private var latestRunButton: some View {
    if detail.latestRun != nil {
      Button(
        "Latest Run",
        systemImage: "play.rectangle.on.rectangle",
        action: makeOperatorSelectLatestRunAction(detail: detail, selectRun: selectRun)
      )
      .lineLimit(1)
      .fixedSize(horizontal: true, vertical: false)
      .frame(minHeight: 44)
      .buttonStyle(.glass)
      .accessibilityIdentifier("latest-run-button")
    }
  }
}

private struct OperatorDetailTabBar: View {
  let theme: OperatorTheme
  @Binding var selection: OperatorDetailTab

  var body: some View {
    if operatorChoiceControlPresentation(isCompact: theme.compact) == .glassBar {
      GlassEffectContainer(spacing: theme.controlSpacing) {
        ForEach(OperatorDetailTab.allCases, id: \.rawValue) { tab in
          tabButton(for: tab)
        }
      }
    } else {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: theme.controlSpacing) {
          ForEach(OperatorDetailTab.allCases, id: \.rawValue) { tab in
            tabButton(for: tab)
          }
        }
        .padding(.vertical, 2)
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
      .lineLimit(1)
      .fixedSize(horizontal: true, vertical: false)
      .frame(minHeight: 44)
      .buttonStyle(.glass)
      .background(theme.selectedFill, in: Capsule())
      .overlay(
        Capsule()
          .strokeBorder(theme.selectedStroke, lineWidth: 1.5)
      )
      .accessibilityIdentifier("detail-tab-\(tab.rawValue)")
    } else {
      Button(
        tab.title,
        systemImage: tab.systemImage,
        action: makeOperatorDetailTabAction(selection: $selection, tab: tab)
      )
      .lineLimit(1)
      .fixedSize(horizontal: true, vertical: false)
      .frame(minHeight: 44)
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
      SectionHeader(theme: theme, title: "Issue Overview")

      if !detail.issue.labels.isEmpty {
        OperatorFlowLayout(spacing: 6, rowSpacing: 6) {
          ForEach(detail.issue.labels, id: \.self) { label in
            QuietBadge(theme: theme, text: label)
          }
        }
      }

      VStack(alignment: .leading, spacing: 10) {
        if let createdAt = detail.issue.createdAt {
          DetailLine(compact: compact, label: "Created", value: formatTimestamp(createdAt))
        }

        if let updatedAt = detail.issue.updatedAt {
          DetailLine(compact: compact, label: "Updated", value: formatTimestamp(updatedAt))
        }

        if let workspacePath = detail.workspacePath {
          DetailLine(
            compact: compact,
            label: "Workspace",
            value: workspacePath,
            monospaced: true
          )
        }
      }

      if !detail.issue.blockedBy.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Text("Blocked By")
            .font(.caption)
            .bold()
            .foregroundStyle(.secondary)

          ForEach(detail.issue.blockedBy, id: \.issueID.rawValue) { blocker in
            OperatorFlowLayout(spacing: 8, rowSpacing: 6) {
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
      SectionHeader(theme: theme, title: "Recent Sessions")

      ForEach(sessions, id: \.sessionID.rawValue) { session in
        VStack(alignment: .leading, spacing: 8) {
          if theme.compact {
            VStack(alignment: .leading, spacing: 6) {
              ProviderBadge(theme: theme, label: session.provider)
              HStack(spacing: 8) {
                Text(formatState(session.status))
                  .font(.subheadline)
                  .bold()
                Spacer()
                Text("\(session.turnCount) turns")
                  .font(.footnote.weight(.medium))
                  .foregroundStyle(Color.primary)
              }
            }
          } else {
            HStack(spacing: 8) {
              ProviderBadge(theme: theme, label: session.provider)
              Text(formatState(session.status))
                .font(.subheadline)
                .bold()

              Spacer()

              Text("\(session.turnCount) turns")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.primary)
            }
          }

          DetailLine(
            compact: theme.compact, label: "Session", value: session.sessionID.rawValue,
            monospaced: true)

          if let providerSessionID = session.providerSessionID {
            DetailLine(
              compact: theme.compact, label: "Provider session", value: providerSessionID,
              monospaced: true)
          }

          if let providerThreadID = session.providerThreadID {
            DetailLine(
              compact: theme.compact, label: "Thread", value: providerThreadID, monospaced: true)
          }

          if let providerTurnID = session.providerTurnID {
            DetailLine(
              compact: theme.compact, label: "Turn", value: providerTurnID, monospaced: true)
          }

          if let providerRunID = session.providerRunID {
            DetailLine(compact: theme.compact, label: "Run", value: providerRunID, monospaced: true)
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
      SectionHeader(theme: theme, title: "Run Overview")

      if theme.compact {
        VStack(alignment: .leading, spacing: 8) {
          Text(runDetail.runID.rawValue)
            .font(.headline.monospaced())

          OperatorFlowLayout(spacing: 6, rowSpacing: 6) {
            StatePill(
              theme: theme, text: formatState(runDetail.status), tint: statusTint(runDetail.status))
            QuietBadge(theme: theme, text: "Attempt \(runDetail.attempt)")
            ProviderBadge(theme: theme, label: runDetail.provider)
          }
        }
      } else {
        HStack(alignment: .top, spacing: 12) {
          VStack(alignment: .leading, spacing: 8) {
            Text(runDetail.runID.rawValue)
              .font(.headline.monospaced())

            OperatorFlowLayout(spacing: 6, rowSpacing: 6) {
              StatePill(
                theme: theme, text: formatState(runDetail.status),
                tint: statusTint(runDetail.status))
              QuietBadge(theme: theme, text: "Attempt \(runDetail.attempt)")
            }
          }

          Spacer(minLength: 12)

          ProviderBadge(theme: theme, label: runDetail.provider)
        }
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
          DetailLine(
            compact: theme.compact, label: "Provider session", value: providerSessionID,
            monospaced: true)
        }

        if let providerRunID = runDetail.providerRunID {
          DetailLine(
            compact: theme.compact, label: "Provider run", value: providerRunID, monospaced: true)
        }

        if let lastAgentEventType = runDetail.lastAgentEventType {
          DetailLine(compact: theme.compact, label: "Last event", value: lastAgentEventType)
            .accessibilityIdentifier("run-last-event-type")
        }

        if let endedAt = runDetail.endedAt {
          DetailLine(compact: theme.compact, label: "Ended", value: formatTimestamp(endedAt))
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

extension View {
  @ViewBuilder
  fileprivate func operatorDetailTitleDisplayPreference(
    _ preference: OperatorDetailNavigationTitleDisplayPreference
  ) -> some View {
    #if os(iOS)
      switch preference {
      case .automatic:
        navigationBarTitleDisplayMode(.automatic)
      case .inline:
        navigationBarTitleDisplayMode(.inline)
      }
    #else
      self
    #endif
  }
}
