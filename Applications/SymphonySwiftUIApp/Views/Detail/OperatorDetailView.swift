import Charts
import SwiftUI
import SymphonyShared

struct OperatorDetailView: View {
  @Environment(\.colorScheme) private var colorScheme
  @Bindable var model: SymphonyOperatorModel
  let theme: OperatorTheme
  let selectRun: (RunID) -> Void
  #if os(macOS)
    let openLocalServerEditor: () -> Void
    let openExistingServerEditor: () -> Void
  #endif

  #if os(macOS)
    init(
      model: SymphonyOperatorModel,
      theme: OperatorTheme,
      selectRun: @escaping (RunID) -> Void,
      openLocalServerEditor: @escaping () -> Void = {},
      openExistingServerEditor: @escaping () -> Void = {}
    ) {
      self.model = model
      self.theme = theme
      self.selectRun = selectRun
      self.openLocalServerEditor = openLocalServerEditor
      self.openExistingServerEditor = openExistingServerEditor
    }
  #else
    init(
      model: SymphonyOperatorModel,
      theme: OperatorTheme,
      selectRun: @escaping (RunID) -> Void
    ) {
      self.model = model
      self.theme = theme
      self.selectRun = selectRun
    }
  #endif

  var body: some View {
    Group {
      if model.selectedIssueID == nil {
        detailEmptyState
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
  private var detailEmptyState: some View {
    VStack(spacing: theme.sectionSpacing) {
      ZStack {
        RoundedRectangle(cornerRadius: theme.itemCornerRadius * 1.4, style: .continuous)
          .fill(theme.badgeFill)
          .frame(width: theme.compact ? 72 : 84, height: theme.compact ? 72 : 84)

        Image(systemName: "sidebar.left")
          .font(.system(size: theme.compact ? 34 : 40, weight: .semibold))
          .foregroundStyle(theme.accentTint)
      }

      VStack(spacing: 8) {
        Text("No Issue Selected")
          .font(theme.compact ? .title2.weight(.semibold) : .title.weight(.bold))
          .foregroundStyle(emptyStateTitleColor)

        Text("Choose an issue from the sidebar to inspect orchestration state, runs, sessions, and logs.")
          .multilineTextAlignment(.center)
          .foregroundStyle(emptyStateDescriptionColor)
      }
      .frame(maxWidth: 420)

      #if os(macOS)
        if model.hasLocalServerSupport && model.health == nil {
          VStack(spacing: 10) {
            Button(
              "Start Local Server",
              systemImage: "play.circle",
              action: openLocalServerEditor
            )
            .operatorProminentActionButton()
            .accessibilityIdentifier("empty-start-local-server-button")

            Button(
              "Use Existing Server",
              systemImage: "slider.horizontal.3",
              action: openExistingServerEditor
            )
            .operatorSecondaryActionButton()
            .accessibilityIdentifier("empty-existing-server-button")
          }
          .frame(maxWidth: 280)
        }
      #endif
    }
    .padding(theme.pagePadding)
    .frame(maxWidth: 480)
    .accessibilityIdentifier("operator-detail-empty-state")
  }

  private var emptyStateTitleColor: Color {
    #if os(macOS)
      colorScheme == .dark ? .white : .black
    #else
      theme.bodyText
    #endif
  }

  private var emptyStateDescriptionColor: Color {
    #if os(macOS)
      colorScheme == .dark ? Color.white.opacity(0.82) : Color.black.opacity(0.78)
    #else
      theme.bodyText
    #endif
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
            runSelectionAction: OperatorDetailSummaryView.makeIssueOverviewRunSelectionAction(
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
      .accessibilityIdentifier("overview-scroll")
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
      .accessibilityIdentifier("sessions-scroll")
    case .logs:
      OperatorLogsPane(model: model, theme: theme)
    case .progress:
      OperatorProgressPanel(model: model, theme: theme, detail: detail)
    }
  }
}

extension View {
  @ViewBuilder
  func operatorDetailTitleDisplayPreference(
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
