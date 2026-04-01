import AVKit
import SwiftUI

#if os(macOS)
  import AppKit
#endif

public struct ValidationGalleryArtifactDetailView: View {
  let artifact: ValidationGalleryArtifact
  let relatedAuditIssues: [ValidationGalleryAuditIssue]
  let comments: [ValidationGalleryNumberedComment]
  let selectedCommentID: ValidationGalleryComment.ID?
  let selectionSummary: String?
  let canSelectPreviousArtifact: Bool
  let canSelectNextArtifact: Bool
  let onSelectComment: ((ValidationGalleryComment.ID?) -> Void)?
  let onSelectPreviousArtifact: (() -> Void)?
  let onSelectNextArtifact: (() -> Void)?
  let onAddPointComment: (() -> Void)?
  let onAddAreaComment: (() -> Void)?
  let onExportComments: (() -> Void)?
  let onPreviewArtifact: (() -> Void)?

  var previewHeight: CGFloat
  var onPreviewHeightChanged: ((CGFloat) -> Void)?

  #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  #endif

  public init(
    artifact: ValidationGalleryArtifact,
    relatedAuditIssues: [ValidationGalleryAuditIssue],
    comments: [ValidationGalleryNumberedComment] = [],
    selectedCommentID: ValidationGalleryComment.ID? = nil,
    selectionSummary: String? = nil,
    canSelectPreviousArtifact: Bool = false,
    canSelectNextArtifact: Bool = false,
    onSelectComment: ((ValidationGalleryComment.ID?) -> Void)? = nil,
    onSelectPreviousArtifact: (() -> Void)? = nil,
    onSelectNextArtifact: (() -> Void)? = nil,
    onAddPointComment: (() -> Void)? = nil,
    onAddAreaComment: (() -> Void)? = nil,
    onExportComments: (() -> Void)? = nil,
    onPreviewArtifact: (() -> Void)? = nil,
    previewHeight: CGFloat = 280,
    onPreviewHeightChanged: ((CGFloat) -> Void)? = nil
  ) {
    self.artifact = artifact
    self.relatedAuditIssues = relatedAuditIssues
    self.comments = comments
    self.selectedCommentID = selectedCommentID
    self.selectionSummary = selectionSummary
    self.canSelectPreviousArtifact = canSelectPreviousArtifact
    self.canSelectNextArtifact = canSelectNextArtifact
    self.onSelectComment = onSelectComment
    self.onSelectPreviousArtifact = onSelectPreviousArtifact
    self.onSelectNextArtifact = onSelectNextArtifact
    self.onAddPointComment = onAddPointComment
    self.onAddAreaComment = onAddAreaComment
    self.onExportComments = onExportComments
    self.onPreviewArtifact = onPreviewArtifact
    self.previewHeight = previewHeight
    self.onPreviewHeightChanged = onPreviewHeightChanged
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        header

        if artifact.record.artifactType == .screenshot {
          ValidationGalleryAnnotatedImageView(
            artifact: artifact,
            comments: comments,
            selectedCommentID: selectedCommentID,
            interactionMode: .readOnly,
            draft: nil,
            minimumHeight: previewHeight,
            accessibilityIdentifier: "artifact-detail-image",
            allowsZoom: false,
            onDraftCreated: { _ in },
            onSelectComment: { onSelectComment?($0) },
            onActivate: onPreviewArtifact
          )
        } else {
          ValidationGalleryArtifactMediaSurface(
            artifact: artifact,
            minimumHeight: previewHeight,
            accessibilityIdentifier: "artifact-video-player"
          )
        }

        ValidationGalleryPreviewResizeHandle(
          previewHeight: previewHeight,
          onHeightChanged: onPreviewHeightChanged
        )

        ValidationGalleryArtifactMetadataGrid(artifact: artifact)

        if relatedAuditIssues.isEmpty == false {
          VStack(alignment: .leading, spacing: 12) {
            Text("Audit Context")
              .font(.headline)
            ForEach(relatedAuditIssues) { issue in
              VStack(alignment: .leading, spacing: 6) {
                Text(issue.record.message)
                  .font(.subheadline)
                Text(ValidationGalleryFormatting.resultBundleTitle(fromPath: issue.fileURL.lastPathComponent))
                  .font(.caption.weight(.medium))
                  .foregroundStyle(validationGalleryMutedForeground())
                  .fixedSize(horizontal: false, vertical: true)
              }
              .padding(12)
              .background(
                validationGalleryPanelBackgroundColor(),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
              )
            }
          }
        }

        DisclosureGroup("File Details") {
          VStack(alignment: .leading, spacing: 10) {
            ValidationGalleryInspectorRow(
              label: "Source Bundle Path",
              value: artifact.record.sourceResultBundle,
              monospace: true
            )
            ValidationGalleryInspectorRow(label: "File Path", value: artifact.fileURL.path, monospace: true)
          }
          .padding(.top, 8)
        }
        .font(.subheadline)
        .foregroundStyle(validationGalleryMutedForeground())
      }
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .modifier(
      ValidationGalleryNavigationTitle(
        title: ValidationGalleryFormatting.checkpointTitle(artifact.record.checkpoint),
        showsTitle: showsNavigationTitle
      )
    )
    .accessibilityIdentifier("artifact-detail-view")
  }

  private var showsNavigationTitle: Bool {
    #if os(iOS)
      horizontalSizeClass == .compact
    #else
      true
    #endif
  }

  @ViewBuilder
  private var header: some View {
    #if os(iOS)
      if horizontalSizeClass == .compact {
        compactHeader
      } else {
        standardHeader
      }
    #else
      standardHeader
    #endif
  }

  private var standardHeader: some View {
    HStack(alignment: .top, spacing: 12) {
      artifactSummary

      Spacer(minLength: 12)

      actionControls(compact: false)
    }
    .background { hiddenNavigationShortcuts }
  }

  private var compactHeader: some View {
    VStack(alignment: .leading, spacing: 14) {
      artifactSummary

      actionControls(compact: true)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background { hiddenNavigationShortcuts }
  }

  private var artifactSummary: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(ValidationGalleryFormatting.artifactTitle(artifact))
        .font(.headline.weight(.semibold))
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
        .accessibilityHidden(true)
      Text(ValidationGalleryFormatting.artifactInspectorSummary(artifact))
        .font(.footnote)
        .foregroundStyle(validationGalleryMutedForeground())
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityHidden(true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(ValidationGalleryFormatting.artifactTitle(artifact))
    .accessibilityValue(artifactSummaryAccessibilityValue)
    .accessibilityAddTraits(.isHeader)
  }

  private var artifactSummaryAccessibilityValue: String {
    [
      selectionSummary,
      ValidationGalleryFormatting.artifactInspectorSummary(artifact),
    ]
    .compactMap { $0 }
    .joined(separator: ", ")
  }

  @ViewBuilder
  private var hiddenNavigationShortcuts: some View {
    #if os(macOS)
      if let onSelectPreviousArtifact, let onSelectNextArtifact {
        Group {
          Button("Previous Artifact", action: onSelectPreviousArtifact)
            .disabled(canSelectPreviousArtifact == false)
            .keyboardShortcut("[", modifiers: [.command])

          Button("Next Artifact", action: onSelectNextArtifact)
            .disabled(canSelectNextArtifact == false)
            .keyboardShortcut("]", modifiers: [.command])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
      }
    #endif
  }

  @ViewBuilder
  private func actionControls(compact: Bool) -> some View {
    if compact {
      HStack(spacing: 10) {
        previewAction(compact: true)
        addCommentControls(
          onAddPointComment: onAddPointComment,
          onAddAreaComment: onAddAreaComment,
          compact: true
        )
        exportAction(compact: true)
      }
    } else {
      VStack(alignment: .trailing, spacing: 10) {
        previewAction(compact: false)
        HStack(spacing: 10) {
          addCommentControls(
            onAddPointComment: onAddPointComment,
            onAddAreaComment: onAddAreaComment,
            compact: false
          )
          exportAction(compact: false)
        }
      }
      .frame(maxWidth: .infinity, alignment: .trailing)
    }
  }

  @ViewBuilder
  private func addCommentControls(
    onAddPointComment: (() -> Void)?,
    onAddAreaComment: (() -> Void)?,
    compact: Bool
  ) -> some View {
    if artifact.record.artifactType == .screenshot,
      let onAddPointComment,
      let onAddAreaComment
    {
      Menu {
        Button("Add Point Comment", action: onAddPointComment)
        Button("Add Area Comment", action: onAddAreaComment)
      } label: {
        actionLabel(title: "Add Comment", systemImage: "plus.bubble", compact: compact)
      }
      .menuStyle(.button)
      .buttonStyle(.bordered)
      .controlSize(.large)
      .accessibilityHint("Choose whether to add a point or area comment.")
      .accessibilityLabel("Add Comment")
      .accessibilityIdentifier("add-comment-menu")
    }
  }

  @ViewBuilder
  private func previewAction(compact: Bool) -> some View {
    if let onPreviewArtifact {
      Button(action: onPreviewArtifact) {
        actionLabel(
          title: "Open Full Size",
          systemImage: "arrow.up.left.and.arrow.down.right",
          compact: compact
        )
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .tint(validationGalleryProminentActionTint())
      .accessibilityLabel("Open Full Size")
      .accessibilityIdentifier(
        "artifact-preview-\(ValidationGalleryFormatting.accessibilitySlug(for: artifact))"
      )
    }
  }

  @ViewBuilder
  private func exportAction(compact: Bool) -> some View {
    if artifact.record.artifactType == .screenshot, let onExportComments {
      Button(action: onExportComments) {
        actionLabel(title: "Export Comments", systemImage: "square.and.arrow.down", compact: compact)
      }
      .buttonStyle(.bordered)
      .controlSize(.large)
      .accessibilityHint(
        comments.isEmpty
          ? "Review export options. Add a comment to enable Export."
          : "Review export options for the current screenshot comments."
      )
      .accessibilityLabel("Export Comments")
      .accessibilityIdentifier("export-screenshot-comments-button")
    }
  }

  @ViewBuilder
  private func actionLabel(title: String, systemImage: String, compact: Bool) -> some View {
    if compact {
      Label(title, systemImage: systemImage)
        .labelStyle(.iconOnly)
    } else {
      Label(title, systemImage: systemImage)
    }
  }
}

struct ValidationGalleryArtifactMetadataGrid: View {
  let artifact: ValidationGalleryArtifact

  #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  #endif

  var body: some View {
    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
      ValidationGalleryInspectorRow(
        label: "Surface",
        value: ValidationGalleryFormatting.checkpointTitle(artifact.record.surface)
      )
      ValidationGalleryInspectorRow(
        label: "Checkpoint",
        value: ValidationGalleryFormatting.checkpointTitle(artifact.record.checkpoint)
      )
      ValidationGalleryInspectorRow(
        label: "Result Bundle",
        value: ValidationGalleryFormatting.sourceBundleTitle(artifact)
      )
      ValidationGalleryInspectorRow(
        label: "Asset",
        value: ValidationGalleryFormatting.assetTitle(artifact)
      )
    }
  }

  private var columns: [GridItem] {
    #if os(iOS)
      if horizontalSizeClass == .compact {
        return [GridItem(.flexible(minimum: 0), spacing: 12, alignment: .top)]
      }
    #endif

    return [
      GridItem(.flexible(minimum: 120), spacing: 16, alignment: .top),
      GridItem(.flexible(minimum: 120), spacing: 16, alignment: .top),
    ]
  }
}
