import SwiftUI
import SymphonyShared

struct OperatorDetailSummaryView: View {
  var model: SymphonyOperatorModel
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
        action: Self.makeSelectLatestRunAction(detail: detail, selectRun: selectRun)
      )
      .lineLimit(1)
      .fixedSize(horizontal: true, vertical: false)
      .frame(minHeight: 44)
      .operatorSecondaryActionButton()
      .accessibilityIdentifier("latest-run-button")
    }
  }
}

struct OperatorDetailTabBar: View {
  let theme: OperatorTheme
  @Binding var selection: OperatorDetailTab

  var body: some View {
    #if os(macOS)
      if theme.compact {
        scrollingTabBar
      } else {
        OperatorDetailTabBar.makeSegmentedTabPicker(selection: $selection)
      }
    #else
      if theme.compact {
        scrollingTabBar
      } else {
        glassTabBar
      }
    #endif
  }

  private var glassTabBar: some View {
    GlassEffectContainer(spacing: theme.controlSpacing) {
      ForEach(OperatorDetailTab.allCases, id: \.rawValue) { tab in
        tabButton(for: tab)
      }
    }
  }

  @ViewBuilder
  private var scrollingTabBar: some View {
    #if os(iOS)
      if operatorChoiceControlButtonStyle(isCompact: theme.compact) == .quietCapsule {
        LazyVGrid(
          columns: Array(repeating: GridItem(.flexible(), spacing: theme.controlSpacing), count: 2),
          spacing: theme.controlSpacing
        ) {
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
    #else
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: theme.controlSpacing) {
          ForEach(OperatorDetailTab.allCases, id: \.rawValue) { tab in
            tabButton(for: tab)
          }
        }
        .padding(.vertical, 2)
      }
    #endif
  }

  private func quietCapsuleTabButton(for tab: OperatorDetailTab) -> some View {
    let isSelected = selection == tab

    return Button(
      action: Self.makeTabAction(selection: $selection, tab: tab)
    ) {
      Image(systemName: tab.systemImage)
        .font(.body.weight(.semibold))
      .frame(maxWidth: .infinity, minHeight: 44)
      .padding(.horizontal, 8)
    }
    .buttonStyle(.plain)
    .foregroundStyle(.primary)
    .background(
      isSelected ? theme.selectedFill : theme.panelFill,
      in: Capsule()
    )
    .overlay(
      Capsule()
        .strokeBorder(isSelected ? theme.selectedStroke : theme.panelStroke, lineWidth: 1)
    )
    .accessibilityLabel(tab.title)
    .accessibilityIdentifier("detail-tab-\(tab.rawValue)")
  }

  @ViewBuilder
  private func tabButton(for tab: OperatorDetailTab) -> some View {
    if operatorChoiceControlButtonStyle(isCompact: theme.compact) == .quietCapsule {
      quietCapsuleTabButton(for: tab)
    } else {
      platformTabButton(for: tab)
    }
  }

  private func platformTabButton(for tab: OperatorDetailTab) -> some View {
    let isSelected = selection == tab

    return Button(
      tab.title,
      systemImage: tab.systemImage,
      action: Self.makeTabAction(selection: $selection, tab: tab)
    )
    .lineLimit(1)
    .fixedSize(horizontal: true, vertical: false)
    .frame(minHeight: 44)
    .buttonStyle(.glass)
    .background(isSelected ? theme.selectedFill : Color.clear, in: Capsule())
    .overlay(
      Capsule()
        .strokeBorder(isSelected ? theme.selectedStroke : .clear, lineWidth: 1.5)
    )
    .accessibilityIdentifier("detail-tab-\(tab.rawValue)")
  }
}

extension OperatorDetailTabBar {
  @MainActor
  static func makeSegmentedTabPicker(selection: Binding<OperatorDetailTab>) -> some View {
    Picker("Detail Tab", selection: selection) {
      ForEach(OperatorDetailTab.allCases, id: \.rawValue) { tab in
        Text(tab.title).tag(tab)
      }
    }
    .pickerStyle(.segmented)
    .labelsHidden()
    .operatorChoiceControlSizing()
    .accessibilityIdentifier("detail-tab-picker")
  }

  @MainActor
  static func setDetailTab(selection: Binding<OperatorDetailTab>, tab: OperatorDetailTab) {
    selection.wrappedValue = tab
  }

  @MainActor
  static func makeTabAction(
    selection: Binding<OperatorDetailTab>,
    tab: OperatorDetailTab
  ) -> () -> Void {
    {
      setDetailTab(selection: selection, tab: tab)
    }
  }
}

extension OperatorDetailSummaryView {
  @MainActor
  static func selectLatestRun(detail: IssueDetail, selectRun: (RunID) -> Void) {
    guard let latestRun = detail.latestRun else {
      return
    }

    selectRun(latestRun.runID)
  }

  @MainActor
  static func makeSelectLatestRunAction(detail: IssueDetail, selectRun: @escaping (RunID) -> Void)
    -> () -> Void
  {
    {
      selectLatestRun(detail: detail, selectRun: selectRun)
    }
  }

  @MainActor
  static func makeIssueOverviewRunSelectionAction(
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

  static func runOverviewShowsLatestMessage(compact: Bool) -> Bool {
    compact == false
  }

  static func runOverviewShowsLastEvent(compact: Bool) -> Bool {
    compact == false
  }
}
