import SwiftUI
import SymphonyShared

struct OperatorSidebarView: View {
  @ObservedObject var model: SymphonyOperatorModel
  let theme: OperatorTheme
  let openLocalServerEditor: () -> Void
  let openExistingServerEditor: () -> Void
  let selectIssue: (IssueSummary) -> Void

  init(
    model: SymphonyOperatorModel,
    theme: OperatorTheme,
    openLocalServerEditor: @escaping () -> Void,
    openExistingServerEditor: @escaping () -> Void,
    selectIssue: @escaping (IssueSummary) -> Void
  ) {
    self.model = model
    self.theme = theme
    self.openLocalServerEditor = openLocalServerEditor
    self.openExistingServerEditor = openExistingServerEditor
    self.selectIssue = selectIssue
  }

  init(
    model: SymphonyOperatorModel,
    theme: OperatorTheme,
    openServerEditor: @escaping () -> Void,
    selectIssue: @escaping (IssueSummary) -> Void
  ) {
    self.init(
      model: model,
      theme: theme,
      openLocalServerEditor: openServerEditor,
      openExistingServerEditor: openServerEditor,
      selectIssue: selectIssue
    )
  }

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
    #if os(macOS)
      .environment(\.defaultMinListRowHeight, 60)
    #endif
    .accessibilityIdentifier("issue-list")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: theme.sectionSpacing) {
      OperatorServerStatusSummaryView(
        theme: theme,
        model: model,
        health: model.health,
        connectionError: model.connectionError,
        host: model.host,
        portText: model.portText,
        openLocalServerEditor: openLocalServerEditor,
        openExistingServerEditor: openExistingServerEditor
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
  model: SymphonyOperatorModel,
  health: HealthResponse?,
  connectionError: String?,
  host: String,
  portText: String,
  openLocalServerEditor: @escaping () -> Void,
  openExistingServerEditor: @escaping () -> Void
) -> some View {
  OperatorServerStatusSummaryView(
    theme: theme,
    model: model,
    health: health,
    connectionError: connectionError,
    host: host,
    portText: portText,
    openLocalServerEditor: openLocalServerEditor,
    openExistingServerEditor: openExistingServerEditor
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
  @ObservedObject var model: SymphonyOperatorModel
  let health: HealthResponse?
  let connectionError: String?
  let host: String
  let portText: String
  let openLocalServerEditor: () -> Void
  let openExistingServerEditor: () -> Void

  @ViewBuilder
  private var serverActionLabel: some View {
    #if os(macOS)
      if model.hasLocalServerSupport && health == nil {
        Text("Start Local Server")
          .font(.body.weight(.semibold))
      } else {
        Text("Server")
          .font(.body.weight(.semibold))
      }
    #else
      Text("Server")
        .font(.body.weight(.semibold))
    #endif
  }

  private var statusText: String {
    if let health {
      if theme.compact {
        return health.trackerKind.capitalized
      }
      return "Connected to \(health.trackerKind.capitalized)"
    }
    #if os(macOS)
      if model.hasLocalServerSupport {
        switch model.localServerLaunchState {
        case .validating:
          return "Validating local setup"
        case .starting:
          return "Starting local server"
        case .waitingForHealth:
          return "Waiting for health"
        case .running:
          return "Local server running"
        case .failed:
          return "Local server failed"
        case .needsSetup:
          return "Local setup required"
        case .idle:
          break
        }
      }
    #endif
    if connectionError != nil {
      return "Connection failed"
    }
    return "Not connected"
  }

  private var statusDetail: String {
    #if os(macOS)
      if let localServerFailure = model.localServerFailure, health == nil {
        return localServerFailure
      }
      if model.hasLocalServerSupport,
        health == nil,
        !model.localServerWorkflowPath.isEmpty
      {
        return model.localServerWorkflowPath
      }
    #endif
    if let connectionError {
      return connectionError
    }
    return "\(host):\(portText)"
  }

  private var statusAccessibilityText: String {
    if let health {
      return "Connected to \(health.trackerKind.capitalized)"
    }
    #if os(macOS)
      if model.hasLocalServerSupport {
        return statusText
      }
    #endif
    if connectionError != nil {
      return "Connection failed"
    }
    return "Not connected"
  }

  private var statusColor: Color {
    if health != nil {
      return theme.successTint
    }

    #if os(macOS)
      if model.hasLocalServerSupport && model.localServerLaunchState == .running {
        return theme.successTint
      }
      if model.hasLocalServerSupport
        && (model.localServerLaunchState == .starting
          || model.localServerLaunchState == .waitingForHealth
          || model.localServerLaunchState == .validating)
      {
        return theme.warningTint
      }
      if model.hasLocalServerSupport && model.localServerLaunchState == .failed {
        return theme.errorTint
      }
    #endif

    if connectionError != nil {
      return theme.errorTint
    }
    return theme.warningTint
  }

  private var primaryServerEditorAction: () -> Void {
    #if os(macOS)
      if model.hasLocalServerSupport && health == nil {
        return openLocalServerEditor
      }
    #endif
    return openExistingServerEditor
  }

  var body: some View {
    VStack(alignment: .leading, spacing: theme.blockSpacing) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: health != nil ? "server.rack" : "bolt.horizontal.circle")
          .font(.title3.weight(.semibold))
          .foregroundStyle(statusColor)
          .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: 4) {
          Text(statusText)
            .font(.headline)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
          Text(statusDetail)
            .font(.footnote)
            .foregroundStyle(theme.quietText)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
        }
      }
      .accessibilityElement(children: .combine)
      .accessibilityAddTraits(.isStaticText)
      .accessibilityLabel(statusAccessibilityText)
      .accessibilityValue(statusDetail)

      Divider()

      Button(action: primaryServerEditorAction) {
        serverActionLabel
          .foregroundStyle(theme.bodyText)
          .frame(maxWidth: .infinity)
      }
      .operatorProminentActionButton()
      .accessibilityLabel("Configure Server")
      .accessibilityIdentifier("server-editor-summary-button")

      #if os(macOS)
        if model.hasLocalServerSupport && health == nil {
          Button(action: openExistingServerEditor) {
            Text("Use Existing Server")
              .frame(maxWidth: .infinity)
          }
          .operatorSecondaryActionButton()
          .accessibilityLabel("Use Existing Server")
          .accessibilityIdentifier("existing-server-summary-button")
        }
      #endif
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
      .foregroundStyle(theme.quietText)
      .lineLimit(2)
      .minimumScaleFactor(0.75)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityLabel(issue.identifier.rawValue)
  }

  private var accessibilityValue: String {
    [
      issue.identifier.rawValue,
      formatState(issue.state),
      issue.issueState,
      issue.currentProvider?.replacingOccurrences(of: "_", with: " "),
      issue.priority.map { "Priority \($0)" },
    ]
    .compactMap { $0 }
    .joined(separator: ", ")
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
        .font(.callout)
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
    .accessibilityElement(children: .combine)
    .accessibilityLabel(issue.title)
    .accessibilityValue(accessibilityValue)
    .accessibilityHint("Opens issue details")
    .operatorSelectionBackground(theme, isSelected: isSelected)
  }
}
