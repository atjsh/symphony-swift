import SwiftUI
import SymphonyShared

struct ProgressCommitList: View {
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
        Button(
          action: { progressModel.selectCommit(id: commit.commitID) },
          label: {
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
        })
        .buttonStyle(.plain)
      }
    }
  }
}

struct ProgressInspectorContent: View {
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
