import SwiftUI

import SymphonyValidationGallery

/// Gallery menu commands, isolated from window content to prevent @FocusedValue churn.
///
/// This is a separate `Commands` conformance so that `@FocusedValue`
/// changes (which fire on every focus shift) only re-evaluate the menu bar,
/// not the entire window content tree. See commit 56c7aba for context.
struct ValidationGalleryEmbeddedCommands: Commands {
  let store: ValidationGalleryStore
  let importController: ValidationGalleryImportController
  @FocusedValue(\.galleryCommandActions) private var galleryActions

  var body: some Commands {
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
