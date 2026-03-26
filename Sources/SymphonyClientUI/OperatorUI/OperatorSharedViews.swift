import Foundation
import SwiftUI
import SymphonyShared

private struct DetailLineValueSelectionModifier: ViewModifier {
  let enabled: Bool

  @ViewBuilder
  func body(content: Content) -> some View {
    if enabled {
      content.textSelection(.enabled)
    } else {
      content
    }
  }
}

struct SectionHeader: View {
  let title: String

  var body: some View {
    Text(title)
      .font(.headline)
      .bold()
  }
}

struct DetailLine: View {
  let label: String
  let value: String
  var monospaced: Bool = false

  var body: some View {
    LabeledContent {
      Text(value)
        .font(monospaced ? .system(.caption, design: .monospaced) : .caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .modifier(DetailLineValueSelectionModifier(enabled: monospaced))
    } label: {
      Text(label)
        .font(.caption)
        .bold()
        .foregroundStyle(.secondary)
    }
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
      .textSelection(.enabled)
  }
}

struct StatePill: View {
  let theme: OperatorTheme
  let text: String
  let tint: Color

  var body: some View {
    Label(text, systemImage: statusSymbol(text))
      .font(.caption)
      .padding(.horizontal, 9)
      .padding(.vertical, 5)
      .background(tint.opacity(0.12), in: Capsule())
      .foregroundStyle(tint)
      .overlay(
        Capsule()
          .strokeBorder(tint.opacity(0.18), lineWidth: 1)
      )
  }
}

struct QuietBadge: View {
  let theme: OperatorTheme
  let text: String

  var body: some View {
    Text(text)
      .font(.caption)
      .padding(.horizontal, 9)
      .padding(.vertical, 5)
      .background(theme.badgeFill, in: Capsule())
      .foregroundStyle(theme.quietText)
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
    Label("P\(priority)", systemImage: "flag.fill")
      .font(.caption)
      .padding(.horizontal, 9)
      .padding(.vertical, 5)
      .background(theme.warningTint.opacity(0.12), in: Capsule())
      .foregroundStyle(theme.warningTint)
      .overlay(
        Capsule()
          .strokeBorder(theme.warningTint.opacity(0.18), lineWidth: 1)
      )
  }
}

struct ProviderBadge: View {
  let theme: OperatorTheme
  let label: String

  var body: some View {
    Text(label.replacingOccurrences(of: "_", with: " ").uppercased())
      .font(.caption)
      .bold()
      .lineLimit(1)
      .fixedSize(horizontal: true, vertical: false)
      .padding(.horizontal, 9)
      .padding(.vertical, 5)
      .background(theme.badgeFill, in: Capsule())
      .foregroundStyle(theme.accentTint)
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

  var body: some View {
    HStack(spacing: 6) {
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.subheadline)
        .bold()
        .monospacedDigit()
    }
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
    HStack(spacing: 8) {
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
    HStack(spacing: 8) {
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
    ContentUnavailableView {
      Label(title, systemImage: systemImage)
    } description: {
      if let detail {
        Text(detail)
      }
    }
    .frame(maxWidth: .infinity)
    .operatorPanel(theme)
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
