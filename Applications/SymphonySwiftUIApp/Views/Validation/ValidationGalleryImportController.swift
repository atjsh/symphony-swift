import Observation
import SwiftUI

import SymphonyValidationGallery

enum ValidationGalleryImportKind: String, Equatable, Sendable {
  case bundle
  case manifest
}

@MainActor
@Observable
final class ValidationGalleryImportController {
  let capturesRequests: Bool
  var requestedImportKind: ValidationGalleryImportKind?
  var isBundleImporterPresented = false
  var isManifestImporterPresented = false

  init(environment: [String: String] = ProcessInfo.processInfo.environment) {
    capturesRequests = environment["XCODE_VALIDATION_GALLERY_UI_TEST_CAPTURE_IMPORT_REQUESTS"] == "1"
  }

  func request(_ kind: ValidationGalleryImportKind) {
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

  func complete(_ kind: ValidationGalleryImportKind) {
    switch kind {
    case .bundle:
      isBundleImporterPresented = false
    case .manifest:
      isManifestImporterPresented = false
    }
  }
}
