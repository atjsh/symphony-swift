import SwiftUI

struct ValidationGalleryInspectorView: View {
  @Bindable var store: ValidationGalleryStore
  let onPreviewArtifact: (ValidationGalleryArtifact) -> Void
  let onAddPointComment: (ValidationGalleryArtifact) -> Void
  let onAddAreaComment: (ValidationGalleryArtifact) -> Void
  let onExportComments: () -> Void

  var body: some View {
    Group {
      if let selectedArtifact = store.selectedArtifact {
        selectedArtifactContent(for: selectedArtifact)
      } else {
        emptyInspectorContent
      }
    }
    .accessibilityIdentifier("validation-gallery-inspector")
  }

  private func selectedArtifactContent(
    for selectedArtifact: ValidationGalleryArtifact
  ) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        ValidationGalleryArtifactDetailView(
          artifact: selectedArtifact,
          relatedAuditIssues: store.selectedArtifactAuditIssues,
          comments: store.selectedArtifactComments,
          selectedCommentID: store.selectedCommentID,
          selectionSummary: store.selectedArtifactPositionText,
          canSelectPreviousArtifact: store.canSelectPreviousArtifact,
          canSelectNextArtifact: store.canSelectNextArtifact,
          onSelectComment: store.selectComment,
          onSelectPreviousArtifact: store.selectPreviousArtifact,
          onSelectNextArtifact: store.selectNextArtifact,
          onAddPointComment: { onAddPointComment(selectedArtifact) },
          onAddAreaComment: { onAddAreaComment(selectedArtifact) },
          onExportComments: onExportComments,
          onPreviewArtifact: { onPreviewArtifact(selectedArtifact) },
          previewHeight: CGFloat(store.workspacePreferences.inspectorPreviewHeight ?? 280),
          onPreviewHeightChanged: { store.setInspectorPreviewHeight(Double($0)) }
        )

        if let snapshot = store.snapshot {
          bundleContextDisclosure(snapshot: snapshot)
        } else {
          EmptyView()
        }
      }
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  @ViewBuilder
  private var emptyInspectorContent: some View {
    VStack(alignment: .leading, spacing: 20) {
      Spacer(minLength: 0)
      ValidationGalleryInspectorEmptyState(
        hasActiveFilters: store.hasActiveFilters,
        onClearFilters: store.hasActiveFilters ? { store.clearFilters() } : nil
      )
      Spacer(minLength: 0)

      if let snapshot = store.snapshot {
        bundleContextDisclosure(snapshot: snapshot)
      } else {
        EmptyView()
      }
    }
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func bundleContextDisclosure(snapshot: ValidationBundleSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Divider()

      DisclosureGroup("Bundle Context") {
        ValidationGalleryBundleContextView(snapshot: snapshot)
          .padding(.top, 8)
      }
      .font(.subheadline)
      .foregroundStyle(validationGalleryMutedForeground())
    }
  }
}

struct ValidationGalleryInspectorEmptyState: View {
  let hasActiveFilters: Bool
  let onClearFilters: (() -> Void)?

  var body: some View {
    Group {
      if let onClearFilters {
        ContentUnavailableView {
          Label(
            ValidationGalleryFormatting.inspectorEmptyStateTitle(hasActiveFilters: hasActiveFilters),
            systemImage: hasActiveFilters ? "line.3.horizontal.decrease.circle" : "sidebar.right"
          )
        } description: {
          Text(ValidationGalleryFormatting.inspectorEmptyStateDescription(hasActiveFilters: hasActiveFilters))
        } actions: {
          Button("Clear Filters", action: onClearFilters)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
      } else {
        ContentUnavailableView {
          Label(
            ValidationGalleryFormatting.inspectorEmptyStateTitle(hasActiveFilters: hasActiveFilters),
            systemImage: hasActiveFilters ? "line.3.horizontal.decrease.circle" : "sidebar.right"
          )
        } description: {
          Text(ValidationGalleryFormatting.inspectorEmptyStateDescription(hasActiveFilters: hasActiveFilters))
        }
      }
    }
    .frame(maxWidth: .infinity, minHeight: 220)
    .padding(.horizontal, 20)
    .accessibilityIdentifier("validation-gallery-inspector-empty-state")
  }
}

struct ValidationGalleryBundleContextView: View {
  let snapshot: ValidationBundleSnapshot

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 8) {
        Text(snapshot.source.displayName)
          .font(.subheadline.weight(.semibold))

        Text(snapshot.bundleRootURL.path)
          .font(.caption.monospaced())
          .foregroundStyle(validationGalleryMutedForeground())
          .lineLimit(3)
          .textSelection(.enabled)
      }

      VStack(alignment: .leading, spacing: 10) {
        Text("Runs")
          .font(.subheadline.weight(.semibold))
        ForEach(Array(snapshot.summary.runRecords.enumerated()), id: \.offset) { _, record in
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(ValidationGalleryFormatting.platformTitle(record.destination.platformDirectoryName))
            Text(ValidationGalleryFormatting.planTitle(record.plan.slug))
              .foregroundStyle(validationGalleryMutedForeground())
            Spacer()
            Label(
              ValidationGalleryFormatting.outcomeTitle(record.outcome),
              systemImage: ValidationGalleryFormatting.outcomeSymbolName(record.outcome)
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(record.outcome == .passed ? .green : .orange)
          }
          .font(.subheadline)
        }
      }
    }
  }
}

struct ValidationGalleryInspectorRow: View {
  let label: String
  let value: String
  var monospace = false

  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label)
        .font(.footnote.weight(.medium))
        .foregroundStyle(validationGalleryMutedForeground())
        .accessibilityHidden(true)
      Text(value)
        .font(monospace ? .footnote.monospaced() : .subheadline)
        .lineLimit(valueLineLimit)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .accessibilityHidden(true)
    }
    .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
    .accessibilityElement(children: .ignore)
    .accessibilityRepresentation {
      Text("\(label): \(value)")
    }
  }

  private var valueLineLimit: Int? {
    if horizontalSizeClass == .compact {
      return monospace ? 6 : nil
    }

    return monospace ? 4 : 2
  }
}

struct ValidationGalleryNavigationTitle: ViewModifier {
  let title: String
  let showsTitle: Bool

  func body(content: Content) -> some View {
    if showsTitle {
      #if os(iOS)
        content
          .navigationTitle(title)
          .navigationBarTitleDisplayMode(.inline)
      #else
        content.navigationTitle(title)
      #endif
    } else {
      content
    }
  }
}

struct ValidationGalleryPreviewResizeHandle: View {
  let previewHeight: CGFloat
  let onHeightChanged: ((CGFloat) -> Void)?

  @State private var dragOffset: CGFloat = 0

  private let minHeight: CGFloat = 160
  private let maxHeight: CGFloat = 600

  var body: some View {
    if onHeightChanged != nil {
      Rectangle()
        .fill(Color.primary.opacity(0.08))
        .frame(height: 6)
        .frame(maxWidth: .infinity)
        .clipShape(Capsule())
        .padding(.horizontal, 40)
        .padding(.vertical, 4)
        .contentShape(Rectangle().inset(by: -8))
        .gesture(
          DragGesture(minimumDistance: 1)
            .onChanged { value in
              let newHeight = (previewHeight + value.translation.height)
                .clamped(to: minHeight...maxHeight)
              dragOffset = newHeight - previewHeight
              onHeightChanged?(newHeight)
            }
            .onEnded { _ in
              dragOffset = 0
            }
        )
        #if os(macOS)
          .onHover { hovering in
            if hovering {
              NSCursor.resizeUpDown.push()
            } else {
              NSCursor.pop()
            }
          }
        #endif
        .accessibilityLabel("Resize preview")
        .accessibilityHint("Drag to resize the media preview height")
        .accessibilityIdentifier("preview-resize-handle")
    }
  }
}

extension Comparable {
  fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
