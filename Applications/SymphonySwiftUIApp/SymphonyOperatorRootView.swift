import Foundation
import SwiftUI
import SymphonyShared

public struct SymphonyOperatorRootView: View {
  @ObservedObject var model: SymphonyOperatorModel
  @State private var isEndpointEditorPresented = false
  @State private var columnVisibility: NavigationSplitViewVisibility = .all
  private let compactOverride: Bool?

  #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  #endif

  private var isCompact: Bool {
    if let compactOverride {
      return compactOverride
    }
    #if os(iOS)
      return horizontalSizeClass == .compact
    #else
      return false
    #endif
  }

  private var theme: OperatorTheme {
    OperatorTheme(compact: isCompact)
  }

  public init(model: SymphonyOperatorModel) {
    self.model = model
    self.compactOverride = nil
  }

  init(
    model: SymphonyOperatorModel,
    initialEndpointEditorPresentation: Bool = false,
    initialColumnVisibility: NavigationSplitViewVisibility = .all,
    compactOverride: Bool? = nil
  ) {
    self.model = model
    self.compactOverride = compactOverride
    _isEndpointEditorPresented = State(initialValue: initialEndpointEditorPresentation)
    _columnVisibility = State(initialValue: initialColumnVisibility)
  }

  public var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      OperatorSidebarView(
        model: model,
        theme: theme,
        openServerEditor: makePresentationAction(for: $isEndpointEditorPresented),
        selectIssue: makeIssueSelectionHandler()
      )
    } detail: {
      OperatorDetailView(
        model: model,
        theme: theme,
        selectRun: makeRunSelectionHandler()
      )
    }
    .navigationSplitViewStyle(.balanced)
    .toolbar {
      #if os(iOS)
        if isCompact, model.selectedIssueID != nil, columnVisibility == .detailOnly {
          ToolbarItem(placement: .topBarLeading) {
            Button("Issues", systemImage: "sidebar.left", action: makeRevealIssuesSidebarAction())
          }
        }
      #endif

      ToolbarItem(placement: .primaryAction) {
        Button("Refresh", systemImage: "arrow.clockwise", action: makeRefreshAction())
          .disabled(model.isConnecting || model.isRefreshing)
          .accessibilityIdentifier("refresh-button")
      }

      #if os(iOS)
        ToolbarItem(placement: .topBarLeading) {
          Button(
            "Server",
            systemImage: "slider.horizontal.3",
            action: makePresentationAction(for: $isEndpointEditorPresented)
          )
          .accessibilityIdentifier("server-editor-button")
        }
      #else
        ToolbarItem(placement: .primaryAction) {
          Button(
            "Server",
            systemImage: "slider.horizontal.3",
            action: makePresentationAction(for: $isEndpointEditorPresented)
          )
          .accessibilityIdentifier("server-editor-button")
        }
      #endif
    }
    .sheet(isPresented: $isEndpointEditorPresented, content: makeEndpointEditorView)
  }
}

extension SymphonyOperatorRootView {
  @MainActor
  func makePresentationAction(for isPresented: Binding<Bool>) -> () -> Void {
    { isPresented.wrappedValue = true }
  }

  func makeConnectAction() -> () -> Void {
    { triggerConnect() }
  }

  func makeRefreshAction() -> () -> Void {
    { triggerRefresh() }
  }

  func makeRevealIssuesSidebarAction() -> () -> Void {
    makeRevealIssuesSidebarAction(for: $columnVisibility)
  }

  func makeRevealIssuesSidebarAction(for columnVisibility: Binding<NavigationSplitViewVisibility>) -> () -> Void {
    { columnVisibility.wrappedValue = .all }
  }

  func triggerConnect() {
    Task { await model.connect() }
  }

  func triggerRefresh() {
    Task { await model.refresh() }
  }

  func triggerIssueSelection(_ issue: IssueSummary) {
    columnVisibility = operatorColumnVisibilityAfterIssueSelection(
      isCompact: isCompact,
      current: columnVisibility
    )
    Task { await model.selectIssue(issue) }
  }

  func triggerRunSelection(_ runID: RunID) {
    if model.selectedRunID == runID, model.runDetail?.runID == runID {
      return
    }
    Task { await model.selectRun(runID) }
  }

  func makeIssueSelectionAction(for issue: IssueSummary) -> () -> Void {
    { triggerIssueSelection(issue) }
  }

  func makeIssueSelectionHandler() -> (IssueSummary) -> Void {
    triggerIssueSelection
  }

  func makeRunSelectionAction(for runID: RunID) -> () -> Void {
    { triggerRunSelection(runID) }
  }

  func makeRunSelectionHandler() -> (RunID) -> Void {
    triggerRunSelection
  }

  func makeEndpointEditorView() -> OperatorEndpointEditorView {
    OperatorEndpointEditorView(model: model)
  }
}

@MainActor
func operatorColumnVisibilityAfterIssueSelection(
  isCompact: Bool,
  current: NavigationSplitViewVisibility
) -> NavigationSplitViewVisibility {
  isCompact ? .detailOnly : current
}

#if DEBUG
  #Preview {
    SymphonyOperatorRootView(model: SymphonyOperatorModel())
  }
#endif
