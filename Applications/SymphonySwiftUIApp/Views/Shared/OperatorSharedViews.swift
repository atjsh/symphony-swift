import Foundation
import SwiftUI
import SymphonyShared

extension View {
  @ViewBuilder
  func operatorDetailTextSelection(enabled: Bool) -> some View {
    #if os(iOS)
      self
    #else
      if enabled {
        self.textSelection(.enabled)
      } else {
        self
      }
    #endif
  }
}

struct SectionHeader: View {
  let theme: OperatorTheme
  let title: String

  var body: some View {
    Text(title)
      .font(theme.sectionTitleFont)
      .foregroundStyle(.primary)
  }
}

struct DetailLine: View {
  let compact: Bool
  let label: String
  let value: String
  var monospaced: Bool = false

  init(compact: Bool = false, label: String, value: String, monospaced: Bool = false) {
    self.compact = compact
    self.label = label
    self.value = value
    self.monospaced = monospaced
  }

  var body: some View {
    if compact {
      VStack(alignment: .leading, spacing: 3) {
        detailLabel
        detailValue
      }
    } else {
      LabeledContent {
        detailValue
      } label: {
        detailLabel
      }
    }
  }

  private var detailLabel: some View {
    Text(label)
      .font(.caption)
      .bold()
      .foregroundStyle(Color.primary)
  }

  private var detailValue: some View {
    Text(value)
      .font(monospaced ? .system(.caption, design: .monospaced) : .caption)
      .foregroundStyle(Color.primary)
      .fixedSize(horizontal: false, vertical: true)
      .operatorDetailTextSelection(enabled: monospaced)
  }
}

struct OperatorMarkdownContent: Equatable {
  let attributedText: AttributedString
  let renderedWithMarkdown: Bool
}

enum OperatorMarkdownRenderer {
  typealias Parser = (String) throws -> AttributedString

  static func makeContent(
    from source: String,
    parser: Parser = parseNativeMarkdown
  ) -> OperatorMarkdownContent {
    do {
      return OperatorMarkdownContent(
        attributedText: try parser(source),
        renderedWithMarkdown: true
      )
    } catch {
      return OperatorMarkdownContent(
        attributedText: AttributedString(source),
        renderedWithMarkdown: false
      )
    }
  }

  static func parseNativeMarkdown(_ source: String) throws -> AttributedString {
    try AttributedString(markdown: source)
  }
}

struct MarkdownMessageText: View {
  let theme: OperatorTheme
  let text: String

  private var renderedContent: OperatorMarkdownContent {
    OperatorMarkdownRenderer.makeContent(from: text)
  }

  var body: some View {
    Text(renderedContent.attributedText)
      .foregroundStyle(theme.bodyText)
      .tint(theme.accentTint)
      .lineSpacing(3)
      .fixedSize(horizontal: false, vertical: true)
      .operatorDetailTextSelection(enabled: true)
  }
}

struct StatePill: View {
  let theme: OperatorTheme
  let text: String
  let tint: Color

  private var foregroundColor: Color {
    #if os(iOS)
      if theme.compact {
        return .white
      }
    #endif
    return .primary
  }

  private var fillColor: Color {
    #if os(iOS)
      if theme.compact {
        return compactAccessibleTint
      }
    #endif
    return tint.opacity(0.12)
  }

  private var strokeColor: Color {
    #if os(iOS)
      if theme.compact {
        return compactAccessibleTint.opacity(0.98)
      }
    #endif
    return tint.opacity(0.18)
  }

  private var compactAccessibleTint: Color {
    let normalized = text.lowercased()

    if normalized.contains("error") || normalized.contains("fail") {
      return Color(red: 0.69, green: 0.12, blue: 0.15)
    }
    if normalized.contains("approve") || normalized.contains("queue") || normalized.contains("wait")
      || normalized.contains("backlog") || normalized.contains("pending")
    {
      return Color(red: 0.74, green: 0.33, blue: 0.04)
    }
    if normalized.contains("done") || normalized.contains("success") || normalized.contains("ready")
      || normalized.contains("complete") || normalized.contains("ended")
    {
      return Color(red: 0.11, green: 0.50, blue: 0.24)
    }
    if normalized.contains("live") || normalized.contains("run") || normalized.contains("active")
      || normalized.contains("progress") || normalized.contains("stream")
    {
      return Color(red: 0.00, green: 0.29, blue: 0.64)
    }
    return Color(red: 0.31, green: 0.34, blue: 0.39)
  }

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: statusSymbol(text))
        .foregroundStyle(foregroundColor)
      Text(text)
        .foregroundStyle(foregroundColor)
    }
      .font(.footnote.weight(.semibold))
      .lineLimit(1)
      .fixedSize(horizontal: true, vertical: false)
      .padding(.horizontal, 9)
      .padding(.vertical, 5)
      .background(fillColor, in: Capsule())
      .overlay(
        Capsule()
          .strokeBorder(strokeColor, lineWidth: 1)
      )
  }
}

struct QuietBadge: View {
  let theme: OperatorTheme
  let text: String

  var body: some View {
    Text(text)
      .font(.footnote.weight(.medium))
      .lineLimit(1)
      .fixedSize(horizontal: true, vertical: false)
      .padding(.horizontal, 9)
      .padding(.vertical, 5)
      .background(theme.badgeFill, in: Capsule())
      .foregroundStyle(Color.primary)
      .overlay(
        Capsule()
          .strokeBorder(theme.badgeBorder, lineWidth: 1)
      )
  }
}

struct PriorityBadge: View {
  let theme: OperatorTheme
  let priority: Int

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: "flag.fill")
        .foregroundStyle(theme.warningTint)
      Text("P\(priority)")
        .foregroundStyle(Color.primary)
    }
      .font(.footnote.weight(.semibold))
      .lineLimit(1)
      .fixedSize(horizontal: true, vertical: false)
      .padding(.horizontal, 9)
      .padding(.vertical, 5)
      .background(theme.warningTint.opacity(0.12), in: Capsule())
      .overlay(
        Capsule()
          .strokeBorder(theme.warningTint.opacity(0.18), lineWidth: 1)
      )
  }
}

struct ProviderBadge: View {
  let theme: OperatorTheme
  let label: String

  private var badgeFont: Font {
    #if os(macOS)
      .subheadline.weight(.semibold)
    #else
      .footnote.weight(.semibold)
    #endif
  }

  var body: some View {
    Text(label.replacingOccurrences(of: "_", with: " ").uppercased())
      .font(badgeFont)
      .lineLimit(2)
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, 9)
      .padding(.vertical, 5)
      .background(theme.badgeFill, in: Capsule())
      .foregroundStyle(Color.primary)
      .overlay(
        Capsule()
          .strokeBorder(theme.badgeBorder, lineWidth: 1)
      )
  }
}

struct MetricChip: View {
  let theme: OperatorTheme
  let label: String
  let value: String

  private var labelFont: Font {
    #if os(macOS)
      .footnote.weight(.medium)
    #else
      .caption
    #endif
  }

  var body: some View {
    HStack(spacing: 6) {
      Text(label)
        .font(labelFont)
        .foregroundStyle(Color.primary)
        .lineLimit(1)
      Text(value)
        .font(.subheadline)
        .bold()
        .monospacedDigit()
        .lineLimit(1)
    }
    .fixedSize(horizontal: true, vertical: false)
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(theme.badgeFill, in: RoundedRectangle(cornerRadius: 10))
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .strokeBorder(theme.badgeBorder, lineWidth: 1)
    )
  }
}

struct MetricsStrip: View {
  let theme: OperatorTheme
  let metrics: [(String, String)]

  var body: some View {
    OperatorFlowLayout(spacing: 8, rowSpacing: 8) {
      ForEach(metrics, id: \.0) { metric in
        MetricChip(theme: theme, label: metric.0, value: metric.1)
      }
    }
  }
}

struct TokenUsageStrip: View {
  let theme: OperatorTheme
  let tokens: TokenUsage

  var body: some View {
    OperatorFlowLayout(spacing: 8, rowSpacing: 8) {
      if let input = tokens.inputTokens {
        MetricChip(theme: theme, label: "Input", value: input.formatted())
      }

      if let output = tokens.outputTokens {
        MetricChip(theme: theme, label: "Output", value: output.formatted())
      }

      if let total = tokens.totalTokens {
        MetricChip(theme: theme, label: "Total", value: total.formatted())
      }
    }
    .accessibilityIdentifier("token-usage")
  }
}

struct EmptyStatePanel: View {
  let theme: OperatorTheme
  let systemImage: String
  let title: String
  var detail: String? = nil

  var body: some View {
    OperatorEmptyStateContent(
      theme: theme,
      systemImage: systemImage,
      title: title,
      detail: detail
    )
    .frame(maxWidth: .infinity)
    .operatorPanel(theme)
  }
}

struct OperatorEmptyStateContent<Actions: View>: View {
  let theme: OperatorTheme
  let systemImage: String
  let title: String
  let detail: String?
  let actions: Actions

  init(
    theme: OperatorTheme,
    systemImage: String,
    title: String,
    detail: String? = nil,
    @ViewBuilder actions: () -> Actions = { EmptyView() }
  ) {
    self.theme = theme
    self.systemImage = systemImage
    self.title = title
    self.detail = detail
    self.actions = actions()
  }

  var body: some View {
    VStack(spacing: theme.sectionSpacing) {
      Image(systemName: systemImage)
        .font(.system(size: theme.compact ? 28 : 34, weight: .regular))
        .foregroundStyle(theme.quietText)
        .accessibilityHidden(true)

      VStack(spacing: 6) {
        Text(title)
          .font(theme.summaryTitleFont)
          .foregroundStyle(theme.bodyText)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)

        if let detail {
          Text(detail)
            .font(.body)
            .foregroundStyle(theme.quietText)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      actions
    }
    .frame(maxWidth: 420)
    .frame(maxWidth: .infinity)
    .padding(.vertical, theme.pagePadding)
    .accessibilityElement(children: .contain)
  }
}

struct LoadingStatePanel: View {
  let theme: OperatorTheme
  let systemImage: String
  let title: String

  var body: some View {
    VStack(spacing: theme.blockSpacing) {
      ProgressView()
      Label(title, systemImage: systemImage)
        .font(.body)
        .foregroundStyle(theme.quietText)
    }
    .frame(maxWidth: .infinity)
    .operatorPanel(theme)
  }
}
