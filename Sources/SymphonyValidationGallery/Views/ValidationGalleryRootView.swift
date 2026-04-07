import SwiftUI

public struct ValidationGalleryRootView: View {
  @Bindable var store: ValidationGalleryStore
  let onOpenBundle: () -> Void
  let onOpenManifest: () -> Void
  let onRequestExport: (ValidationGalleryCommentExportScope) -> Void
  let exportFeedback: String?
  let isModalPresentationActive: Bool
  let usesToolbarSearch: Bool
  @State private var sheetRoute: ValidationGalleryArtifactSheetRoute?
  @State private var sheetMode: ValidationGalleryArtifactPresentationMode = .preview
  @State private var pendingExportScope: ValidationGalleryCommentExportScope?
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  public init(
    store: ValidationGalleryStore,
    onOpenBundle: @escaping () -> Void,
    onOpenManifest: @escaping () -> Void,
    onRequestExport: @escaping (ValidationGalleryCommentExportScope) -> Void,
    exportFeedback: String? = nil,
    isModalPresentationActive: Bool = false,
    usesToolbarSearch: Bool = true
  ) {
    self.store = store
    self.onOpenBundle = onOpenBundle
    self.onOpenManifest = onOpenManifest
    self.onRequestExport = onRequestExport
    self.exportFeedback = exportFeedback
    self.isModalPresentationActive = isModalPresentationActive
    self.usesToolbarSearch = usesToolbarSearch
  }

  public var body: some View {
    Group {
      if horizontalSizeClass == .regular, store.snapshot != nil {
        NavigationSplitView {
          ValidationGallerySidebar(store: store, onOpenRecent: { recent in
            Task { await store.openRecent(recent) }
          })
          .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        } content: {
          browserView(compact: false)
            .navigationSplitViewColumnWidth(
              min: regularBrowserColumnMinimumWidth,
              ideal: regularBrowserColumnIdealWidth,
              max: regularBrowserColumnMaximumWidth
            )
        } detail: {
          inspectorView
            .navigationSplitViewColumnWidth(min: 520, ideal: 700, max: 960)
        }
        .navigationSplitViewStyle(.balanced)
      } else {
        NavigationStack {
          browserView(compact: horizontalSizeClass != .regular)
            .navigationTitle("Validation Gallery")
            .modifier(ConditionalSearchable(text: $store.searchText, isEnabled: usesToolbarSearch))
            .toolbar { primaryActionToolbarContent }
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Validation Gallery")
    .accessibilityIdentifier("validation-gallery-root")
    .accessibilityHidden(isModalPresentationActive)
    .modifier(ConditionalSearchable(text: $store.searchText, isEnabled: usesToolbarSearch && horizontalSizeClass == .regular))
    .toolbar {
      if horizontalSizeClass == .regular, store.snapshot != nil {
        ToolbarItem(placement: .secondaryAction) {
            HStack(spacing: 0) {
              ControlGroup {
                Button {
                  store.setBrowserDisplayMode(.list)
                } label: {
                  Image(systemName: "list.bullet")
                    .foregroundStyle(.primary)
                    .padding(2)
                    .background(
                      store.workspacePreferences.browserDisplayMode == .list
                        ? AnyShapeStyle(Color.accentColor.opacity(0.15))
                        : AnyShapeStyle(Color.clear),
                      in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                    )
                }
                .accessibilityLabel("List Browser")
                .accessibilityValue(
                  Text("Current"),
                  isEnabled: store.workspacePreferences.browserDisplayMode == .list
                )
                .accessibilityIdentifier("workspace-display-mode-list-button")

                Button {
                  store.setBrowserDisplayMode(.grid)
                } label: {
                  Image(systemName: "square.grid.2x2")
                    .foregroundStyle(.primary)
                    .padding(2)
                    .background(
                      store.workspacePreferences.browserDisplayMode == .grid
                        ? AnyShapeStyle(Color.accentColor.opacity(0.15))
                        : AnyShapeStyle(Color.clear),
                      in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                    )
                }
                .accessibilityLabel("Grid Browser")
                .accessibilityValue(
                  Text("Current"),
                  isEnabled: store.workspacePreferences.browserDisplayMode == .grid
                )
                .accessibilityIdentifier("workspace-display-mode-grid-button")
              } label: {
                Label("Browser Display Mode", systemImage: "rectangle.grid.1x2")
              }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Browser Display Mode")
            .accessibilityValue(browserDisplayModeAccessibilityValue)
            .accessibilityIdentifier("workspace-display-mode-picker")
          }

          ToolbarItem(placement: .secondaryAction) {
            HStack(spacing: 0) {
              ControlGroup {
                Button {
                  store.setMacPreviewEmphasis(.standard)
                } label: {
                  Image(systemName: "rectangle.split.3x1")
                    .foregroundStyle(.primary)
                    .padding(2)
                    .background(
                      store.workspacePreferences.macPreviewEmphasis == .standard
                        ? AnyShapeStyle(Color.accentColor.opacity(0.15))
                        : AnyShapeStyle(Color.clear),
                      in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                    )
                }
                .accessibilityLabel("Standard Preview Emphasis")
                .accessibilityValue(
                  Text("Current"),
                  isEnabled: store.workspacePreferences.macPreviewEmphasis == .standard
                )
                .accessibilityIdentifier("workspace-preview-emphasis-standard-button")

                Button {
                  store.setMacPreviewEmphasis(.expanded)
                } label: {
                  Image(systemName: "rectangle.trailinghalf.inset.filled")
                    .foregroundStyle(.primary)
                    .padding(2)
                    .background(
                      store.workspacePreferences.macPreviewEmphasis == .expanded
                        ? AnyShapeStyle(Color.accentColor.opacity(0.15))
                        : AnyShapeStyle(Color.clear),
                      in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                    )
                }
                .accessibilityLabel("Expanded Preview Emphasis")
                .accessibilityValue(
                  Text("Current"),
                  isEnabled: store.workspacePreferences.macPreviewEmphasis == .expanded
                )
                .accessibilityIdentifier("workspace-preview-emphasis-expanded-button")
              } label: {
                Label("Preview Emphasis", systemImage: "rectangle.expand.vertical")
              }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Preview Emphasis")
            .accessibilityValue(previewEmphasisAccessibilityValue)
            .accessibilityIdentifier("workspace-preview-emphasis-picker")
          }
      }

      if horizontalSizeClass == .regular {
        primaryActionToolbarContent
      }
    }
    .sheet(item: $sheetRoute) { route in
      if let artifact = artifact(for: route.artifactID) {
        previewSheet(for: artifact)
      }
    }
    .overlay(alignment: .topTrailing) {
      if let exportFeedback {
        Text(exportFeedback)
          .font(.footnote.weight(.semibold))
          .padding(.horizontal, 12)
          .padding(.vertical, 10)
          .background(.regularMaterial, in: Capsule())
          .padding()
          .transition(.move(edge: .top).combined(with: .opacity))
          .accessibilityIdentifier("comments-exported-toast")
      }
    }
    .focusedValue(\.galleryCommandActions, ValidationGalleryCommandActions(
      addPointComment: {
        guard let selectedArtifact = store.selectedArtifact, store.canCommentSelectedArtifact else { return }
        presentSheet(for: selectedArtifact, mode: .addPointComment)
      },
      addAreaComment: {
        guard let selectedArtifact = store.selectedArtifact, store.canCommentSelectedArtifact else { return }
        presentSheet(for: selectedArtifact, mode: .addAreaComment)
      },
      exportSelectedComments: { requestSelectedArtifactExport() },
      exportBundleComments: { requestBundleExport() }
    ))
    .onChange(of: sheetRoute?.id) { _, routeID in
      guard routeID == nil, let pendingExportScope else {
        return
      }

      self.pendingExportScope = nil
      onRequestExport(pendingExportScope)
    }
    .animation(.snappy(duration: 0.22), value: exportFeedback)
  }

  @ToolbarContentBuilder
  private var primaryActionToolbarContent: some ToolbarContent {
    ToolbarItemGroup(placement: .primaryAction) {
      Button("Open Bundle", systemImage: "folder.badge.plus", action: onOpenBundle)
        .accessibilityIdentifier("toolbar-open-validation-bundle-button")
      Button("Open Manifest", systemImage: "doc.badge.plus", action: onOpenManifest)
        .accessibilityIdentifier("toolbar-open-manifest-button")

      if let source = store.snapshot?.source {
        Button("Reload", systemImage: "arrow.clockwise") {
          Task { await store.open(source, rememberRecent: false) }
        }
        .disabled(store.isLoading)
      }

      if store.hasCommentsInCurrentBundle {
        Button("Export Bundle Comments", systemImage: "square.and.arrow.down") {
          requestBundleExport()
        }
        .accessibilityIdentifier("export-bundle-comments-button")
      }
    }
  }

  private func browserView(compact: Bool) -> some View {
    ValidationGalleryBrowserView(
      store: store,
      compact: compact,
      onOpenBundle: onOpenBundle,
      onOpenManifest: onOpenManifest,
      onPreviewArtifact: { presentSheet(for: $0, mode: .preview) },
      onAddPointComment: { presentSheet(for: $0, mode: .addPointComment) },
      onAddAreaComment: { presentSheet(for: $0, mode: .addAreaComment) },
      onExportComments: requestSelectedArtifactExport
    )
  }

  private var inspectorView: some View {
    ValidationGalleryInspectorView(
      store: store,
      onPreviewArtifact: { presentSheet(for: $0, mode: .preview) },
      onAddPointComment: { presentSheet(for: $0, mode: .addPointComment) },
      onAddAreaComment: { presentSheet(for: $0, mode: .addAreaComment) },
      onExportComments: requestSelectedArtifactExport
    )
  }

  private var regularBrowserColumnMinimumWidth: CGFloat {
    switch store.workspacePreferences.browserDisplayMode {
    case .list:
      return 260
    case .grid:
      return 340
    }
  }

  private var regularBrowserColumnIdealWidth: CGFloat {
    switch (store.workspacePreferences.browserDisplayMode, store.workspacePreferences.macPreviewEmphasis) {
    case (.list, .standard):
      return 330
    case (.list, .expanded):
      return 290
    case (.grid, .standard):
      return 420
    case (.grid, .expanded):
      return 360
    }
  }

  private var regularBrowserColumnMaximumWidth: CGFloat {
    switch store.workspacePreferences.browserDisplayMode {
    case .list:
      return 380
    case .grid:
      return 500
    }
  }

  private var browserDisplayModeAccessibilityValue: String {
    switch store.workspacePreferences.browserDisplayMode {
    case .list:
      "List"
    case .grid:
      "Grid"
    }
  }

  private var previewEmphasisAccessibilityValue: String {
    switch store.workspacePreferences.macPreviewEmphasis {
    case .standard:
      "Standard"
    case .expanded:
      "Expanded"
    }
  }

  @ViewBuilder
  private func previewSheet(
    for artifact: ValidationGalleryArtifact
  ) -> some View {
    let detailView = ValidationGalleryArtifactSheetView(
      store: store,
      artifact: artifact,
      mode: $sheetMode,
      onDismissRequested: { sheetRoute = nil },
      onExportComments: requestSelectedArtifactExport
    )

    detailView.presentationSizing(.page)
  }

  private func presentSheet(
    for artifact: ValidationGalleryArtifact,
    mode: ValidationGalleryArtifactPresentationMode
  ) {
    guard mode == .preview || artifact.record.artifactType == .screenshot else {
      return
    }

    sheetMode = mode
    if sheetRoute?.artifactID != artifact.id {
      sheetRoute = ValidationGalleryArtifactSheetRoute(artifactID: artifact.id)
    }
  }

  private func artifact(for artifactID: ValidationGalleryArtifact.ID) -> ValidationGalleryArtifact? {
    store.snapshot?.artifacts.first(where: { $0.id == artifactID })
  }

  private func requestSelectedArtifactExport() {
    requestExport(.selectedArtifact)
  }

  private func requestBundleExport() {
    requestExport(.currentBundle)
  }

  private func requestExport(_ scope: ValidationGalleryCommentExportScope) {
    if sheetRoute != nil {
      pendingExportScope = scope
      sheetRoute = nil
      return
    }

    onRequestExport(scope)
  }
}

private struct ValidationGalleryArtifactSheetRoute: Identifiable, Equatable {
  let artifactID: ValidationGalleryArtifact.ID

  var id: String {
    "\(artifactID)"
  }
}

public struct ValidationGalleryCommandActions {
  public let addPointComment: () -> Void
  public let addAreaComment: () -> Void
  public let exportSelectedComments: () -> Void
  public let exportBundleComments: () -> Void

  public init(
    addPointComment: @escaping () -> Void,
    addAreaComment: @escaping () -> Void,
    exportSelectedComments: @escaping () -> Void,
    exportBundleComments: @escaping () -> Void
  ) {
    self.addPointComment = addPointComment
    self.addAreaComment = addAreaComment
    self.exportSelectedComments = exportSelectedComments
    self.exportBundleComments = exportBundleComments
  }
}

public struct ValidationGalleryCommandActionsKey: FocusedValueKey {
  public typealias Value = ValidationGalleryCommandActions
}

public extension FocusedValues {
  var galleryCommandActions: ValidationGalleryCommandActions? {
    get { self[ValidationGalleryCommandActionsKey.self] }
    set { self[ValidationGalleryCommandActionsKey.self] = newValue }
  }
}

private struct ValidationGallerySidebar: View {
  @Bindable var store: ValidationGalleryStore
  let onOpenRecent: (ValidationRecentBundle) -> Void

  var body: some View {
    List(selection: sidebarSelectionBinding) {
      Section("Browse") {
        Label("All Artifacts", systemImage: "square.grid.2x2")
          .tag(ValidationGallerySidebarSelection?.some(.all))
          .accessibilityIdentifier("sidebar-selection-all")
          .onTapGesture { store.sidebarSelection = .all }
      }

      ForEach(store.snapshot?.platformSections ?? []) { platformSection in
        Section(ValidationGalleryFormatting.platformTitle(platformSection.platform)) {
          Label(
            ValidationGalleryFormatting.platformTitle(platformSection.platform),
            systemImage: "rectangle.stack"
          )
            .tag(ValidationGallerySidebarSelection?.some(.platform(platformSection.platform)))
            .accessibilityIdentifier("sidebar-platform-\(ValidationGalleryFormatting.sanitizeForIdentifier(platformSection.platform))")
            .onTapGesture { store.sidebarSelection = .platform(platformSection.platform) }

          ForEach(platformSection.plans) { planSection in
            Label(
              ValidationGalleryFormatting.planTitle(planSection.plan),
              systemImage: "list.bullet.rectangle"
            )
              .tag(
                ValidationGallerySidebarSelection?.some(
                  .plan(platform: planSection.platform, plan: planSection.plan)
                )
              )
              .accessibilityIdentifier(
                "sidebar-plan-\(ValidationGalleryFormatting.sanitizeForIdentifier(planSection.platform))-\(ValidationGalleryFormatting.sanitizeForIdentifier(planSection.plan))"
              )
              .onTapGesture { store.sidebarSelection = .plan(platform: planSection.platform, plan: planSection.plan) }
          }
        }
      }

      if store.recentBundles.isEmpty == false {
        Section("Recent") {
          ForEach(store.recentBundles) { recent in
            Button {
              onOpenRecent(recent)
            } label: {
              ValidationGalleryRecentBundleRow(recent: recent)
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
    .listStyle(.sidebar)
    .animation(.snappy(duration: 0.24), value: store.sidebarSelection)
    .frame(minWidth: 200, idealWidth: 220, maxWidth: 240)
    .accessibilityIdentifier("validation-gallery-sidebar")
  }

  private var sidebarSelectionBinding: Binding<ValidationGallerySidebarSelection?> {
    Binding(
      get: { store.sidebarSelection },
      set: { newSelection in
        store.sidebarSelection = newSelection ?? .all
      }
    )
  }
}

private struct ValidationGalleryRecentBundleRow: View {
  let recent: ValidationRecentBundle

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(ValidationGalleryFormatting.recentBundleTitle(recent))
        .font(.subheadline.weight(.medium))
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)

      if let subtitle = ValidationGalleryFormatting.recentBundleSubtitle(recent) {
        Text(subtitle)
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .minimumScaleFactor(0.85)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}
