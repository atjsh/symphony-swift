import SwiftUI
import SymphonyShared

struct OperatorSidebarView: View {
  @ObservedObject var model: SymphonyOperatorModel
  let theme: OperatorTheme
  let openServerEditor: () -> Void
  let selectIssue: (IssueSummary) -> Void

  private var issueSelection: Binding<IssueID?> {
    operatorSidebarIssueSelectionBinding(model: model, selectIssue: selectIssue)
  }

  private var issueList: some View {
    List(selection: issueSelection) {
      ForEach(model.filteredIssues, id: \.issueID.rawValue) { issue in
        Button(
          action: makeOperatorSidebarSelectIssueAction(
            issueID: issue.issueID,
            model: model,
            selectIssue: selectIssue
          )
        ) {
          IssueSidebarRow(
            theme: theme,
            issue: issue,
            isSelected: issue.issueID == model.selectedIssueID
          )
        }
        .buttonStyle(.plain)
        .tag(Optional(issue.issueID))
        .accessibilityIdentifier("issue-row-\(issue.issueID.rawValue)")
      }
    }
    .accessibilityIdentifier("issue-list")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: theme.sectionSpacing) {
      TextField("Filter Issues", text: $model.issueSearchText)
        .font(.body)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white.opacity(0.96))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(theme.insetStroke, lineWidth: 1)
        )
        .accessibilityIdentifier("sidebar-search")

      OperatorServerStatusSummaryView(
        theme: theme,
        health: model.health,
        connectionError: model.connectionError,
        host: model.host,
        portText: model.portText,
        openServerEditor: openServerEditor
      )

      if theme.compact {
        issueList
          .listStyle(.plain)
          .scrollContentBackground(.hidden)
      } else {
        issueList
          .listStyle(.sidebar)
      }
    }
    .padding(theme.pagePadding)
    .navigationTitle("Symphony")
    .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 380)
  }
}

@MainActor
func operatorSidebarSelectIssue(
  _ newSelection: IssueID?,
  model: SymphonyOperatorModel,
  selectIssue: (IssueSummary) -> Void
) {
  guard let newSelection,
    let summary = model.issues.first(where: { $0.issueID == newSelection }),
    newSelection != model.selectedIssueID || model.issueDetail == nil
  else {
    return
  }

  selectIssue(summary)
}

@MainActor
func makeOperatorSidebarSelectIssueAction(
  issueID: IssueID,
  model: SymphonyOperatorModel,
  selectIssue: @escaping (IssueSummary) -> Void
) -> () -> Void {
  {
    operatorSidebarSelectIssue(issueID, model: model, selectIssue: selectIssue)
  }
}

@MainActor
func operatorSidebarIssueSelectionBinding(
  model: SymphonyOperatorModel,
  selectIssue: @escaping (IssueSummary) -> Void
) -> Binding<IssueID?> {
  Binding(
    get: { model.selectedIssueID },
    set: { newSelection in
      operatorSidebarSelectIssue(newSelection, model: model, selectIssue: selectIssue)
    }
  )
}

@MainActor
func makeOperatorServerStatusSummaryView(
  theme: OperatorTheme,
  health: HealthResponse?,
  connectionError: String?,
  host: String,
  portText: String,
  openServerEditor: @escaping () -> Void
) -> some View {
  OperatorServerStatusSummaryView(
    theme: theme,
    health: health,
    connectionError: connectionError,
    host: host,
    portText: portText,
    openServerEditor: openServerEditor
  )
}

@MainActor
func makeOperatorIssueSidebarRow(theme: OperatorTheme, issue: IssueSummary, isSelected: Bool)
  -> some View
{
  IssueSidebarRow(theme: theme, issue: issue, isSelected: isSelected)
}

private struct OperatorServerStatusSummaryView: View {
  let theme: OperatorTheme
  let health: HealthResponse?
  let connectionError: String?
  let host: String
  let portText: String
  let openServerEditor: () -> Void

  @ViewBuilder
  private var serverActionLabel: some View {
    Text("Server")
      .font(.body.weight(.semibold))
  }

  private var statusText: String {
    if let health {
      if theme.compact {
        return health.trackerKind.capitalized
      }
      return "Connected to \(health.trackerKind.capitalized)"
    }
    if connectionError != nil {
      return "Connection failed"
    }
    return "Not connected"
  }

  private var statusDetail: String {
    if let connectionError {
      return connectionError
    }
    return "\(host):\(portText)"
  }

  private var statusAccessibilityText: String {
    if let health {
      return "Connected to \(health.trackerKind.capitalized)"
    }
    if connectionError != nil {
      return "Connection failed"
    }
    return "Not connected"
  }

  private var statusColor: Color {
    if health != nil {
      theme.successTint
    } else if connectionError != nil {
      theme.errorTint
    } else {
      theme.warningTint
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: theme.blockSpacing) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: health != nil ? "server.rack" : "bolt.horizontal.circle")
          .font(.title3)
          .foregroundStyle(statusColor)
          .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: 4) {
          Text(statusText)
            .font(.headline)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
            .accessibilityLabel(statusAccessibilityText)
          Text(statusDetail)
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color.primary)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
        }
      }

      Button(action: openServerEditor) {
        serverActionLabel
          .foregroundStyle(theme.bodyText)
          .lineLimit(2)
          .minimumScaleFactor(0.8)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
        .buttonStyle(.borderless)
        .accessibilityLabel("Configure Server")
        .accessibilityIdentifier("server-editor-summary-button")
    }
    .operatorPanel(theme)
  }
}

private struct IssueSidebarRow: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  let theme: OperatorTheme
  let issue: IssueSummary
  let isSelected: Bool

  private var metadataPlacement: OperatorIssueRowMetadataPlacement {
    operatorIssueRowMetadataPlacement(
      isCompact: theme.compact,
      prefersAccessibilityLayout: dynamicTypeSize.isAccessibilitySize
    )
  }

  private var issueIdentifierDisplayText: String {
    issue.identifier.rawValue
      .replacingOccurrences(of: "/", with: "/\u{200B}")
      .replacingOccurrences(of: "#", with: "\u{200B}#")
  }

  private var issueIdentifierLabel: some View {
    Text(verbatim: issueIdentifierDisplayText)
      .font(.caption.monospaced())
      .foregroundStyle(.secondary)
      .lineLimit(2)
      .minimumScaleFactor(0.75)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityLabel(issue.identifier.rawValue)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if metadataPlacement == .trailing {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          issueIdentifierLabel

          Spacer(minLength: 12)

          if let provider = issue.currentProvider {
            ProviderBadge(theme: theme, label: provider)
          }
        }
      } else {
        VStack(alignment: .leading, spacing: 6) {
          issueIdentifierLabel

          if let provider = issue.currentProvider {
            ProviderBadge(theme: theme, label: provider)
          }
        }
      }

      Text(issue.title)
        .font(.body)
        .lineLimit(3)
        .minimumScaleFactor(0.85)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)

      OperatorFlowLayout(spacing: 6, rowSpacing: 6) {
        StatePill(theme: theme, text: formatState(issue.state), tint: statusTint(issue.state))
        QuietBadge(theme: theme, text: issue.issueState)
        if let priority = issue.priority {
          PriorityBadge(theme: theme, priority: priority)
        }
      }
    }
    .padding(.vertical, 4)
    .padding(.horizontal, 2)
    .contentShape(Rectangle())
    .operatorSelectionBackground(theme, isSelected: isSelected)
  }
}
