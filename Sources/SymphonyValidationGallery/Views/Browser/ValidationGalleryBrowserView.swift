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

// MARK: - Regular browser view

private struct ValidationGalleryRegularBrowserView: View {
  @Bindable var store: ValidationGalleryStore
  let snapshot: ValidationBundleSnapshot

  var body: some View {
    let currentSelectedID = store.selectedArtifactID
    let currentDisplayMode = store.workspacePreferences.browserDisplayMode
    let selectArtifact = store.selectArtifact

    ScrollView {
      LazyVStack(alignment: .leading, spacing: 20) {
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
          ForEach(store.flatBrowserRows) { row in
            switch row.content {
            case .platformHeader(let platform, let count):
              HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(ValidationGalleryFormatting.platformTitle(platform))
                  .font(.title3.weight(.semibold))
                Text("\(count) items")
                  .font(.footnote)
                  .foregroundStyle(.primary)
              }
              .padding(.top, 4)
              .allowsHitTesting(false)

            case .planHeader(let plan, let count):
              HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(ValidationGalleryFormatting.planTitle(plan))
                  .font(.subheadline.weight(.semibold))
                Text("\(count) artifacts")
                  .font(.footnote)
                  .foregroundStyle(.primary)
              }
              .padding(.top, 4)
              .allowsHitTesting(false)

            case .checkpoint(let header, let count, let artifacts):
              let localSelectedID = artifacts.contains(where: { $0.id == currentSelectedID }) ? currentSelectedID : nil
              ValidationGalleryCheckpointContent(
                selectedArtifactID: localSelectedID,
                displayMode: currentDisplayMode,
                header: header,
                artifactCount: count,
                artifacts: artifacts,
                onSelectArtifact: selectArtifact
              )
              .equatable()
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

// MARK: - Checkpoint content (isolates selection observation)

/// Renders a single checkpoint's artifacts without holding a reference to the
/// store. Receives only primitive/value-type parameters so it establishes no
/// `@Observable` tracking relationship with the store.
private struct ValidationGalleryCheckpointContent: View, Equatable {
  let selectedArtifactID: ValidationGalleryArtifact.ID?
  let displayMode: ValidationGalleryBrowserDisplayMode
  let header: String
  let artifactCount: Int
  let artifacts: [ValidationGalleryArtifact]
  let onSelectArtifact: (ValidationGalleryArtifact.ID?) -> Void

  nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.selectedArtifactID == rhs.selectedArtifactID
      && lhs.displayMode == rhs.displayMode
      && lhs.header == rhs.header
      && lhs.artifactCount == rhs.artifactCount
      && lhs.artifacts == rhs.artifacts
  }

  private let columns = [
    GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 14, alignment: .top)
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text(ValidationGalleryFormatting.checkpointTitle(header))
          .font(.footnote.weight(.semibold))
        Text("\(artifactCount)")
          .font(.footnote.monospacedDigit().weight(.semibold))
          .foregroundStyle(validationGalleryMutedForeground(opacity: 0.94))
      }
      .allowsHitTesting(false)

      if displayMode == .list {
        ValidationGalleryRegularArtifactList(
          artifacts: artifacts,
          selectedArtifactID: selectedArtifactID,
          onSelectArtifact: onSelectArtifact
        )
      } else {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
          ForEach(artifacts) { artifact in
            ValidationGalleryArtifactCard(
              artifact: artifact,
              isSelected: selectedArtifactID == artifact.id,
              onSelect: { onSelectArtifact(artifact.id) }
            )
            .equatable()
          }
        }
        .accessibilityIdentifier("validation-gallery-browser-grid-mode")
      }
    }
  }
}
