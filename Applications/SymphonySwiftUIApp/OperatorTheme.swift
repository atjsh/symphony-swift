import Foundation
import SwiftUI
import SymphonyShared

#if canImport(AppKit)
  import AppKit
#endif

struct OperatorTheme {
  let compact: Bool

  var pagePadding: CGFloat { compact ? 12 : defaultSpacing(14, regular: 16) }
  var sectionSpacing: CGFloat { compact ? 12 : defaultSpacing(12, regular: 14) }
  var blockSpacing: CGFloat { compact ? 10 : defaultSpacing(10, regular: 12) }
  var controlSpacing: CGFloat { compact ? 8 : 10 }
  var panelPadding: CGFloat { compact ? 12 : defaultSpacing(12, regular: 14) }
  var itemPadding: CGFloat { compact ? 10 : 12 }
  var rowSpacing: CGFloat { compact ? 8 : 10 }
  var panelCornerRadius: CGFloat { compact ? 12 : platformMetric(macOS: 10, default: 16) }
  var itemCornerRadius: CGFloat { compact ? 10 : platformMetric(macOS: 8, default: 12) }
  var iconSize: CGFloat { compact ? 18 : 20 }
  var summaryTitleFont: Font {
    compact ? .title3.weight(.semibold) : platformFont(macOS: .title3.weight(.semibold), default: .title2.weight(.bold))
  }
  var sectionTitleFont: Font {
    compact ? .title3.weight(.semibold) : platformFont(macOS: .headline.weight(.semibold), default: .headline.weight(.bold))
  }

  var bodyText: Color { .primary }
  var quietText: Color { .secondary }
  var subduedText: Color { .secondary }
  var accentTint: Color { .accentColor }
  var toolTint: Color { .blue }
  var successTint: Color { .green }
  var warningTint: Color { .orange }
  var errorTint: Color { .red }
  var badgeFill: Color {
    #if os(macOS)
      .primary.opacity(0.12)
    #else
      .primary.opacity(0.05)
    #endif
  }
  var badgeBorder: Color {
    #if os(macOS)
      .primary.opacity(0.18)
    #else
      .secondary.opacity(0.16)
    #endif
  }
  var selectedFill: Color { .accentColor.opacity(0.12) }
  var selectedStroke: Color { .accentColor.opacity(0.28) }
  var panelFill: Color {
    #if os(macOS)
      Color(nsColor: .controlBackgroundColor)
    #else
      Color.primary.opacity(0.04)
    #endif
  }
  var insetFill: Color {
    #if os(macOS)
      Color(nsColor: .controlColor)
    #else
      Color.primary.opacity(0.03)
    #endif
  }
  var panelStroke: Color {
    #if os(macOS)
      Color(nsColor: .separatorColor).opacity(0.4)
    #else
      .secondary.opacity(0.18)
    #endif
  }
  var insetStroke: Color {
    #if os(macOS)
      Color(nsColor: .separatorColor).opacity(0.18)
    #else
      .secondary.opacity(0.12)
    #endif
  }

  private func defaultSpacing(_ macOS: CGFloat, regular: CGFloat) -> CGFloat {
    platformMetric(macOS: macOS, default: regular)
  }

  private func platformMetric(macOS: CGFloat, default: CGFloat) -> CGFloat {
    #if os(macOS)
      macOS
    #else
      `default`
    #endif
  }

  private func platformFont(macOS: Font, default: Font) -> Font {
    #if os(macOS)
      macOS
    #else
      `default`
    #endif
  }
}

enum OperatorSummaryActionPlacement: Equatable {
  case trailing
  case stacked
}

enum OperatorChoiceControlPresentation: Equatable {
  case segmented
  case glassBar
  case scrolling
}

enum OperatorIssueRowMetadataPlacement: Equatable {
  case trailing
  case stacked
}

enum OperatorDetailNavigationTitleDisplayPreference: Equatable {
  case automatic
  case inline
}

func operatorSummaryActionPlacement(isCompact: Bool) -> OperatorSummaryActionPlacement {
  isCompact ? .stacked : .trailing
}

func operatorChoiceControlPresentation(isCompact: Bool) -> OperatorChoiceControlPresentation {
  if isCompact {
    return .scrolling
  }
  #if os(macOS)
    return .segmented
  #else
    return .glassBar
  #endif
}

func operatorIssueRowMetadataPlacement(isCompact: Bool) -> OperatorIssueRowMetadataPlacement {
  isCompact ? .stacked : .trailing
}

func operatorIssueRowMetadataPlacement(
  isCompact: Bool,
  prefersAccessibilityLayout: Bool
) -> OperatorIssueRowMetadataPlacement {
  prefersAccessibilityLayout ? .stacked : operatorIssueRowMetadataPlacement(isCompact: isCompact)
}

func operatorDetailNavigationTitleDisplayPreference(isCompact: Bool)
  -> OperatorDetailNavigationTitleDisplayPreference
{
  isCompact ? .inline : .automatic
}

func formatTimestamp(_ isoString: String) -> String {
  let formatter = ISO8601DateFormatter()
  guard let date = formatter.date(from: isoString) else { return isoString }
  let relative = RelativeDateTimeFormatter()
  relative.unitsStyle = .abbreviated
  return relative.localizedString(for: date, relativeTo: Date())
}

func formatState(_ state: String) -> String {
  state.split(separator: "_")
    .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
    .joined(separator: " ")
}

func recentSessionHasVisibleTokenUsage(_ tokens: TokenUsage) -> Bool {
  if tokens.inputTokens != nil {
    return true
  }
  if tokens.outputTokens != nil {
    return true
  }
  return tokens.totalTokens != nil
}

func statusTint(_ state: String) -> Color {
  let normalized = state.lowercased()

  if normalized.contains("error") || normalized.contains("fail") {
    return .red
  }
  if normalized.contains("approve") || normalized.contains("queue") || normalized.contains("wait")
    || normalized.contains("backlog") || normalized.contains("pending")
  {
    return .orange
  }
  if normalized.contains("done") || normalized.contains("success") || normalized.contains("ready")
    || normalized.contains("complete") || normalized.contains("ended")
  {
    return .green
  }
  if normalized.contains("live") || normalized.contains("run") || normalized.contains("active")
    || normalized.contains("progress") || normalized.contains("stream")
  {
    return .accentColor
  }
  return .secondary
}

func statusSymbol(_ state: String) -> String {
  let normalized = state.lowercased()

  if normalized.contains("error") || normalized.contains("fail") {
    return "xmark.octagon.fill"
  }
  if normalized.contains("approve") || normalized.contains("queue") || normalized.contains("wait")
    || normalized.contains("backlog") || normalized.contains("pending")
  {
    return "clock.badge.exclamationmark.fill"
  }
  if normalized.contains("done") || normalized.contains("success") || normalized.contains("ready")
    || normalized.contains("complete") || normalized.contains("ended")
  {
    return "checkmark.circle.fill"
  }
  if normalized.contains("live") || normalized.contains("run") || normalized.contains("active")
    || normalized.contains("progress") || normalized.contains("stream")
  {
    return "bolt.horizontal.circle.fill"
  }
  return "circle.fill"
}

extension View {
  func operatorPanel(_ theme: OperatorTheme) -> some View {
    self
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(theme.panelPadding)
      .background(
        theme.panelFill, in: RoundedRectangle(cornerRadius: theme.panelCornerRadius)
      )
      .overlay(
        RoundedRectangle(cornerRadius: theme.panelCornerRadius)
          .strokeBorder(theme.panelStroke, lineWidth: 1)
      )
  }

  func operatorInset(_ theme: OperatorTheme) -> some View {
    self
      .background(
        theme.insetFill, in: RoundedRectangle(cornerRadius: theme.itemCornerRadius)
      )
      .overlay(
        RoundedRectangle(cornerRadius: theme.itemCornerRadius)
          .strokeBorder(theme.insetStroke, lineWidth: 1)
      )
  }

  func operatorSelectionBackground(_ theme: OperatorTheme, isSelected: Bool) -> some View {
    self
      .background(
        isSelected ? theme.selectedFill : Color.clear,
        in: RoundedRectangle(cornerRadius: theme.itemCornerRadius)
      )
      .overlay(
        RoundedRectangle(cornerRadius: theme.itemCornerRadius)
          .strokeBorder(isSelected ? theme.selectedStroke : .clear, lineWidth: 1)
      )
  }

  @ViewBuilder
  func operatorProminentActionButton() -> some View {
    #if os(macOS)
      self
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
    #else
      self.buttonStyle(.glassProminent)
    #endif
  }

  @ViewBuilder
  func operatorSecondaryActionButton() -> some View {
    #if os(macOS)
      self
        .buttonStyle(.bordered)
        .controlSize(.small)
    #else
      self.buttonStyle(.glass)
    #endif
  }

  @ViewBuilder
  func operatorChoiceControlSizing() -> some View {
    #if os(macOS)
      self.controlSize(.small)
    #else
      self
    #endif
  }
}
