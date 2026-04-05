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

// MARK: - Flat browser row model

/// A flat representation of the browser hierarchy, replacing 4-level nested
/// ForEach (platform → plan → checkpoint → artifacts) with a single-level
/// ForEach. This dramatically reduces SwiftUI view-tree depth and the cost of
/// hit-testing on every mouse-move event.
private struct FlatBrowserRow: Identifiable {
  enum Content {
    case platformHeader(platform: String, artifactCount: Int)
    case planHeader(plan: String, artifactCount: Int)
    case checkpoint(
      header: String,
      artifactCount: Int,
      artifacts: [ValidationGalleryArtifact]
    )
  }

  let id: String
  let content: Content
}

private func makeFlatBrowserRows(
  from sections: [ValidationGalleryPlatformSection]
) -> [FlatBrowserRow] {
  var rows: [FlatBrowserRow] = []
  for platform in sections {
    let count = platform.plans.reduce(0) {
      $0 + $1.checkpoints.reduce(0) { $0 + $1.artifacts.count }
    }
    rows.append(FlatBrowserRow(
      id: "platform:\(platform.id)",
      content: .platformHeader(platform: platform.platform, artifactCount: count)
    ))
    for plan in platform.plans {
      let planCount = plan.checkpoints.reduce(0) { $0 + $1.artifacts.count }
      rows.append(FlatBrowserRow(
        id: "plan:\(plan.id)",
        content: .planHeader(plan: plan.plan, artifactCount: planCount)
      ))
      for checkpoint in plan.checkpoints {
        rows.append(FlatBrowserRow(
          id: "checkpoint:\(checkpoint.id)",
          content: .checkpoint(
            header: checkpoint.checkpoint,
            artifactCount: checkpoint.artifacts.count,
            artifacts: checkpoint.artifacts
          )
        ))
      }
    }
  }
  return rows
}

// MARK: - Regular browser view

private struct ValidationGalleryRegularBrowserView: View {
  @Bindable var store: ValidationGalleryStore
  let snapshot: ValidationBundleSnapshot

  private let columns = [
    GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 14, alignment: .top)
  ]

  var body: some View {
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
          let displayMode = store.workspacePreferences.browserDisplayMode
          let selectedID = store.selectedArtifactID
          let selectArtifact = store.selectArtifact
          ForEach(makeFlatBrowserRows(from: store.visiblePlatformSections)) { row in
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
              VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                  Text(ValidationGalleryFormatting.checkpointTitle(header))
                    .font(.footnote.weight(.semibold))
                  Text("\(count)")
                    .font(.footnote.monospacedDigit().weight(.semibold))
                    .foregroundStyle(validationGalleryMutedForeground(opacity: 0.94))
                }
                .allowsHitTesting(false)

                if displayMode == .list {
                  ValidationGalleryRegularArtifactList(
                    artifacts: artifacts,
                    selectedArtifactID: selectedID,
                    onSelectArtifact: selectArtifact
                  )
                } else {
                  LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    ForEach(artifacts) { artifact in
                      ValidationGalleryArtifactCard(
                        artifact: artifact,
                        isSelected: selectedID == artifact.id,
                        onSelect: { selectArtifact(artifact.id) }
                      )
                    }
                  }
                  .accessibilityIdentifier("validation-gallery-browser-grid-mode")
                }
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
