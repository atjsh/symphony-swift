import SwiftUI
import SymphonyShared

struct OperatorLogsPane: View {
  @ObservedObject var model: SymphonyOperatorModel
  let theme: OperatorTheme

  var body: some View {
    VStack(alignment: .leading, spacing: theme.sectionSpacing) {
      if theme.compact {
        VStack(alignment: .leading, spacing: 8) {
          SectionHeader(theme: theme, title: "Live Run Logs")
          StatePill(theme: theme, text: model.liveStatus, tint: statusTint(model.liveStatus))
            .accessibilityIdentifier("live-status")
        }
      } else {
        HStack(alignment: .center, spacing: 12) {
          SectionHeader(theme: theme, title: "Live Run Logs")
          Spacer()
          StatePill(theme: theme, text: model.liveStatus, tint: statusTint(model.liveStatus))
            .accessibilityIdentifier("live-status")
        }
      }

      OperatorLogFilterBar(theme: theme, selection: $model.selectedLogFilter)

      LogTimelinePanel(theme: theme, logEvents: model.filteredVisibleLogEvents)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

private struct OperatorLogFilterBar: View {
  let theme: OperatorTheme
  @Binding var selection: OperatorLogFilter

  var body: some View {
    if operatorChoiceControlPresentation(isCompact: theme.compact) == .glassBar {
      GlassEffectContainer(spacing: theme.controlSpacing) {
        ForEach(OperatorLogFilter.allCases, id: \.rawValue) { filter in
          filterButton(for: filter)
        }
      }
    } else {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: theme.controlSpacing) {
          ForEach(OperatorLogFilter.allCases, id: \.rawValue) { filter in
            filterButton(for: filter)
          }
        }
        .padding(.vertical, 2)
      }
    }
  }

  @ViewBuilder
  private func filterButton(for filter: OperatorLogFilter) -> some View {
    let palette = operatorLogFilterPalette()
    if selection == filter {
      Button(action: makeLogFilterAction(selection: $selection, filter: filter)) {
        filterButtonLabel(for: filter)
          .foregroundStyle(Color.white)
          .padding(.horizontal, 14)
          .padding(.vertical, 10)
          .frame(minHeight: 44)
          .background(palette.selectedFill, in: Capsule())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("log-filter-\(filter.rawValue)")
    } else {
      Button(action: makeLogFilterAction(selection: $selection, filter: filter)) {
        filterButtonLabel(for: filter)
          .foregroundStyle(theme.bodyText)
          .padding(.horizontal, 14)
          .padding(.vertical, 10)
          .frame(minHeight: 44)
          .background(palette.unselectedFill, in: Capsule())
          .overlay(
            Capsule()
              .strokeBorder(palette.unselectedStroke, lineWidth: 1)
          )
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("log-filter-\(filter.rawValue)")
    }
  }

  @ViewBuilder
  private func filterButtonLabel(for filter: OperatorLogFilter) -> some View {
    if theme.compact {
      Text(filter.title)
        .font(.body.weight(.semibold))
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    } else {
      Label(filter.title, systemImage: filter.systemImage)
        .font(.body.weight(.semibold))
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
  }
}

struct OperatorLogFilterPalette {
  let selectedFill: Color
  let unselectedFill: Color
  let unselectedStroke: Color
}

func operatorLogFilterPalette() -> OperatorLogFilterPalette {
  OperatorLogFilterPalette(
    selectedFill: Color(red: 0.0, green: 0.28, blue: 0.72),
    unselectedFill: Color.primary.opacity(0.04),
    unselectedStroke: Color.primary.opacity(0.14)
  )
}

@MainActor
func operatorSetLogFilter(selection: Binding<OperatorLogFilter>, filter: OperatorLogFilter) {
  selection.wrappedValue = filter
}

@MainActor
func makeLogFilterAction(selection: Binding<OperatorLogFilter>, filter: OperatorLogFilter) -> () ->
  Void
{
  { operatorSetLogFilter(selection: selection, filter: filter) }
}

struct LogTimelinePanel: View {
  let theme: OperatorTheme
  let logEvents: [AgentRawEvent]

  var body: some View {
    if logEvents.isEmpty {
      EmptyStatePanel(
        theme: theme,
        systemImage: "text.alignleft",
        title: "No Matching Log Events",
        detail: "Adjust the filter to inspect a different slice of the run."
      )
      .accessibilityIdentifier("logs-empty")
    } else {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: theme.sectionSpacing) {
          ForEach(Array(logEvents.enumerated()), id: \.element.sequence.rawValue) { index, event in
            LogEventRow(
              theme: theme,
              event: event,
              presentation: SymphonyEventPresentation(event: event),
              isLast: index == logEvents.index(before: logEvents.endIndex)
            )
            .accessibilityIdentifier("log-event-\(event.sequence.rawValue)")
          }
        }
        .padding(.vertical, 4)
      }
      .accessibilityIdentifier("logs-list")
    }
  }
}

struct LogEventRow: View {
  let theme: OperatorTheme
  let event: AgentRawEvent
  let presentation: SymphonyEventPresentation
  let isLast: Bool

  var body: some View {
    HStack(alignment: .top, spacing: theme.blockSpacing) {
      TimelineMarker(
        theme: theme, rowStyle: presentation.rowStyle, tint: markerTint, isLast: isLast)

      switch presentation.rowStyle {
      case .message:
        messageContent
      case .tool:
        toolContent
      case .compact:
        compactContent
      case .callout:
        calloutContent
      case .supplemental:
        supplementalContent
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .contain)
  }

  private var markerTint: Color {
    switch presentation.rowStyle {
    case .message:
      theme.accentTint
    case .tool:
      theme.toolTint
    case .compact:
      statusTint(presentation.detail)
    case .callout:
      event.normalizedKind == .error ? theme.errorTint : theme.warningTint
    case .supplemental:
      .secondary
    }
  }

  private var messageContent: some View {
    VStack(alignment: .leading, spacing: 8) {
      EventMetaLine(theme: theme, title: presentation.title, metadata: presentation.metadata)
      Text(presentation.detail)
        .font(.body)
        .foregroundStyle(theme.bodyText)
        .fixedSize(horizontal: false, vertical: true)
        .operatorDetailTextSelection(enabled: true)
    }
    .padding(theme.itemPadding)
    .operatorInset(theme)
  }

  private var toolContent: some View {
    VStack(alignment: .leading, spacing: 8) {
      EventMetaLine(theme: theme, title: presentation.title, metadata: presentation.metadata)
      Text(presentation.detail)
        .font(.body.monospaced())
        .foregroundStyle(theme.bodyText)
        .fixedSize(horizontal: false, vertical: true)
        .operatorDetailTextSelection(enabled: true)
    }
    .padding(theme.itemPadding)
    .operatorInset(theme)
  }

  private var compactContent: some View {
    Group {
      if theme.compact {
        VStack(alignment: .leading, spacing: 8) {
          EventTag(theme: theme, text: presentation.title, tint: markerTint)
          Text(presentation.detail)
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
          Text(presentation.metadata)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      } else {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          EventTag(theme: theme, text: presentation.title, tint: markerTint)
          Text(presentation.detail)
            .font(.subheadline)
          Spacer(minLength: 8)
          Text(presentation.metadata)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.trailing)
        }
      }
    }
    .padding(theme.itemPadding)
    .operatorInset(theme)
  }

  private var calloutContent: some View {
    VStack(alignment: .leading, spacing: 8) {
      EventMetaLine(
        theme: theme, title: presentation.title, metadata: presentation.metadata, tint: markerTint)
      Text(presentation.detail)
        .font(.body)
        .foregroundStyle(theme.bodyText)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(theme.itemPadding)
    .background(
      markerTint.opacity(0.10), in: RoundedRectangle(cornerRadius: theme.itemCornerRadius)
    )
    .overlay(
      RoundedRectangle(cornerRadius: theme.itemCornerRadius)
        .strokeBorder(markerTint.opacity(0.22), lineWidth: 1)
    )
  }

  private var supplementalContent: some View {
    VStack(alignment: .leading, spacing: 8) {
      EventMetaLine(theme: theme, title: presentation.title, metadata: presentation.metadata)
      Text(presentation.detail)
        .font(.subheadline)
        .foregroundStyle(theme.subduedText)
        .fixedSize(horizontal: false, vertical: true)

      if presentation.showsRawJSON {
        Text(event.rawJSON)
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
          .operatorDetailTextSelection(enabled: true)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(theme.itemPadding)
    .operatorInset(theme)
  }
}

private struct TimelineMarker: View {
  let theme: OperatorTheme
  let rowStyle: SymphonyEventPresentation.RowStyle
  let tint: Color
  let isLast: Bool

  var body: some View {
    VStack(spacing: 0) {
      Image(systemName: markerSymbol)
        .font(.caption)
        .foregroundStyle(tint)

      Rectangle()
        .fill(.secondary.opacity(0.25))
        .frame(width: 1)
        .frame(maxHeight: .infinity)
        .opacity(isLast ? 0 : 1)
    }
    .frame(width: 14)
    .padding(.top, 4)
  }

  private var markerSymbol: String {
    switch rowStyle {
    case .message:
      "text.bubble.fill"
    case .tool:
      "hammer.fill"
    case .compact:
      "bolt.horizontal.circle.fill"
    case .callout:
      "exclamationmark.triangle.fill"
    case .supplemental:
      "ellipsis.circle.fill"
    }
  }
}

private struct EventMetaLine: View {
  let theme: OperatorTheme
  let title: String
  let metadata: String
  var tint: Color = .secondary

  private var metadataDisplayText: String {
    metadata
      .replacingOccurrences(of: "_", with: "_\u{200B}")
      .replacingOccurrences(of: " • ", with: " •\u{200B} ")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(verbatim: metadataDisplayText)
        .font(.subheadline)
        .foregroundStyle(Color.primary)
        .multilineTextAlignment(.leading)
        .accessibilityLabel(metadata)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct EventTag: View {
  let theme: OperatorTheme
  let text: String
  let tint: Color

  var body: some View {
    Text(text)
      .font(.body.weight(.semibold))
      .multilineTextAlignment(.leading)
      .foregroundStyle(Color.primary)
      .accessibilityHidden(true)
  }
}
