import SwiftUI

struct ValidationGalleryCompactListView: View {
  @Bindable var store: ValidationGalleryStore
  let snapshot: ValidationBundleSnapshot
  let onPreviewArtifact: (ValidationGalleryArtifact) -> Void
  let onAddPointComment: (ValidationGalleryArtifact) -> Void
  let onAddAreaComment: (ValidationGalleryArtifact) -> Void
  let onExportComments: () -> Void

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 16) {
        ValidationGallerySummaryHeader(snapshot: snapshot)
        ValidationGalleryFilterStatusBar(store: store)

        if let selectionFeedback = store.selectionFeedback {
          ValidationGallerySelectionFeedbackStrip(
            feedback: selectionFeedback,
            onDismiss: store.dismissSelectionFeedback
          )
        }

        if snapshot.warnings.isEmpty == false {
          ValidationGalleryWarningStrip(warnings: snapshot.warnings)
        }

        if store.hasNoVisibleArtifacts {
          ValidationGalleryFilteredEmptyStateView(store: store)
        } else {
          ForEach(store.visiblePlatformSections) { platformSection in
            ValidationGalleryCompactPlatformSection(
              platformSection: platformSection,
              auditIssues: store.filteredAuditIssues,
              flatArtifacts: platformSection.plans.flatMap { $0.checkpoints.flatMap(\.artifacts) },
              comments: { store.numberedComments(for: $0) },
              selectedCommentID: store.selectedCommentID,
              onSelectComment: store.selectComment,
              onSelectArtifact: { store.selectArtifact($0) },
              onPreviewArtifact: onPreviewArtifact,
              onAddPointComment: onAddPointComment,
              onAddAreaComment: onAddAreaComment,
              onExportComments: onExportComments
            )
          }
        }
      }
      .padding(20)
    }
    .accessibilityIdentifier("validation-gallery-browser-compact")
  }
}

struct ValidationGalleryCompactPlatformSection: View {
  let platformSection: ValidationGalleryPlatformSection
  let auditIssues: [ValidationGalleryAuditIssue]
  let flatArtifacts: [ValidationGalleryArtifact]
  let comments: (ValidationGalleryArtifact) -> [ValidationGalleryNumberedComment]
  let selectedCommentID: ValidationGalleryComment.ID?
  let onSelectComment: (ValidationGalleryComment.ID?) -> Void
  let onSelectArtifact: (ValidationGalleryArtifact.ID) -> Void
  let onPreviewArtifact: (ValidationGalleryArtifact) -> Void
  let onAddPointComment: (ValidationGalleryArtifact) -> Void
  let onAddAreaComment: (ValidationGalleryArtifact) -> Void
  let onExportComments: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      platformHeader

      ForEach(flatArtifacts) { artifact in
        ValidationGalleryCompactArtifactLink(
          artifact: artifact,
          relatedAuditIssues: relatedAuditIssues(for: artifact),
          comments: comments(artifact),
          selectedCommentID: selectedCommentID,
          onSelectComment: onSelectComment,
          onSelectArtifact: onSelectArtifact,
          onPreviewArtifact: onPreviewArtifact,
          onAddPointComment: onAddPointComment,
          onAddAreaComment: onAddAreaComment,
          onExportComments: onExportComments
        )
      }
    }
  }

  private var platformHeader: some View {
    HStack {
      Text(ValidationGalleryFormatting.platformTitle(platformSection.platform))
        .font(.headline.weight(.semibold))
        .foregroundStyle(.primary)
        .accessibilityAddTraits(.isHeader)

      Spacer(minLength: 0)
    }
    .padding(.vertical, 2)
  }

  private func relatedAuditIssues(for artifact: ValidationGalleryArtifact) -> [ValidationGalleryAuditIssue] {
    auditIssues.filter {
      $0.record.platform == artifact.record.platform
        && $0.record.plan == artifact.record.plan
        && $0.record.checkpoint == artifact.record.checkpoint
    }
  }
}

struct ValidationGalleryCompactArtifactLink: View {
  let artifact: ValidationGalleryArtifact
  let relatedAuditIssues: [ValidationGalleryAuditIssue]
  let comments: [ValidationGalleryNumberedComment]
  let selectedCommentID: ValidationGalleryComment.ID?
  let onSelectComment: (ValidationGalleryComment.ID?) -> Void
  let onSelectArtifact: (ValidationGalleryArtifact.ID) -> Void
  let onPreviewArtifact: (ValidationGalleryArtifact) -> Void
  let onAddPointComment: (ValidationGalleryArtifact) -> Void
  let onAddAreaComment: (ValidationGalleryArtifact) -> Void
  let onExportComments: () -> Void

  var body: some View {
    NavigationLink {
      ScrollView {
        ValidationGalleryArtifactDetailView(
          artifact: artifact,
          relatedAuditIssues: relatedAuditIssues,
          comments: comments,
          selectedCommentID: selectedCommentID,
          onSelectComment: onSelectComment,
          onAddPointComment: { onAddPointComment(artifact) },
          onAddAreaComment: { onAddAreaComment(artifact) },
          onExportComments: onExportComments,
          onPreviewArtifact: { onPreviewArtifact(artifact) }
        )
      }
      .onAppear {
        onSelectArtifact(artifact.id)
      }
    } label: {
      ValidationGalleryArtifactRow(artifact: artifact)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
          validationGalleryPanelBackgroundColor(),
          in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(ValidationGalleryFormatting.artifactTitle(artifact))
    .accessibilityValue(
      "\(ValidationGalleryFormatting.planTitle(artifact.record.plan)), \(ValidationGalleryFormatting.artifactBrowserSubtitle(artifact))"
    )
    .accessibilityHint("Opens the selected validation artifact.")
    .accessibilityIdentifier(
      "artifact-row-\(ValidationGalleryFormatting.accessibilitySlug(for: artifact))"
    )
  }
}
