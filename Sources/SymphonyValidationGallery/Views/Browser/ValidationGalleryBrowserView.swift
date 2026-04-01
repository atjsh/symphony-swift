import SwiftUI

struct ValidationGalleryBrowserView: View {
  @Bindable var store: ValidationGalleryStore
  let compact: Bool
  let onOpenBundle: () -> Void
  let onOpenManifest: () -> Void
  let onPreviewArtifact: (ValidationGalleryArtifact) -> Void
  let onAddPointComment: (ValidationGalleryArtifact) -> Void
  let onAddAreaComment: (ValidationGalleryArtifact) -> Void
  let onExportComments: () -> Void

  var body: some View {
    if store.isLoading {
      ProgressView("Loading validation bundle…")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if let error = store.error {
      ValidationGalleryErrorStateView(
        error: error,
        onOpenBundle: onOpenBundle,
        onOpenManifest: onOpenManifest
      )
    } else if let snapshot = store.snapshot {
      if compact {
        ValidationGalleryCompactListView(
          store: store,
          snapshot: snapshot,
          onPreviewArtifact: onPreviewArtifact,
          onAddPointComment: onAddPointComment,
          onAddAreaComment: onAddAreaComment,
          onExportComments: onExportComments
        )
      } else {
        ValidationGalleryRegularBrowserView(
          store: store,
          snapshot: snapshot
        )
      }
    } else {
      ValidationGalleryEmptyStateView(
        onOpenBundle: onOpenBundle,
        onOpenManifest: onOpenManifest
      )
    }
  }
}

private struct ValidationGalleryRegularBrowserView: View {
  @Bindable var store: ValidationGalleryStore
  let snapshot: ValidationBundleSnapshot

  private let columns = [
    GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 14, alignment: .top)
  ]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
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
            VStack(alignment: .leading, spacing: 16) {
              HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(ValidationGalleryFormatting.platformTitle(platformSection.platform))
                  .font(.title3.weight(.semibold))
                Text("\(platformSection.plans.reduce(0) { $0 + $1.checkpoints.reduce(0) { $0 + $1.artifacts.count } }) items")
                  .font(.footnote)
                  .foregroundStyle(.primary)
              }
              .padding(.top, 4)

              ForEach(platformSection.plans) { planSection in
                VStack(alignment: .leading, spacing: 12) {
                  HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(ValidationGalleryFormatting.planTitle(planSection.plan))
                      .font(.subheadline.weight(.semibold))
                    Text("\(planSection.checkpoints.reduce(0) { $0 + $1.artifacts.count }) artifacts")
                      .font(.footnote)
                      .foregroundStyle(.primary)
                  }

                  ForEach(planSection.checkpoints) { checkpointSection in
                    VStack(alignment: .leading, spacing: 10) {
                      HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(ValidationGalleryFormatting.checkpointTitle(checkpointSection.checkpoint))
                          .font(.footnote.weight(.semibold))
                        Text("\(checkpointSection.artifacts.count)")
                          .font(.footnote.monospacedDigit().weight(.semibold))
                          .foregroundStyle(validationGalleryMutedForeground(opacity: 0.94))
                      }

                      if store.workspacePreferences.browserDisplayMode == .list {
                        ValidationGalleryRegularArtifactList(
                          artifacts: checkpointSection.artifacts,
                          selectedArtifactID: store.selectedArtifact?.id,
                          onSelectArtifact: store.selectArtifact
                        )
                      } else {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                          ForEach(checkpointSection.artifacts) { artifact in
                            ValidationGalleryArtifactCard(
                              artifact: artifact,
                              isSelected: store.selectedArtifact?.id == artifact.id,
                              onSelect: { store.selectArtifact(artifact.id) }
                            )
                          }
                        }
                        .accessibilityIdentifier("validation-gallery-browser-grid-mode")
                      }
                    }
                  }
                }
                .padding(.vertical, 4)
              }
            }
          }
        }
      }
      .padding(24)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .accessibilityIdentifier("validation-gallery-browser")
  }
}
