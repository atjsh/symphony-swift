import Charts
import SwiftUI
import SymphonyShared

struct OperatorProgressPanel: View {
  var model: SymphonyOperatorModel
  let theme: OperatorTheme
  let detail: IssueDetail

  private var progressModel: OperatorProgressReportViewModel {
    model.progressReportModel
  }

  private var progressTaskID: String {
    "\(detail.issue.id.rawValue)|\(detail.workspacePath ?? "no-workspace")"
  }

  private var metricSelection: Binding<OperatorProgressMetric> {
    Binding(
      get: { progressModel.selectedMetric },
      set: { progressModel.selectMetric($0) }
    )
  }

  var body: some View {
    Group {
      if let report = progressModel.report {
        progressContent(report: report)
      } else {
        ProgressStateContent(
          theme: theme,
          status: progressModel.status,
          isLoading: progressModel.isLoading,
          isRefreshing: progressModel.isRefreshing,
          refreshReport: refreshReport
        )
      }
    }
    .task(id: progressTaskID) {
      progressModel.updateIssueContext(
        issueID: detail.issue.id,
        workspacePath: detail.workspacePath
      )
      await progressModel.loadIfNeeded(endpoint: model.serverEndpoint)
    }
  }

  @ViewBuilder
  private func progressContent(report: IssueProgressReportResponse) -> some View {
    if theme.compact {
      ScrollView {
        VStack(alignment: .leading, spacing: theme.sectionSpacing) {
          headerPanel
          summaryStrip(report: report)
          chartPanel(report: report)
          syntaxPanel(report: report)
          ProgressCommitList(theme: theme, progressModel: progressModel)
          ProgressInspectorContent(theme: theme, progressModel: progressModel)
        }
      }
    } else {
      HStack(alignment: .top, spacing: theme.sectionSpacing) {
        ProgressCommitList(theme: theme, progressModel: progressModel)
          .frame(width: 280)
          .frame(maxHeight: .infinity, alignment: .top)

        ScrollView {
          VStack(alignment: .leading, spacing: theme.sectionSpacing) {
            headerPanel
            summaryStrip(report: report)
            chartPanel(report: report)
            syntaxPanel(report: report)
          }
        }

        ProgressInspectorContent(theme: theme, progressModel: progressModel)
          .frame(width: 300)
          .frame(maxHeight: .infinity, alignment: .top)
      }
    }
  }

  private var headerPanel: some View {
    VStack(alignment: .leading, spacing: theme.blockSpacing) {
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          SectionHeader(theme: theme, title: "Repository Progress")
          Text("Issue-scoped repository growth, commit history, and current parse health.")
            .font(.caption)
            .foregroundStyle(theme.quietText)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer(minLength: 12)

        if progressModel.isShowingCachedReport {
          QuietBadge(theme: theme, text: "Cached")
        }

        Button("Refresh Report", systemImage: "arrow.clockwise", action: refreshReport)
          .disabled(progressModel.isLoading || progressModel.isRefreshing)
          .operatorSecondaryActionButton()
          .accessibilityIdentifier("refresh-progress-report-button")
      }

      if let refreshErrorMessage = progressModel.refreshErrorMessage {
        Text(refreshErrorMessage)
          .font(.caption)
          .foregroundStyle(theme.warningTint)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .operatorPanel(theme)
  }

  @ViewBuilder
  private func summaryStrip(report: IssueProgressReportResponse) -> some View {
    let metrics = report.report.summary

    if theme.compact {
      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: theme.controlSpacing) {
        summaryCard(title: "Files", systemImage: "doc.on.doc", value: formatCount(metrics.fileCount))
        summaryCard(title: "Lines", systemImage: "text.alignleft", value: formatCount(metrics.lineCount))
        summaryCard(title: "Bytes", systemImage: "internaldrive", value: formatByteCount(metrics.byteCount))
      }
    } else {
      HStack(spacing: theme.controlSpacing) {
        summaryCard(title: "Files", systemImage: "doc.on.doc", value: formatCount(metrics.fileCount))
        summaryCard(title: "Lines", systemImage: "text.alignleft", value: formatCount(metrics.lineCount))
        summaryCard(title: "Bytes", systemImage: "internaldrive", value: formatByteCount(metrics.byteCount))
      }
    }
  }

  private func summaryCard(title: String, systemImage: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(title, systemImage: systemImage)
        .font(.caption.weight(.semibold))
        .foregroundStyle(theme.quietText)
      Text(value)
        .font(theme.summaryTitleFont)
        .foregroundStyle(theme.bodyText)
        .monospacedDigit()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(theme.itemPadding)
    .operatorInset(theme)
  }

  private func chartPanel(report: IssueProgressReportResponse) -> some View {
    VStack(alignment: .leading, spacing: theme.blockSpacing) {
      HStack(alignment: .center, spacing: 12) {
        SectionHeader(theme: theme, title: "History")
        Spacer(minLength: 12)
        metricPicker
      }

      if progressModel.chartPoints.isEmpty {
        EmptyStatePanel(
          theme: theme,
          systemImage: "chart.xyaxis.line",
          title: "No History Yet",
          detail: "Historical buckets will appear here once repository history is available."
        )
      } else {
        Chart(progressModel.chartPoints) { point in
          AreaMark(
            x: .value("Date", point.date),
            y: .value(progressModel.selectedMetric.title, point.value)
          )
          .foregroundStyle(theme.accentTint.opacity(0.14))

          LineMark(
            x: .value("Date", point.date),
            y: .value(progressModel.selectedMetric.title, point.value)
          )
          .foregroundStyle(theme.accentTint)
          .lineStyle(.init(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

          PointMark(
            x: .value("Date", point.date),
            y: .value(progressModel.selectedMetric.title, point.value)
          )
          .foregroundStyle(theme.accentTint)
        }
        .chartYAxis {
          AxisMarks(position: .leading)
        }
        .chartLegend(.hidden)
        .frame(minHeight: theme.compact ? 220 : 260)
      }

      DetailLine(
        compact: theme.compact,
        label: "Head commit",
        value: report.report.headCommitID,
        monospaced: true
      )
    }
    .operatorPanel(theme)
  }

  private func syntaxPanel(report: IssueProgressReportResponse) -> some View {
    let syntaxHealth = report.syntaxHealth
    return VStack(alignment: .leading, spacing: theme.blockSpacing) {
      SectionHeader(theme: theme, title: "Parse Health")

      HStack(spacing: 8) {
        StatePill(
          theme: theme,
          text: syntaxHealthStatusText(syntaxHealth.status),
          tint: syntaxHealthTint(syntaxHealth.status)
        )
        if syntaxHealth.status == .configured {
          QuietBadge(theme: theme, text: diagnosticSummaryText(syntaxHealth.diagnosticCount))
        }
      }

      DetailLine(
        compact: theme.compact,
        label: "Checked Files",
        value: formatCount(syntaxHealth.checkedFileCount)
      )
      DetailLine(
        compact: theme.compact,
        label: "Diagnostics",
        value: formatCount(syntaxHealth.diagnosticCount)
      )

      if let failureMessage = syntaxHealth.failureMessage, !failureMessage.isEmpty {
        Text(failureMessage)
          .font(.caption)
          .foregroundStyle(theme.errorTint)
          .fixedSize(horizontal: false, vertical: true)
      }

      if !syntaxHealth.diagnostics.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(syntaxHealth.diagnostics.prefix(5), id: \.self) { diagnostic in
            VStack(alignment: .leading, spacing: 4) {
              Text(diagnostic.path)
                .font(.caption.monospaced())
                .foregroundStyle(theme.bodyText)
                .lineLimit(1)
                .truncationMode(.middle)
              Text(diagnostic.message)
                .font(.caption)
                .foregroundStyle(theme.quietText)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(theme.itemPadding)
            .operatorInset(theme)
          }
        }
      }
    }
    .operatorPanel(theme)
  }

  private var metricPicker: some View {
    Group {
      if theme.compact {
        Menu {
          Picker("Metric", selection: metricSelection) {
            ForEach(OperatorProgressMetric.allCases, id: \.rawValue) { metric in
              Label(metric.title, systemImage: metric.systemImage).tag(metric)
            }
          }
        } label: {
          Label(progressModel.selectedMetric.title, systemImage: progressModel.selectedMetric.systemImage)
        }
        .operatorSecondaryActionButton()
      } else {
        Picker("Metric", selection: metricSelection) {
          ForEach(OperatorProgressMetric.allCases, id: \.rawValue) { metric in
            Text(metric.title).tag(metric)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 360)
        .operatorChoiceControlSizing()
      }
    }
  }

  private func refreshReport() {
    Task {
      await progressModel.refresh(endpoint: model.serverEndpoint)
    }
  }

  private func syntaxHealthStatusText(_ status: RepositorySyntaxHealthStatus) -> String {
    switch status {
    case .configured:
      "Configured"
    case .unsupported:
      "Not Configured"
    case .failed:
      "Failed"
    }
  }

  private func syntaxHealthTint(_ status: RepositorySyntaxHealthStatus) -> Color {
    switch status {
    case .configured:
      theme.successTint
    case .unsupported:
      theme.warningTint
    case .failed:
      theme.errorTint
    }
  }

  private func diagnosticSummaryText(_ diagnosticCount: Int) -> String {
    if diagnosticCount == 1 {
      return "1 diagnostic"
    }
    return "\(formatCount(diagnosticCount)) diagnostics"
  }
}

// MARK: - Shared Formatters

private func formatCount(_ value: Int) -> String {
  value.formatted(.number.grouping(.automatic))
}

private func formatByteCount(_ value: Int) -> String {
  ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
}

// MARK: - Subviews

private struct ProgressStateContent: View {
  let theme: OperatorTheme
  let status: OperatorProgressReportStatus
  let isLoading: Bool
  let isRefreshing: Bool
  let refreshReport: () -> Void

  var body: some View {
    switch status {
    case .idle, .loading:
      LoadingStatePanel(
        theme: theme,
        systemImage: "chart.line.uptrend.xyaxis",
        title: "Loading progress report…"
      )
    case .noWorkspace:
      EmptyStatePanel(
        theme: theme,
        systemImage: "folder.badge.questionmark",
        title: "No Workspace Available",
        detail:
          "Progress reporting requires an issue workspace before the repository can be analyzed."
      )
    case .failed(let message):
      VStack(alignment: .leading, spacing: theme.sectionSpacing) {
        EmptyStatePanel(
          theme: theme,
          systemImage: "exclamationmark.triangle",
          title: "Progress Report Unavailable",
          detail: message
        )
        Button("Refresh Report", systemImage: "arrow.clockwise", action: refreshReport)
          .disabled(isLoading || isRefreshing)
          .operatorSecondaryActionButton()
      }
    case .loaded:
      EmptyStatePanel(
        theme: theme,
        systemImage: "chart.line.uptrend.xyaxis",
        title: "No Progress Report",
        detail: "A report will appear here after the workspace repository is analyzed."
      )
    }
  }
}

private struct ProgressCommitList: View {
  let theme: OperatorTheme
  var progressModel: OperatorProgressReportViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: theme.blockSpacing) {
      SectionHeader(theme: theme, title: "Commits")

      if progressModel.visibleCommits.isEmpty {
        Text("No commits available.")
          .font(.caption)
          .foregroundStyle(theme.quietText)
      } else {
        Group {
          if theme.compact {
            commitRows
          } else {
            ScrollView { commitRows }
          }
        }
      }
    }
    .frame(maxHeight: .infinity, alignment: .top)
    .operatorPanel(theme)
  }

  private var commitRows: some View {
    LazyVStack(alignment: .leading, spacing: 10) {
      ForEach(progressModel.visibleCommits, id: \.commitID) { commit in
        Button(action: { progressModel.selectCommit(id: commit.commitID) }) {
          VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
              Text(commit.shortID)
                .font(.caption.monospaced())
                .foregroundStyle(theme.accentTint)
              Spacer(minLength: 8)
              Text(formatTimestamp(commit.committedAt))
                .font(.caption2)
                .foregroundStyle(theme.quietText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            Text(commit.subject)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(theme.bodyText)
              .multilineTextAlignment(.leading)
              .lineLimit(theme.compact ? 4 : 3)
              .fixedSize(horizontal: false, vertical: true)
            Text("\(formatCount(commit.metrics.lineCount)) lines")
              .font(.caption)
              .foregroundStyle(theme.quietText)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(theme.itemPadding)
          .operatorSelectionBackground(
            theme, isSelected: progressModel.selectedCommitID == commit.commitID)
        }
        .buttonStyle(.plain)
      }
    }
  }
}

private struct ProgressInspectorContent: View {
  let theme: OperatorTheme
  var progressModel: OperatorProgressReportViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: theme.blockSpacing) {
      SectionHeader(theme: theme, title: "Inspector")

      Group {
        if theme.compact {
          inspectorDetail
        } else {
          ScrollView { inspectorDetail }
        }
      }
    }
    .frame(maxHeight: .infinity, alignment: .top)
    .operatorPanel(theme)
  }

  @ViewBuilder
  private var inspectorDetail: some View {
    if let commit = progressModel.selectedCommit {
      VStack(alignment: .leading, spacing: theme.blockSpacing) {
        DetailLine(compact: theme.compact, label: "Commit", value: commit.shortID, monospaced: true)
        DetailLine(compact: theme.compact, label: "Author", value: commit.authorName)
        DetailLine(
          compact: theme.compact, label: "Committed", value: formatTimestamp(commit.committedAt))
        DetailLine(
          compact: theme.compact, label: "Files", value: formatCount(commit.metrics.fileCount))
        DetailLine(
          compact: theme.compact, label: "Lines", value: formatCount(commit.metrics.lineCount))
        DetailLine(
          compact: theme.compact, label: "Characters",
          value: formatCount(commit.metrics.characterCount))
        DetailLine(
          compact: theme.compact, label: "Bytes",
          value: formatByteCount(commit.metrics.byteCount))
        DetailLine(
          compact: theme.compact, label: "Changed Files",
          value: formatCount(commit.activity.changedFileCount))
        DetailLine(
          compact: theme.compact, label: "Additions",
          value: formatCount(commit.activity.additions))
        DetailLine(
          compact: theme.compact, label: "Deletions",
          value: formatCount(commit.activity.deletions))
      }
    } else {
      Text("Select a commit to inspect its metrics.")
        .font(.caption)
        .foregroundStyle(theme.quietText)
    }
  }
}
