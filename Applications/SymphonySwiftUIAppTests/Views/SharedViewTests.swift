import SwiftUI
import SymphonyShared
import Testing

@testable import SymphonySwiftUIApp

#if canImport(AppKit)
  import AppKit
#endif
#if canImport(UIKit)
  import UIKit
#endif

@MainActor
@Suite("SharedViews – Flow Layout & Detail Helpers", .tags(.views))
struct SharedViewTests {
  @Test func SharedHelperViewsRenderDetailSelectionAndFlowRowsOnIOS() throws {
    let theme = OperatorTheme(compact: false)

    render(
      host(
        VStack(alignment: .leading, spacing: 12) {
          DetailLine(compact: false, label: "Workspace", value: "/tmp/example", monospaced: true)
          DetailLine(compact: true, label: "Status", value: "Running")
          Text("Selectable")
            .operatorDetailTextSelection(enabled: true)
          EmptyStatePanel(
            theme: theme,
            systemImage: "tray",
            title: "Still empty",
            detail: "Waiting for a selected run."
          )
          OperatorFlowLayout(spacing: 8, rowSpacing: 8) {
            Text("One")
            Text("Two")
            Text("Three")
          }
        },
        width: 480,
        height: 420
      )
    )

    #if canImport(UIKit)
      let selectionHostingView = host(
        Text("Selectable").operatorDetailTextSelection(enabled: true),
        width: 180,
        height: 80
      )
      let selectionSize = selectionHostingView.controller.sizeThatFits(
        in: CGSize(width: 180, height: 80))
      #expect(selectionSize.height > 0)

      let flowHostingView = host(
        OperatorFlowLayout(spacing: 8, rowSpacing: 8) {
          Text("One")
          Text("Two")
          Text("Three")
          Text("Four")
        },
        width: 90,
        height: 240
      )
      let flowSize = flowHostingView.controller.sizeThatFits(
        in: CGSize(width: 90, height: 240))
      #expect(flowSize.height > 0)
    #endif

    #expect(
      operatorIssueRowMetadataPlacement(isCompact: false, prefersAccessibilityLayout: true)
        == .stacked
    )
    #expect(operatorFlowLayoutMaxWidth(for: nil) == .greatestFiniteMagnitude)
    #expect(operatorFlowLayoutMaxWidth(for: 144) == 144)
    let measuredFlowSize = operatorFlowLayoutMeasuredSize(
      proposedWidth: nil,
      rowWidths: [72, 96],
      rowHeights: [20, 28],
      rowSpacing: 8
    )
    #expect(measuredFlowSize.width == 96)
    #expect(measuredFlowSize.height == 56)
  }

  @Test func endpointEditorSheetRendersOnBothPlatforms() throws {
    let client = PassiveSymphonyAPIClient()
    let model = SymphonyOperatorModel(client: client, progressReportCache: TestProgressReportCache())
    let root = SymphonyOperatorRootView(model: model)

    let editorView = root.makeEndpointEditorView()
    exercise(editorView, width: 480, height: 400)

    let sheetView = root.makeEndpointEditorSheet()
    exercise(sheetView, width: 480, height: 400)
  }

  @Test func statePillTintCoversAllBranches() {
    // Each state string exercises a different branch in compactAccessibleTint
    let stateValues = [
      "in_progress",
      "running",
      "active",
      "queued",
      "pending",
      "waiting",
      "done",
      "success",
      "complete",
      "failed",
      "error",
      "cancelled",
      "unknown_state",
    ]

    for compact in [false, true] {
      let theme = OperatorTheme(compact: compact)
      for state in stateValues {
        let pill = StatePill(theme: theme, text: state, tint: statusTint(state))
        exercise(pill, width: 120, height: 40)
      }
    }
  }
}
