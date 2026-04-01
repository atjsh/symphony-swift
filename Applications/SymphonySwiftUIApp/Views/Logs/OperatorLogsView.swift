import SwiftUI
import SymphonyShared

struct OperatorLogsPane: View {
  @Bindable var model: SymphonyOperatorModel
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
    #if os(macOS)
      if theme.compact {
        scrollingFilterBar
      } else {
        OperatorLogsPane.makeSegmentedLogFilterPicker(selection: $selection)
      }
    #else
      if theme.compact {
        scrollingFilterBar
      } else {
        glassFilterBar
      }
    #endif
  }

  private var glassFilterBar: some View {
    GlassEffectContainer(spacing: theme.controlSpacing) {
      ForEach(OperatorLogFilter.allCases, id: \.rawValue) { filter in
        filterButton(for: filter)
      }
    }
  }

  private var scrollingFilterBar: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: theme.controlSpacing) {
        ForEach(OperatorLogFilter.allCases, id: \.rawValue) { filter in
          filterButton(for: filter)
        }
      }
      .padding(.vertical, 2)
    }
  }

  @ViewBuilder
  private func filterButton(for filter: OperatorLogFilter) -> some View {
    let palette = OperatorLogsPane.logFilterPalette()
    if selection == filter {
      Button(action: OperatorLogsPane.makeLogFilterAction(selection: $selection, filter: filter)) {
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
      Button(action: OperatorLogsPane.makeLogFilterAction(selection: $selection, filter: filter)) {
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

extension OperatorLogsPane {
  @MainActor
  static func makeSegmentedLogFilterPicker(selection: Binding<OperatorLogFilter>) -> some View {
    Picker("Log Filter", selection: selection) {
      ForEach(OperatorLogFilter.allCases, id: \.rawValue) { filter in
        Text(filter.title).tag(filter)
      }
    }
    .pickerStyle(.segmented)
    .labelsHidden()
    .operatorChoiceControlSizing()
    .accessibilityIdentifier("log-filter-picker")
  }

  static func logFilterPalette() -> OperatorLogFilterPalette {
    OperatorLogFilterPalette(
      selectedFill: .accentColor,
      unselectedFill: Color.primary.opacity(0.04),
      unselectedStroke: Color.primary.opacity(0.14)
    )
  }

  @MainActor
  static func setLogFilter(selection: Binding<OperatorLogFilter>, filter: OperatorLogFilter) {
    selection.wrappedValue = filter
  }

  @MainActor
  static func makeLogFilterAction(selection: Binding<OperatorLogFilter>, filter: OperatorLogFilter) -> () -> Void {
    { setLogFilter(selection: selection, filter: filter) }
  }
}

// LogTimelinePanel, LogEventRow, TimelineMarker, EventMetaLine, EventTag
// moved to LogEventViews.swift
