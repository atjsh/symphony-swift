import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

import SymphonyValidationGallery

#if os(macOS)
  import AppKit
#endif

enum XcodeValidationGalleryExportRoute: Equatable {
  case macOSFolder
  case packageDocument
  case uiTestingFolder
}

struct XcodeValidationGalleryExportRequest: Identifiable, Equatable {
  var options: ValidationGalleryCommentExportOptions

  var id: String {
    switch options.scope {
    case .selectedArtifact:
      "selected-artifact"
    case .currentBundle:
      "current-bundle"
    }
  }
}

@MainActor
protocol XcodeValidationGalleryCommentExportSaving {
  func save(_ preparedExport: ValidationGalleryPreparedCommentExport) async throws -> URL?
}

#if os(macOS)
  struct NSSavePanelValidationGalleryCommentExportSaver: XcodeValidationGalleryCommentExportSaving {
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
      self.fileManager = fileManager
    }

    func save(_ preparedExport: ValidationGalleryPreparedCommentExport) async throws -> URL? {
      let panel = NSSavePanel()
      panel.title = "Export Comments"
      panel.prompt = "Export"
      panel.canCreateDirectories = true
      panel.nameFieldStringValue = preparedExport.rootDirectoryName
      panel.directoryURL = fileManager.homeDirectoryForCurrentUser

      let response = await panel.begin()
      guard response == .OK, let destinationURL = panel.url else {
        return nil
      }

      try write(preparedExport, to: destinationURL, fileManager: fileManager)
      return destinationURL
    }
  }
#endif

struct UITestingValidationGalleryCommentExportSaver: XcodeValidationGalleryCommentExportSaving {
  let rootDirectory: URL
  let fileManager: FileManager

  init(rootDirectory: URL, fileManager: FileManager = .default) {
    self.rootDirectory = rootDirectory
    self.fileManager = fileManager
  }

  func save(_ preparedExport: ValidationGalleryPreparedCommentExport) async throws -> URL? {
    let destinationURL = rootDirectory.appendingPathComponent(preparedExport.rootDirectoryName, isDirectory: true)
    if fileManager.fileExists(atPath: destinationURL.path) {
      try fileManager.removeItem(at: destinationURL)
    }
    try write(preparedExport, to: destinationURL, fileManager: fileManager)
    return destinationURL
  }
}

private func write(
  _ preparedExport: ValidationGalleryPreparedCommentExport,
  to destinationURL: URL,
  fileManager: FileManager
) throws {
  try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
  for file in preparedExport.files {
    let fileURL = destinationURL.appendingPathComponent(file.relativePath)
    try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try file.data.write(to: fileURL)
  }
}

struct XcodeValidationGalleryCommentExportPackageDocument: FileDocument {
  static let packageContentType = UTType(exportedAs: "dev.atjsh.xcode-validation-gallery.comment-export", conformingTo: .package)
  static var readableContentTypes: [UTType] { [packageContentType] }

  let preparedExport: ValidationGalleryPreparedCommentExport

  init(preparedExport: ValidationGalleryPreparedCommentExport) {
    self.preparedExport = preparedExport
  }

  init(configuration: ReadConfiguration) throws {
    throw CocoaError(.fileReadUnsupportedScheme)
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    let mediaFiles = preparedExport.files.filter { $0.relativePath.hasPrefix("media/") }
    let mediaWrapper = FileWrapper(
      directoryWithFileWrappers: Dictionary(
        uniqueKeysWithValues: mediaFiles.map { file in
          let filename = String(file.relativePath.dropFirst("media/".count))
          return (filename, FileWrapper(regularFileWithContents: file.data))
        }
      )
    )

    let manifestData = preparedExport.files.first(where: { $0.relativePath == "comments.json" })?.data ?? Data()
    return FileWrapper(
      directoryWithFileWrappers: [
        "comments.json": FileWrapper(regularFileWithContents: manifestData),
        "media": mediaWrapper,
      ]
    )
  }
}

@MainActor
@Observable
final class XcodeValidationGalleryExportController {
  var request: XcodeValidationGalleryExportRequest?
  var packageDocument: XcodeValidationGalleryCommentExportPackageDocument?
  var packageDefaultFilename = ""
  var isPackageExporterPresented = false
  var error: ValidationGalleryError?
  var feedbackMessage: String?
  var lastExportURL: URL?
  var lastRoute: XcodeValidationGalleryExportRoute?

  private let environment: [String: String]
  private let exportCoordinator: any ValidationGalleryCommentExportPreparing
  private let folderSaver: (any XcodeValidationGalleryCommentExportSaving)?

  init(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    exportCoordinator: any ValidationGalleryCommentExportPreparing = ValidationGalleryCommentExportCoordinator(),
    folderSaver: (any XcodeValidationGalleryCommentExportSaving)? = nil
  ) {
    self.environment = environment
    self.exportCoordinator = exportCoordinator
    #if os(macOS)
      self.folderSaver = folderSaver ?? NSSavePanelValidationGalleryCommentExportSaver()
    #else
      self.folderSaver = folderSaver
    #endif
  }

  func requestExport(scope: ValidationGalleryCommentExportScope) {
    request = XcodeValidationGalleryExportRequest(options: ValidationGalleryCommentExportOptions(scope: scope))
  }

  func cancelExport() {
    request = nil
  }

  func dismissError() {
    error = nil
  }

  func commentCount(using store: ValidationGalleryStore) -> Int {
    guard let request else {
      return 0
    }

    return (try? store.exportCommentsPayload(scope: request.options.scope).comments.count) ?? 0
  }

  func screenshotCount(using store: ValidationGalleryStore) -> Int {
    guard let request else {
      return 0
    }

    let artifactIDs = (try? store.exportCommentsPayload(scope: request.options.scope).comments.map(\.artifactID)) ?? []
    return Set(artifactIDs).count
  }

  func performExport(using store: ValidationGalleryStore) async {
    guard let request else {
      return
    }

    do {
      let preparedExport = try exportCoordinator.prepareExport(from: store, options: request.options)

      if let uiTestSaver = makeUITestSaver() {
        lastExportURL = try await uiTestSaver.save(preparedExport)
        lastRoute = .uiTestingFolder
        self.request = nil
        showFeedback(for: preparedExport.payload.comments.count)
        return
      }

      if let folderSaver {
        lastExportURL = try await folderSaver.save(preparedExport)
        lastRoute = .macOSFolder
        self.request = nil
        if lastExportURL != nil {
          showFeedback(for: preparedExport.payload.comments.count)
        }
        return
      }

      packageDocument = XcodeValidationGalleryCommentExportPackageDocument(preparedExport: preparedExport)
      packageDefaultFilename = preparedExport.rootDirectoryName
      lastRoute = .packageDocument
      self.request = nil
      isPackageExporterPresented = true
    } catch {
      handleExportFailure(error)
    }
  }

  func completePackageExport(result: Result<URL, Error>, store: ValidationGalleryStore) {
    let exportedCommentCount = packageDocument?.preparedExport.payload.comments.count
    packageDocument = nil
    isPackageExporterPresented = false

    switch result {
    case .success(let url):
      lastExportURL = url
      if let commentCount = exportedCommentCount {
        showFeedback(for: commentCount)
      } else {
        showFeedback(for: nil)
      }
    case .failure(let error):
      guard isUserCancellation(error) == false else {
        return
      }
      handleExportFailure(error)
    }
  }

  private func handleExportFailure(_ error: Error) {
    request = nil
    packageDocument = nil
    isPackageExporterPresented = false
    self.error = normalizedExportError(from: error)
  }

  private func normalizedExportError(from error: Error) -> ValidationGalleryError {
    if let galleryError = error as? ValidationGalleryError {
      switch galleryError {
      case .exportFailed(let message), .loadFailed(let message):
        return .exportFailed(message)
      default:
        return .exportFailed(galleryError.errorDescription ?? error.localizedDescription)
      }
    }

    return .exportFailed(error.localizedDescription)
  }

  private func isUserCancellation(_ error: Error) -> Bool {
    if error is CancellationError {
      return true
    }

    let cocoaError = error as NSError
    return cocoaError.domain == NSCocoaErrorDomain
      && cocoaError.code == CocoaError.userCancelled.rawValue
  }

  private func showFeedback(for commentCount: Int?) {
    if let commentCount {
      feedbackMessage = "Exported \(commentCount) comment\(commentCount == 1 ? "" : "s")"
    } else {
      feedbackMessage = "Comments exported"
    }

    let message = feedbackMessage
    Task {
      try? await Task.sleep(for: .seconds(1.6))
      await MainActor.run {
        if feedbackMessage == message {
          feedbackMessage = nil
        }
      }
    }
  }

  private func makeUITestSaver() -> (any XcodeValidationGalleryCommentExportSaving)? {
    let currentEnvironment = ProcessInfo.processInfo.environment
    let exportDirectory =
      environment["XCODE_VALIDATION_GALLERY_UI_TEST_EXPORT_DIRECTORY"]
      ?? currentEnvironment["XCODE_VALIDATION_GALLERY_UI_TEST_EXPORT_DIRECTORY"]

    guard let exportDirectory, exportDirectory.isEmpty == false else {
      return nil
    }

    return UITestingValidationGalleryCommentExportSaver(
      rootDirectory: URL(fileURLWithPath: exportDirectory, isDirectory: true)
    )
  }
}
