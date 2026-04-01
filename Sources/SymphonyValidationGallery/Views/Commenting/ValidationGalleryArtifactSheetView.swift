import SwiftUI

enum ValidationGalleryArtifactPresentationMode: String, CaseIterable {
  case preview
  case addPointComment
  case addAreaComment

  var isAddingComment: Bool {
    switch self {
    case .preview:
      false
    case .addPointComment, .addAreaComment:
      true
    }
  }
}

struct ValidationGalleryArtifactSheetView: View {
  @Bindable var store: ValidationGalleryStore
  let artifact: ValidationGalleryArtifact
  let mode: ValidationGalleryArtifactPresentationMode
  let onDismissRequested: () -> Void
  let onExportComments: () -> Void

  #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  #endif

  @State private var draft: ValidationGalleryCommentDraft?
  @State private var draftBody = ""
  @State private var editingBody = ""
  @State private var showDiscardConfirmation = false
  @State private var showDeleteConfirmation = false

  init(
    store: ValidationGalleryStore,
    artifact: ValidationGalleryArtifact,
    mode: ValidationGalleryArtifactPresentationMode,
    onDismissRequested: @escaping () -> Void,
    onExportComments: @escaping () -> Void
  ) {
    self.store = store
    self.artifact = artifact
    self.mode = mode
    self.onDismissRequested = onDismissRequested
    self.onExportComments = onExportComments
  }

  private var comments: [ValidationGalleryNumberedComment] {
    store.numberedComments(for: artifact)
  }

  private var selectedComment: ValidationGalleryNumberedComment? {
    comments.first(where: { $0.id == store.selectedCommentID })
  }

  private var interactionMode: ValidationGalleryAnnotationInteractionMode {
    if draft != nil {
      return .readOnly
    }

    switch mode {
    case .preview:
      return .readOnly
    case .addPointComment:
      return .addPoint
    case .addAreaComment:
      return .addArea
    }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        header

        if artifact.record.artifactType == .screenshot {
          ValidationGalleryAnnotatedImageView(
            artifact: artifact,
            comments: comments,
            selectedCommentID: store.selectedCommentID,
            interactionMode: interactionMode,
            draft: draft,
            minimumHeight: 420,
            accessibilityIdentifier: "artifact-full-size-preview",
            allowsZoom: true,
            onDraftCreated: handleDraftCreated(_:),
            onSelectComment: store.selectComment,
            onActivate: nil
          )
        } else {
          ValidationGalleryArtifactMediaSurface(
            artifact: artifact,
            minimumHeight: 420,
            accessibilityIdentifier: "artifact-full-size-preview"
          )
        }

        if let draft {
          ValidationGalleryCommentComposer(
            title: draftTitle(for: draft.anchor),
            bodyText: $draftBody,
            saveButtonTitle: "Save Comment",
            onSave: saveDraft,
            onCancel: { discardDraft() }
          )
        } else if let selectedComment, artifact.record.artifactType == .screenshot {
          ValidationGalleryCommentEditor(
            numberedComment: selectedComment,
            bodyText: $editingBody,
            onSave: { updateComment(selectedComment.comment) },
            onDelete: { showDeleteConfirmation = true }
          )
        }

        if artifact.record.artifactType == .screenshot {
          ValidationGalleryCommentList(
            comments: comments,
            selectedCommentID: store.selectedCommentID,
            isAddingComment: mode.isAddingComment,
            onSelectComment: { comment in
              store.selectComment(comment.id)
              editingBody = comment.comment.body
            }
          )
        }
      }
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .accessibilityIdentifier("artifact-sheet-scroll-view")
    .interactiveDismissDisabled(draft != nil)
    .confirmationDialog(
      ValidationGalleryFormatting.discardDraftTitle,
      isPresented: $showDiscardConfirmation,
      titleVisibility: .visible
    ) {
      Button("Discard Comment", role: .destructive) {
        discardDraft()
        onDismissRequested()
      }
      .accessibilityIdentifier("confirm-discard-comment-button")
      Button("Keep Editing", role: .cancel) {}
        .accessibilityIdentifier("keep-editing-comment-button")
    } message: {
      Text(ValidationGalleryFormatting.discardDraftMessage)
    }
    .confirmationDialog(
      ValidationGalleryFormatting.deleteCommentTitle(annotationID: selectedComment?.annotationID ?? 0),
      isPresented: $showDeleteConfirmation,
      titleVisibility: .visible
    ) {
      Button("Delete Comment", role: .destructive) {
        if let selectedComment {
          deleteComment(selectedComment.comment)
        }
      }
      .accessibilityIdentifier("confirm-delete-comment-button")
      Button("Keep Comment", role: .cancel) {}
        .accessibilityIdentifier("keep-comment-button")
    } message: {
      Text(ValidationGalleryFormatting.deleteCommentMessage)
    }
    .onAppear {
      if let selectedComment {
        editingBody = selectedComment.comment.body
      } else {
        store.selectComment(comments.first?.id)
        editingBody = comments.first?.comment.body ?? ""
      }
    }
    .onChange(of: store.selectedCommentID) { _, _ in
      editingBody = selectedComment?.comment.body ?? ""
    }
  }

  private var header: some View {
    Group {
      if usesCompactHeaderActions {
        VStack(alignment: .leading, spacing: 10) {
          HStack(alignment: .top, spacing: 12) {
            headerMetadata

            Spacer(minLength: 12)

            compactHeaderActions
          }

          if mode.isAddingComment {
            modeInstructionBanner
          }
        }
      } else {
        HStack(alignment: .top, spacing: 12) {
          VStack(alignment: .leading, spacing: 6) {
            headerMetadata

            if mode.isAddingComment {
              modeInstructionBanner
            }
          }

          Spacer(minLength: 12)

          regularHeaderActions
        }
      }
    }
  }

  private var headerMetadata: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(ValidationGalleryFormatting.artifactTitle(artifact))
        .font(.title3.weight(.semibold))
      Text(ValidationGalleryFormatting.artifactInspectorSummary(artifact))
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }

  private var modeInstructionBanner: some View {
    Text(modeInstructionText)
      .font(.footnote)
      .foregroundStyle(.secondary)
      .accessibilityIdentifier("comment-mode-banner")
  }

  private var regularHeaderActions: some View {
    GlassEffectContainer(spacing: 10) {
      HStack(spacing: 10) {
        if artifact.record.artifactType == .screenshot {
          Button("Export Comments", systemImage: "square.and.arrow.down", action: onExportComments)
            .buttonStyle(.glass)
            .controlSize(.large)
            .accessibilityIdentifier("artifact-sheet-export-comments-button")
            .accessibilityHint(exportCommentsAccessibilityHint)
        }

        closeButton
          .buttonStyle(.glass)
          .controlSize(.large)
      }
    }
  }

  private var compactHeaderActions: some View {
    GlassEffectContainer(spacing: 8) {
      HStack(spacing: 8) {
        if artifact.record.artifactType == .screenshot {
          Button("Export Comments", systemImage: "square.and.arrow.down", action: onExportComments)
            .buttonStyle(.glass)
            .controlSize(.regular)
            .accessibilityIdentifier("artifact-sheet-export-comments-button")
            .accessibilityHint(exportCommentsAccessibilityHint)
        }

        closeButton
          .buttonStyle(.glass)
          .controlSize(.regular)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("artifact-sheet-compact-actions")
  }

  private var closeButton: some View {
    Button {
      if draft != nil {
        showDiscardConfirmation = true
      } else {
        onDismissRequested()
      }
    } label: {
      Label("Close", systemImage: "xmark")
    }
    .accessibilityIdentifier("artifact-sheet-close-button")
  }

  private var exportCommentsAccessibilityHint: String {
    comments.isEmpty
      ? "Review export options. Add a comment to enable Export."
      : "Review export options for the current screenshot comments."
  }

  private var usesCompactHeaderActions: Bool {
    #if os(iOS)
      horizontalSizeClass == .compact
    #else
      false
    #endif
  }

  private var modeInstructionText: String {
    switch mode {
    case .preview:
      ""
    case .addPointComment:
      #if os(iOS)
        "Tap once to place the comment marker."
      #else
        "Click once to place the comment marker."
      #endif
    case .addAreaComment:
      #if os(iOS)
        "Drag to mark the comment area."
      #else
        "Drag to mark the comment area."
      #endif
    }
  }

  private func handleDraftCreated(_ draft: ValidationGalleryCommentDraft) {
    self.draft = draft
    draftBody = ""
  }

  private func saveDraft() {
    guard let draft else {
      return
    }

    store.saveCommentDraft(
      ValidationGalleryCommentDraft(
        artifactID: draft.artifactID,
        anchor: draft.anchor,
        body: draftBody
      ),
      for: artifact
    )
    self.draft = nil
    draftBody = ""
    editingBody = selectedComment?.comment.body ?? ""
  }

  private func discardDraft() {
    draft = nil
    draftBody = ""
  }

  private func updateComment(_ comment: ValidationGalleryComment) {
    store.updateCommentBody(comment.id, body: editingBody, in: artifact)
    editingBody = selectedComment?.comment.body ?? editingBody
  }

  private func deleteComment(_ comment: ValidationGalleryComment) {
    store.deleteComment(comment.id, from: artifact)
    editingBody = selectedComment?.comment.body ?? ""
  }

  private func draftTitle(for anchor: ValidationGalleryCommentAnchor) -> String {
    switch anchor {
    case .point:
      "New Point Comment"
    case .area:
      "New Area Comment"
    }
  }
}
