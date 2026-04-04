import Observation
import SwiftUI
import UniformTypeIdentifiers

import SymphonyValidationGallery

#if os(macOS)
  import AppKit
#endif

enum XcodeValidationGalleryImportKind: String, Equatable, Sendable {
  case bundle
  case manifest
}

@MainActor
@Observable
final class XcodeValidationGalleryImportController {
  let capturesRequests: Bool
  var requestedImportKind: XcodeValidationGalleryImportKind?
  var isBundleImporterPresented = false
  var isManifestImporterPresented = false

  init(environment: [String: String] = ProcessInfo.processInfo.environment) {
    capturesRequests = environment["XCODE_VALIDATION_GALLERY_UI_TEST_CAPTURE_IMPORT_REQUESTS"] == "1"
  }

  func request(_ kind: XcodeValidationGalleryImportKind) {
    requestedImportKind = kind

    guard capturesRequests == false else {
      return
    }

    switch kind {
    case .bundle:
      isBundleImporterPresented = true
    case .manifest:
      isManifestImporterPresented = true
    }
  }

  func complete(_ kind: XcodeValidationGalleryImportKind) {
    switch kind {
    case .bundle:
      isBundleImporterPresented = false
    case .manifest:
      isManifestImporterPresented = false
    }
  }
}

import SymphonyXcodeValidationServerCore

@main
struct XcodeValidationGalleryApp: App {
  @State private var store: ValidationGalleryStore
  @State private var runnerStore: ValidationRunnerStore
  @State private var importController: XcodeValidationGalleryImportController
  @State private var exportController: XcodeValidationGalleryExportController
  @State private var hasBootstrapped = false
  @FocusedValue(\.galleryCommandActions) private var galleryActions

  init() {
    let environment = ProcessInfo.processInfo.environment
    _store = State(
      initialValue: ValidationGalleryStore(
        loader: ValidationBundleLoader(),
        recentBundleStore: Self.makeRecentBundleStore(environment: environment),
        workspacePreferencesStore: Self.makeWorkspacePreferencesStore(environment: environment)
      )
    )
    let serverURL = URL(string: environment["XCODE_VALIDATION_SERVER_URL"] ?? "http://127.0.0.1:8090")
      ?? URL(string: "http://127.0.0.1:8090")!  // swiftlint:disable:this force_unwrapping
    _runnerStore = State(initialValue: ValidationRunnerStore(serverURL: serverURL))
    _importController = State(initialValue: XcodeValidationGalleryImportController(environment: environment))
    _exportController = State(initialValue: XcodeValidationGalleryExportController(environment: environment))
  }

  var body: some Scene {
    WindowGroup {
      rootView
    }
    #if os(macOS)
    .defaultLaunchBehavior(.presented)
    .defaultSize(width: 1480, height: 920)
    .windowResizability(.contentMinSize)
    .windowToolbarStyle(.automatic)
    #endif
    .commands {
      CommandGroup(after: .newItem) {
        Button("Open Validation Bundle…") {
          importController.request(.bundle)
        }
        .keyboardShortcut("o", modifiers: [.command])

        Button("Open Manifest File…") {
          importController.request(.manifest)
        }
        .keyboardShortcut("o", modifiers: [.command, .shift])

        if store.recentBundles.isEmpty == false {
          Divider()
          Menu("Open Recent") {
            ForEach(store.recentBundles) { recent in
              Button(ValidationGalleryFormatting.recentBundleMenuTitle(recent)) {
                Task { await store.openRecent(recent) }
              }
            }
          }
        }

        if store.canCommentSelectedArtifact {
          Divider()
          Menu("Comments") {
            Button("Add Point Comment") {
              galleryActions?.addPointComment()
            }
            .keyboardShortcut(";", modifiers: [.command])

            Button("Add Area Comment") {
              galleryActions?.addAreaComment()
            }
            .keyboardShortcut(";", modifiers: [.command, .shift])

            Button("Export Comments") {
              galleryActions?.exportSelectedComments()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
          }
        }

        if store.hasCommentsInCurrentBundle {
          Button("Export Bundle Comments") {
            galleryActions?.exportBundleComments()
          }
          .keyboardShortcut("b", modifiers: [.command, .shift])
        }
      }
    }
  }

  @MainActor
  private func bootstrapIfNeeded() async {
    guard hasBootstrapped == false else {
      return
    }
    hasBootstrapped = true

    let action = XcodeValidationGalleryBootstrapResolver.resolve(
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

  private var rootView: some View {
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
      "Couldn’t Export Comments",
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
      XcodeValidationGalleryExportSheet(controller: exportController, store: store)
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
      contentType: XcodeValidationGalleryCommentExportPackageDocument.packageContentType,
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

  private static func makeRecentBundleStore(
    environment: [String: String]
  ) -> UserDefaultsValidationRecentBundleStore {
    guard
      let suiteName = environment["XCODE_VALIDATION_GALLERY_UI_TEST_DEFAULTS_SUITE"],
      suiteName.isEmpty == false,
      let userDefaults = UserDefaults(suiteName: suiteName)
    else {
      return UserDefaultsValidationRecentBundleStore()
    }

    return UserDefaultsValidationRecentBundleStore(userDefaults: userDefaults)
  }

  private static func makeWorkspacePreferencesStore(
    environment: [String: String]
  ) -> UserDefaultsValidationGalleryWorkspacePreferencesStore {
    guard
      let suiteName = environment["XCODE_VALIDATION_GALLERY_UI_TEST_DEFAULTS_SUITE"],
      suiteName.isEmpty == false,
      let userDefaults = UserDefaults(suiteName: suiteName)
    else {
      return UserDefaultsValidationGalleryWorkspacePreferencesStore()
    }

    return UserDefaultsValidationGalleryWorkspacePreferencesStore(userDefaults: userDefaults)
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
