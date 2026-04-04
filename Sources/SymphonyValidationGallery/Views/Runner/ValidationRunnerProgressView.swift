import SwiftUI
import SymphonyXcodeValidation
import SymphonyXcodeValidationServerCore

/// Displays the progress of an active or completed validation run.
public struct ValidationRunnerProgressView: View {
  @Bindable var store: ValidationRunnerStore

  public init(store: ValidationRunnerStore) {
    self.store = store
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      statusBar
      Divider()
      logViewer
      Divider()
      actionBar
    }
  }

  // MARK: - Status

  @ViewBuilder
  private var statusBar: some View {
    HStack(spacing: 12) {
      statusBadge
      if let phase = store.currentPhase {
        Text(phase.slug)
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("phaseIndicator")
          .accessibilityValue(phase.slug)
      }
      Spacer()
      if let startedAt = store.startedAt {
        Text(startedAt, style: .relative)
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("elapsedTime")
      }
      Text("\(store.logLines.count) lines")
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("logLineCount")
        .accessibilityValue("\(store.logLines.count)")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }

  @ViewBuilder
  private var statusBadge: some View {
    HStack(spacing: 4) {
      Circle()
        .fill(statusColor)
        .frame(width: 8, height: 8)
      Text(store.runStatus.rawValue.capitalized)
        .font(.caption.bold())
    }
    .accessibilityIdentifier("statusBadge")
    .accessibilityLabel("Status: \(store.runStatus.rawValue)")
  }

  private var statusColor: Color {
    switch store.runStatus {
    case .idle: .secondary
    case .running: .blue
    case .completed: .green
    case .failed: .red
    }
  }

  // MARK: - Log Viewer

  @ViewBuilder
  private var logViewer: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(store.logLines, id: \.index) { line in
            Text(line.text)
              .font(.system(.caption, design: .monospaced))
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 12)
              .padding(.vertical, 1)
              .id(line.index)
          }
        }
      }
      .accessibilityIdentifier("logViewer")
      .onChange(of: store.logLines.count) {
        if let lastLine = store.logLines.last {
          proxy.scrollTo(lastLine.index, anchor: .bottom)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Action Bar

  @ViewBuilder
  private var actionBar: some View {
    HStack {
      if store.runStatus == .running {
        Button(role: .destructive) {
          Task { await store.cancelRun() }
        } label: {
          Label("Cancel", systemImage: "xmark.circle")
        }
        .accessibilityIdentifier("cancelButton")
      }

      Spacer()

      if let errorMessage = store.errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(.red)
          .lineLimit(1)
          .accessibilityIdentifier("errorMessage")
      }

      if store.runStatus == .completed {
        Button {
          Task { await store.fetchSummary() }
        } label: {
          Label("View Results", systemImage: "doc.text.magnifyingglass")
        }
        .accessibilityIdentifier("viewResultsButton")
      }

      if store.runStatus == .completed || store.runStatus == .failed {
        Button {
          store.reset()
        } label: {
          Label("New Run", systemImage: "arrow.counterclockwise")
        }
        .accessibilityIdentifier("newRunButton")
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }
}
