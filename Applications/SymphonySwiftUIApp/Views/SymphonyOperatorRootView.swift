import Foundation
import SwiftUI
import SymphonyShared

public struct SymphonyOperatorRootView: View {
  @Bindable var model: SymphonyOperatorModel
  @State private var isEndpointEditorPresented = false
  @State private var columnVisibility: NavigationSplitViewVisibility = .all
  @State private var serverEditorMode: ServerEditorMode = .localServer
  private let compactOverride: Bool?

  #if os(macOS)
    @Environment(\.openWindow) private var openWindow
  #endif

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
        openLocalServerEditor: makeOpenEditorAction(mode: .localServer),
        openExistingServerEditor: makeOpenEditorAction(mode: .existingServer),
        selectIssue: makeIssueSelectionHandler()
      )
    } detail: {
      #if os(macOS)
        OperatorDetailView(
          model: model,
          theme: theme,
          selectRun: makeRunSelectionHandler(),
          openLocalServerEditor: { openWindow(id: "server-editor") },
          openExistingServerEditor: { openWindow(id: "server-editor") }
        )
        .backgroundExtensionEffect()
      #else
        OperatorDetailView(
          model: model,
          theme: theme,
          selectRun: makeRunSelectionHandler()
        )
        .backgroundExtensionEffect()
      #endif
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
          .symbolEffect(.rotate, isActive: model.isRefreshing)
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
            systemImage: "slider.horizontal.3"
          ) {
            openWindow(id: "server-editor")
          }
          .accessibilityIdentifier("server-editor-button")
        }
      #endif
    }
    #if os(macOS)
      .frame(minWidth: 1024, idealWidth: 1280, minHeight: 680, idealHeight: 820, alignment: .topLeading)
      .onReceive(NotificationCenter.default.publisher(for: .symphonyOpenServerEditor)) { _ in
        openWindow(id: "server-editor")
      }
    #endif
    .sheet(isPresented: $isEndpointEditorPresented, content: makeEndpointEditorSheet)
  }
}

extension SymphonyOperatorRootView {
  @MainActor
  func makePresentationAction(for isPresented: Binding<Bool>) -> () -> Void {
    { isPresented.wrappedValue = true }
  }

  @MainActor
  func makeServerEditorAction(mode: ServerEditorMode) -> () -> Void {
    {
      serverEditorMode = mode
      #if os(macOS)
        model.prepareLocalServerEditor(mode: mode)
      #endif
      isEndpointEditorPresented = true
    }
  }

  @MainActor
  func makeOpenEditorAction(mode: ServerEditorMode) -> () -> Void {
    #if os(macOS)
      return {
        model.prepareLocalServerEditor(mode: mode)
        openWindow(id: "server-editor")
      }
    #else
      return makeServerEditorAction(mode: mode)
    #endif
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
    columnVisibility = Self.columnVisibilityAfterIssueSelection(
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
    #if os(macOS)
      OperatorEndpointEditorView(model: model, initialMode: serverEditorMode)
    #else
      OperatorEndpointEditorView(model: model)
    #endif
  }

  @ViewBuilder
  func makeEndpointEditorSheet() -> some View {
    #if os(macOS)
      makeEndpointEditorView()
        .presentationSizing(.fitted)
    #else
      makeEndpointEditorView()
    #endif
  }
}

extension SymphonyOperatorRootView {
  @MainActor
  static func columnVisibilityAfterIssueSelection(
    isCompact: Bool,
    current: NavigationSplitViewVisibility
  ) -> NavigationSplitViewVisibility {
    isCompact ? .detailOnly : current
  }
}

#if DEBUG
  #Preview {
    SymphonyOperatorRootView(model: SymphonyOperatorModel())
  }
#endif
