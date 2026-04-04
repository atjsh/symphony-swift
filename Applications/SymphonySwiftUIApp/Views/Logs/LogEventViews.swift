import SwiftUI
import SymphonyShared

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
      .scrollEdgeEffectStyle(.soft, for: .top)
      .accessibilityIdentifier("logs-list")
    }
  }
}

struct LogEventRow: View {
  let theme: OperatorTheme
  let event: AgentRawEvent
  let presentation: SymphonyEventPresentation
  let isLast: Bool

  private var accessibilityLabel: String {
    if presentation.title.isEmpty {
      return presentation.detail
    }
    return "\(presentation.title). \(presentation.detail)"
  }

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
    .accessibilityRepresentation {
      VStack(alignment: .leading, spacing: 4) {
        Text(accessibilityLabel)
          .fixedSize(horizontal: false, vertical: true)
        if presentation.metadata.isEmpty == false {
          Text(presentation.metadata)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
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
    .accessibilityHidden(true)
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
    .accessibilityHidden(true)
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
    .accessibilityHidden(true)
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
    .accessibilityHidden(true)
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
    .accessibilityHidden(true)
  }
}

private struct TimelineMarker: View {
  let theme: OperatorTheme
  let rowStyle: SymphonyEventPresentation.RowStyle
  let tint: Color
  let isLast: Bool

  private var style: OperatorLogTimelineMarkerStyle {
    OperatorLogTimelineMarkerStyle(for: rowStyle)
  }

  var body: some View {
    VStack(spacing: 0) {
      ZStack {
        Circle()
          .fill(style.fill(tint: tint))
        Circle()
          .strokeBorder(style.strokeColor, lineWidth: 1)
        Image(systemName: markerSymbol)
          .font(.system(size: style.symbolSize, weight: .bold))
          .foregroundStyle(Color.white)
      }
      .frame(width: style.markerSize, height: style.markerSize)

      Rectangle()
        .fill(.secondary.opacity(0.25))
        .frame(width: 1)
        .frame(maxHeight: .infinity)
        .opacity(isLast ? 0 : 1)
    }
    .frame(width: style.markerSize)
    .padding(.top, 4)
    .accessibilityHidden(true)
  }

  private var markerSymbol: String {
    style.symbolName
  }
}

enum OperatorLogTimelineMarkerFillRole: Equatable {
  case accent
  case toolHighContrast
  case supplemental
}

struct OperatorLogTimelineMarkerStyle: Equatable {
  let symbolName: String
  let fillRole: OperatorLogTimelineMarkerFillRole
  let markerSize: CGFloat
  let symbolSize: CGFloat
}

extension OperatorLogTimelineMarkerStyle {
  init(for rowStyle: SymphonyEventPresentation.RowStyle) {
    switch rowStyle {
    case .message:
      self = OperatorLogTimelineMarkerStyle(
        symbolName: "text.bubble.fill",
        fillRole: .accent,
        markerSize: 20,
        symbolSize: 10
      )
    case .tool:
      self = OperatorLogTimelineMarkerStyle(
        symbolName: "hammer.fill",
        fillRole: .toolHighContrast,
        markerSize: 20,
        symbolSize: 10
      )
    case .compact:
      self = OperatorLogTimelineMarkerStyle(
        symbolName: "bolt.horizontal.circle.fill",
        fillRole: .accent,
        markerSize: 20,
        symbolSize: 10
      )
    case .callout:
      self = OperatorLogTimelineMarkerStyle(
        symbolName: "exclamationmark.triangle.fill",
        fillRole: .accent,
        markerSize: 20,
        symbolSize: 10
      )
    case .supplemental:
      self = OperatorLogTimelineMarkerStyle(
        symbolName: "ellipsis.circle.fill",
        fillRole: .supplemental,
        markerSize: 20,
        symbolSize: 10
      )
    }
  }

  func fill(tint: Color) -> Color {
    switch fillRole {
    case .accent:
      tint
    case .toolHighContrast:
      Color(red: 0.05, green: 0.22, blue: 0.56)
    case .supplemental:
      .secondary.opacity(0.75)
    }
  }

  var strokeColor: Color {
    switch fillRole {
    case .toolHighContrast:
      Color.white.opacity(0.18)
    case .accent, .supplemental:
      .clear
    }
  }
}

private struct EventMetaLine: View {
  @Environment(\.colorScheme) private var colorScheme
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
        .font(metadataFont)
        .foregroundStyle(metadataForeground)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(metadataBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(metadataStroke, lineWidth: 1)
        )
        .multilineTextAlignment(.leading)
        .accessibilityLabel(metadata)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var metadataFont: Font {
    #if os(macOS)
      .callout.weight(.semibold)
    #else
      .subheadline.weight(.medium)
    #endif
  }

  private var metadataForeground: Color {
    #if os(macOS)
      colorScheme == .dark ? .white : Color.black.opacity(0.82)
    #else
      Color.primary
    #endif
  }

  private var metadataBackground: Color {
    #if os(macOS)
      if colorScheme == .dark {
        Color.white.opacity(0.10)
      } else {
        Color.black.opacity(0.05)
      }
    #else
      Color.clear
    #endif
  }

  private var metadataStroke: Color {
    #if os(macOS)
      if colorScheme == .dark {
        Color.white.opacity(0.12)
      } else {
        Color.black.opacity(0.08)
      }
    #else
      Color.clear
    #endif
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
