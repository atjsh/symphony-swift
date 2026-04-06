import SwiftUI
import UniformTypeIdentifiers

import SymphonyValidationGallery

/// Container view that embeds the validation gallery and runner into SymphonySwiftUIApp.
///
/// Stores are owned by SymphonyApp and passed in so that the Commands struct
/// can share the same store instances.
///
///     ┌─────────────────────────────────────────────────┐
///     │ ValidationGalleryContainerView                   │
///     │                                                  │
///     │  TabView                                         │
///     │  ├─ Tab "Gallery"                                │
///     │  │   └─ ValidationGalleryRootView (from library) │
///     │  │       ├─ onOpenBundle → importController      │
///     │  │       ├─ onOpenManifest → importController    │
///     │  │       └─ onRequestExport → exportController   │
///     │  │                                               │
///     │  └─ Tab "Runner"                                 │
///     │      └─ ValidationRunnerView (from library)      │
///     │          └─ connects to validation server HTTP   │
///     └─────────────────────────────────────────────────┘
struct ValidationGalleryContainerView: View {
  var store: ValidationGalleryStore
  var runnerStore: ValidationRunnerStore
  @Bindable var importController: ValidationGalleryImportController
  @Bindable var exportController: ValidationGalleryExportController

  @State private var hasBootstrapped = false

  init(
    store: ValidationGalleryStore,
    runnerStore: ValidationRunnerStore,
    importController: ValidationGalleryImportController,
    exportController: ValidationGalleryExportController
  ) {
    self.store = store
    self.runnerStore = runnerStore
    self.importController = importController
    self.exportController = exportController
  }

  var body: some View {
    TabView {
      Tab("Gallery", systemImage: "photo.on.rectangle") {
        galleryContentView
      }
      .accessibilityIdentifier("galleryTab")

      Tab("Runner", systemImage: "play.rectangle") {
        ValidationRunnerView(store: runnerStore)
      }
      .accessibilityIdentifier("runnerTab")
    }
    .task {
      await bootstrapIfNeeded()
    }
  }

  @MainActor
  private func bootstrapIfNeeded() async {
    guard hasBootstrapped == false else {
      return
    }
    hasBootstrapped = true

    let action = ValidationGalleryBootstrapResolver.resolve(
      arguments: ProcessInfo.processInfo.arguments,
      environment: ProcessInfo.processInfo.environment
    )

    switch action {
    case .open(let source, let rememberRecent):
      await store.open(source, rememberRecent: rememberRecent)
    case .restoreLastOpenedBundle:
      await store.restoreLastOpenedBundle()
    case .none:
      return
    }
  }

  private var galleryContentView: some View {
    ValidationGalleryRootView(
      store: store,
      onOpenBundle: { importController.request(.bundle) },
      onOpenManifest: { importController.request(.manifest) },
      onRequestExport: { exportController.requestExport(scope: $0) },
      exportFeedback: exportController.feedbackMessage,
      isModalPresentationActive: exportController.request != nil
    )
    .overlay(alignment: .bottomTrailing) {
      if importController.capturesRequests {
        Text(importController.requestedImportKind?.rawValue ?? "none")
          .font(.caption2)
          .opacity(0.01)
          .padding(4)
          .accessibilityIdentifier("import-request-marker")
      }
    }
    .alert(
      "Couldn't Export Comments",
      isPresented: exportErrorIsPresented
    ) {
      Button("OK", role: .cancel) {
        exportController.dismissError()
      }
    } message: {
      Text(exportController.error?.errorDescription ?? "Unknown export error.")
    }
    .sheet(
      item: Binding(
        get: { exportController.request },
        set: { exportController.request = $0 }
      )
    ) { _ in
      ValidationGalleryExportSheet(controller: exportController, store: store)
    }
    .fileImporter(
      isPresented: $importController.isBundleImporterPresented,
      allowedContentTypes: [.directory]
    ) { result in
      importController.complete(.bundle)
      handleImport(result: result) { .folder($0) }
    }
    .fileImporter(
      isPresented: $importController.isManifestImporterPresented,
      allowedContentTypes: [.json]
    ) { result in
      importController.complete(.manifest)
      handleImport(result: result) { .manifestFile($0) }
    }
    .fileExporter(
      isPresented: $exportController.isPackageExporterPresented,
      document: exportController.packageDocument,
      contentType: ValidationGalleryCommentExportPackageDocument.packageContentType,
      defaultFilename: exportController.packageDefaultFilename
    ) { result in
      exportController.completePackageExport(result: result, store: store)
    }
  }

  private func handleImport(
    result: Result<URL, Error>,
    sourceBuilder: @escaping (URL) -> ValidationBundleSource
  ) {
    switch result {
    case .success(let url):
      Task {
        await store.open(sourceBuilder(url))
      }
    case .failure(let error):
      store.present(error: .loadFailed(error.localizedDescription))
    }
  }

  private var exportErrorIsPresented: Binding<Bool> {
    Binding(
      get: { exportController.error != nil },
      set: { isPresented in
        if isPresented == false {
          exportController.dismissError()
        }
      }
    )
  }
}
