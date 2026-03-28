import Foundation
import SwiftUI
import SymphonyShared

struct OperatorFlowLayout: Layout {
  var spacing: CGFloat
  var rowSpacing: CGFloat

  init(spacing: CGFloat = 8, rowSpacing: CGFloat? = nil) {
    self.spacing = spacing
    self.rowSpacing = rowSpacing ?? spacing
  }

  struct Cache {
    var sizes: [CGSize]
  }

  func makeCache(subviews: Subviews) -> Cache {
    var sizes = [CGSize]()
    sizes.reserveCapacity(subviews.count)
    for subview in subviews {
      sizes.append(subview.sizeThatFits(.unspecified))
    }
    return Cache(sizes: sizes)
  }

  func updateCache(_ cache: inout Cache, subviews: Subviews) {
    var sizes = [CGSize]()
    sizes.reserveCapacity(subviews.count)
    for subview in subviews {
      sizes.append(subview.sizeThatFits(.unspecified))
    }
    cache.sizes = sizes
  }

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout Cache
  ) -> CGSize {
    let maxWidth = operatorFlowLayoutMaxWidth(for: proposal.width)
    let rows = makeRows(maxWidth: maxWidth, sizes: cache.sizes)
    var rowWidths = [CGFloat]()
    var rowHeights = [CGFloat]()
    rowWidths.reserveCapacity(rows.count)
    rowHeights.reserveCapacity(rows.count)
    for row in rows {
      rowWidths.append(row.width)
      rowHeights.append(row.height)
    }
    return operatorFlowLayoutMeasuredSize(
      proposedWidth: proposal.width,
      rowWidths: rowWidths,
      rowHeights: rowHeights,
      rowSpacing: rowSpacing
    )
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout Cache
  ) {
    let rows = makeRows(maxWidth: bounds.width, sizes: cache.sizes)
    var y = bounds.minY

    for row in rows {
      var x = bounds.minX
      for index in row.indices {
        let size = cache.sizes[index]
        subviews[index].place(
          at: CGPoint(x: x, y: y),
          proposal: ProposedViewSize(width: size.width, height: size.height)
        )
        x += size.width + spacing
      }
      y += row.height + rowSpacing
    }
  }

  private func makeRows(maxWidth: CGFloat, sizes: [CGSize]) -> [OperatorFlowLayoutRow] {
    guard sizes.isEmpty == false else {
      return []
    }

    var rows = [OperatorFlowLayoutRow]()
    var currentRow = OperatorFlowLayoutRow()

    for (index, size) in sizes.enumerated() {
      let proposedWidth =
        currentRow.indices.isEmpty ? size.width : currentRow.width + spacing + size.width
      if proposedWidth > maxWidth, currentRow.indices.isEmpty == false {
        rows.append(currentRow)
        currentRow = OperatorFlowLayoutRow()
      }

      currentRow.indices.append(index)
      currentRow.width =
        currentRow.indices.count == 1 ? size.width : currentRow.width + spacing + size.width
      currentRow.height = max(currentRow.height, size.height)
    }

    rows.append(currentRow)
    return rows
  }
}

func operatorFlowLayoutMaxWidth(for proposedWidth: CGFloat?) -> CGFloat {
  if let proposedWidth {
    return proposedWidth
  }
  return .greatestFiniteMagnitude
}

func operatorFlowLayoutMeasuredSize(
  proposedWidth: CGFloat?,
  rowWidths: [CGFloat],
  rowHeights: [CGFloat],
  rowSpacing: CGFloat
) -> CGSize {
  var width: CGFloat = 0
  for rowWidth in rowWidths {
    width = max(width, rowWidth)
  }

  var height: CGFloat = 0
  for rowHeight in rowHeights {
    height += rowHeight
  }
  height += rowSpacing * CGFloat(max(rowHeights.count - 1, 0))

  if let proposedWidth {
    return CGSize(width: proposedWidth, height: height)
  }
  return CGSize(width: width, height: height)
}

private struct OperatorFlowLayoutRow {
  var indices = [Int]()
  var width: CGFloat = 0
  var height: CGFloat = 0
}

func detailLineTextSelectionEnabled(for enabled: Bool) -> Bool {
  #if os(iOS)
    false
  #else
    enabled
  #endif
}

extension View {
  @ViewBuilder
  func operatorDetailTextSelection(enabled: Bool) -> some View {
    #if os(iOS)
      self
    #else
      if detailLineTextSelectionEnabled(for: enabled) {
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

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: statusSymbol(text))
        .foregroundStyle(tint)
      Text(text)
        .foregroundStyle(Color.primary)
    }
      .font(.footnote.weight(.semibold))
      .lineLimit(1)
      .fixedSize(horizontal: true, vertical: false)
      .padding(.horizontal, 9)
      .padding(.vertical, 5)
      .background(tint.opacity(0.12), in: Capsule())
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

  var body: some View {
    Text(label.replacingOccurrences(of: "_", with: " ").uppercased())
      .font(.footnote.weight(.semibold))
      .lineLimit(2)
      .minimumScaleFactor(0.85)
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

  var body: some View {
    HStack(spacing: 6) {
      Text(label)
        .font(.caption)
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
