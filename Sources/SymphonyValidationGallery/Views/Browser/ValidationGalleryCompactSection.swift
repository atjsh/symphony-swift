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
              store: store,
              platformSection: platformSection,
              auditIssues: store.filteredAuditIssues,
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
  @Bindable var store: ValidationGalleryStore
  let platformSection: ValidationGalleryPlatformSection
  let auditIssues: [ValidationGalleryAuditIssue]
  let onSelectArtifact: (ValidationGalleryArtifact.ID) -> Void
  let onPreviewArtifact: (ValidationGalleryArtifact) -> Void
  let onAddPointComment: (ValidationGalleryArtifact) -> Void
  let onAddAreaComment: (ValidationGalleryArtifact) -> Void
  let onExportComments: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      platformHeader

      ForEach(platformSection.plans.flatMap({ $0.checkpoints.flatMap(\.artifacts) })) { artifact in
        ValidationGalleryCompactArtifactLink(
          store: store,
          artifact: artifact,
          relatedAuditIssues: relatedAuditIssues(for: artifact),
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
  @Bindable var store: ValidationGalleryStore
  let artifact: ValidationGalleryArtifact
  let relatedAuditIssues: [ValidationGalleryAuditIssue]
  let onSelectArtifact: (ValidationGalleryArtifact.ID) -> Void
  let onPreviewArtifact: (ValidationGalleryArtifact) -> Void
  let onAddPointComment: (ValidationGalleryArtifact) -> Void
  let onAddAreaComment: (ValidationGalleryArtifact) -> Void
  let onExportComments: () -> Void

  var body: some View {
    NavigationLink {
      ValidationGalleryArtifactDetailView(
        artifact: artifact,
        relatedAuditIssues: relatedAuditIssues,
        comments: store.numberedComments(for: artifact),
        selectedCommentID: store.selectedCommentID,
        onSelectComment: store.selectComment,
        onAddPointComment: { onAddPointComment(artifact) },
        onAddAreaComment: { onAddAreaComment(artifact) },
        onExportComments: onExportComments,
        onPreviewArtifact: { onPreviewArtifact(artifact) }
      )
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
