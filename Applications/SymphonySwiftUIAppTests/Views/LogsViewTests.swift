import SwiftUI
import SymphonyShared
import Testing

@testable import SymphonySwiftUIApp

#if canImport(AppKit)
  import AppKit
#endif

@MainActor
@Suite("LogsView – Filters, Timeline & Theme", .tags(.views))
struct LogsViewTests {
  @MainActor
  @Test func LogViewsCoverFilterActionsCompactStatusRowsAndSupplementalRawJSON() throws {
    var selection = OperatorLogFilter.all
    let binding = Binding(
      get: { selection },
      set: { selection = $0 }
    )

    OperatorLogsPane.setLogFilter(selection: binding, filter: .alerts)
    #expect(selection == .alerts)

    OperatorLogsPane.makeLogFilterAction(selection: binding, filter: .messages)()
    #expect(selection == .messages)

    let statusEvent = AgentRawEvent(
      sessionID: SessionID("session-status"),
      provider: "copilot_cli",
      sequence: EventSequence(10),
      timestamp: "2026-03-24T03:00:10Z",
      rawJSON: #"{"type":"status","message":"Queued"}"#,
      providerEventType: "status",
      normalizedEventKind: "status"
    )
    let usageEvent = AgentRawEvent(
      sessionID: SessionID("session-usage"),
      provider: "codex",
      sequence: EventSequence(11),
      timestamp: "2026-03-24T03:00:11Z",
      rawJSON: #"{"tokens":{"total":21}}"#,
      providerEventType: "usage",
      normalizedEventKind: "usage"
    )
    let supplementalEvent = AgentRawEvent(
      sessionID: SessionID("session-unknown"),
      provider: "claude_code",
      sequence: EventSequence(12),
      timestamp: "2026-03-24T03:00:12Z",
      rawJSON: #"{"payload":{"notes":"inspect raw payload"}}"#,
      providerEventType: "provider_custom",
      normalizedEventKind: "unexpected_kind"
    )

    do {
      let compactTheme = OperatorTheme(compact: true)
      let regularTheme = OperatorTheme(compact: false)
      let model = SymphonyOperatorModel(client: PassiveSymphonyAPIClient())
      model.liveStatus = "Queued"
      model.selectedLogFilter = .all
      model.logEvents = [statusEvent, usageEvent, supplementalEvent]

      render(
        host(
          OperatorLogsPane(model: model, theme: regularTheme), width: 960,
          height: 720))
      render(
        host(
          OperatorLogsPane(model: model, theme: compactTheme), width: 320,
          height: 720))
      render(
        host(
          LogTimelinePanel(theme: compactTheme, logEvents: [statusEvent, usageEvent]),
          width: 320,
          height: 420
        ))
      render(
        host(
          LogEventRow(
            theme: compactTheme,
            event: statusEvent,
            presentation: SymphonyEventPresentation(event: statusEvent),
            isLast: false
          ),
          width: 320,
          height: 220
        ))
      render(
        host(
          LogEventRow(
            theme: regularTheme,
            event: usageEvent,
            presentation: SymphonyEventPresentation(event: usageEvent),
            isLast: false
          ),
          width: 720,
          height: 220
        ))
      render(
        host(
          LogEventRow(
            theme: compactTheme,
            event: supplementalEvent,
            presentation: SymphonyEventPresentation(event: supplementalEvent),
            isLast: true
          ),
          width: 320,
          height: 260
        ))
    }
  }

  @Test func LogsAndThemeHelpersCoverFilterActionsTimelineStatesAndSelectionBackground() throws {
    let regularTheme = OperatorTheme(compact: false)
    let compactTheme = OperatorTheme(compact: true)

    _ = compactTheme.rowSpacing
    _ = regularTheme.rowSpacing
    _ = compactTheme.iconSize
    _ = regularTheme.iconSize
    _ = regularTheme.selectedFill
    _ = regularTheme.selectedStroke
    let logFilterPalette = OperatorLogsPane.logFilterPalette()
    _ = logFilterPalette.selectedFill
    _ = logFilterPalette.unselectedFill
    _ = logFilterPalette.unselectedStroke

    let messageMarkerStyle = OperatorLogTimelineMarkerStyle(for: .message)
    #expect(messageMarkerStyle.fillRole == .accent)
    #expect(messageMarkerStyle.markerSize == 20)
    #expect(messageMarkerStyle.symbolSize == 10)

    let toolMarkerStyle = OperatorLogTimelineMarkerStyle(for: .tool)
    #expect(toolMarkerStyle.symbolName == "hammer.fill")
    #expect(toolMarkerStyle.fillRole == .toolHighContrast)

    let supplementalMarkerStyle = OperatorLogTimelineMarkerStyle(for: .supplemental)
    #expect(supplementalMarkerStyle.fillRole == .supplemental)

    #expect(statusSymbol("failed") == "xmark.octagon.fill")
    #expect(statusSymbol("queued") == "clock.badge.exclamationmark.fill")
    #expect(statusSymbol("completed") == "checkmark.circle.fill")
    #expect(statusSymbol("running") == "bolt.horizontal.circle.fill")
    #expect(statusSymbol("idle") == "circle.fill")

    var filter = OperatorLogFilter.all
    let filterBinding = Binding(
      get: { filter },
      set: { filter = $0 }
    )

    OperatorLogsPane.makeLogFilterAction(selection: filterBinding, filter: .messages)()
    #expect(filter == .messages)
    OperatorLogsPane.makeLogFilterAction(selection: filterBinding, filter: .tools)()
    #expect(filter == .tools)
    OperatorLogsPane.makeLogFilterAction(selection: filterBinding, filter: .alerts)()
    #expect(filter == .alerts)
    render(
      host(
        OperatorLogsPane.makeSegmentedLogFilterPicker(selection: filterBinding),
        width: 420,
        height: 80
      )
    )

    let messageEvent = makeEvent(
      sequence: 1,
      kind: "message",
      rawJSON: #"{"message":"hello"}"#
    )
    let toolEvent = makeEvent(
      sequence: 2,
      kind: "tool_call",
      rawJSON: #"{"arguments":"pwd"}"#
    )
    let compactEvent = makeEvent(
      sequence: 3,
      kind: "status",
      rawJSON: #"{"status":"queued"}"#
    )
    let approvalEvent = makeEvent(
      sequence: 4,
      kind: "approval_request",
      rawJSON: #"{"message":"approve?"}"#
    )
    let errorEvent = makeEvent(
      sequence: 5,
      kind: "error",
      rawJSON: #"{"message":"fail"}"#
    )
    let supplementalEvent = AgentRawEvent(
      sessionID: SessionID("session-42"),
      provider: "claude_code",
      sequence: EventSequence(6),
      timestamp: "2026-03-24T00:00:06Z",
      rawJSON: #"{"payload":{"notes":"inspect raw payload"}}"#,
      providerEventType: "provider_custom",
      normalizedEventKind: "unexpected_kind"
    )

    do {
      render(
        host(
          EmptyStatePanel(
            theme: regularTheme,
            systemImage: "tray",
            title: "Nothing here yet"
          ),
          width: 480,
          height: 220
        ))
      let model = SymphonyOperatorModel(client: PassiveSymphonyAPIClient())
      model.liveStatus = "Running"
      model.selectedLogFilter = .all
      model.logEvents = [
        messageEvent,
        toolEvent,
        compactEvent,
        approvalEvent,
        errorEvent,
        supplementalEvent,
      ]

      render(
        host(
          OperatorLogsPane(model: model, theme: regularTheme), width: 960,
          height: 900))
      render(
        host(
          OperatorLogsPane(model: model, theme: compactTheme), width: 320,
          height: 900))
      render(
        host(
          LogTimelinePanel(theme: regularTheme, logEvents: []), width: 960,
          height: 320)
      )
      render(
        host(
          LogTimelinePanel(
            theme: regularTheme,
            logEvents: [
              messageEvent,
              toolEvent,
              compactEvent,
              approvalEvent,
              errorEvent,
              supplementalEvent,
            ]
          ),
          width: 960,
          height: 900
        ))
      render(
        host(
          LogEventRow(
            theme: regularTheme,
            event: messageEvent,
            presentation: SymphonyEventPresentation(event: messageEvent),
            isLast: false
          ),
          width: 720,
          height: 220
        ))
      render(
        host(
          LogEventRow(
            theme: regularTheme,
            event: toolEvent,
            presentation: SymphonyEventPresentation(event: toolEvent),
            isLast: false
          ),
          width: 720,
          height: 220
        ))
      render(
        host(
          LogEventRow(
            theme: regularTheme,
            event: compactEvent,
            presentation: SymphonyEventPresentation(event: compactEvent),
            isLast: false
          ),
          width: 720,
          height: 220
        ))
      render(
        host(
          LogEventRow(
            theme: regularTheme,
            event: approvalEvent,
            presentation: SymphonyEventPresentation(event: approvalEvent),
            isLast: false
          ),
          width: 720,
          height: 220
        ))
      render(
        host(
          LogEventRow(
            theme: regularTheme,
            event: errorEvent,
            presentation: SymphonyEventPresentation(event: errorEvent),
            isLast: false
          ),
          width: 720,
          height: 220
        ))
      render(
        host(
          LogEventRow(
            theme: regularTheme,
            event: supplementalEvent,
            presentation: SymphonyEventPresentation(event: supplementalEvent),
            isLast: true
          ),
          width: 720,
          height: 240
        ))
      render(
        host(
          LogEventRow(
            theme: regularTheme,
            event: supplementalEvent,
            presentation: SymphonyEventPresentation(
              rowStyle: .supplemental,
              title: "",
              detail: "Detail-only accessibility label",
              metadata: "claude_code • #6 • provider_custom",
              showsRawJSON: true
            ),
            isLast: true
          ),
          width: 720,
          height: 240
        ))
      render(
        host(
          Text("Selected").operatorSelectionBackground(regularTheme, isSelected: true),
          width: 240,
          height: 100
        ))
      render(
        host(
          Text("Unselected").operatorSelectionBackground(regularTheme, isSelected: false),
          width: 240,
          height: 100
        ))
    }
  }
}
