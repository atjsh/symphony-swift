import SwiftUI
import SymphonyShared

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

        if OperatorDetailSummaryView.runOverviewShowsLastEvent(compact: theme.compact),
          let lastAgentEventType = runDetail.lastAgentEventType
        {
          DetailLine(compact: theme.compact, label: "Last event", value: lastAgentEventType)
            .accessibilityIdentifier("run-last-event-type")
        }

        if let endedAt = runDetail.endedAt {
          DetailLine(compact: theme.compact, label: "Ended", value: formatTimestamp(endedAt))
            .accessibilityIdentifier("run-ended-at")
        }
      }

      if OperatorDetailSummaryView.runOverviewShowsLatestMessage(compact: theme.compact),
        let lastAgentMessage = runDetail.lastAgentMessage
      {
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
