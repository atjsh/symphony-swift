import SwiftUI

enum ValidationGalleryAnnotationInteractionMode {
  case readOnly
  case addPoint
  case addArea
}

struct ValidationGalleryAnnotatedImageView: View {
  let artifact: ValidationGalleryArtifact
  let comments: [ValidationGalleryNumberedComment]
  let selectedCommentID: ValidationGalleryComment.ID?
  let interactionMode: ValidationGalleryAnnotationInteractionMode
  let draft: ValidationGalleryCommentDraft?
  let minimumHeight: CGFloat
  let accessibilityIdentifier: String
  let allowsZoom: Bool
  let onDraftCreated: (ValidationGalleryCommentDraft) -> Void
  let onSelectComment: (ValidationGalleryComment.ID?) -> Void
  let onActivate: (() -> Void)?

  @State private var areaStartPoint: CGPoint?
  @State private var areaCurrentPoint: CGPoint?
  @State private var zoomScale: CGFloat = 1
  @State private var panOffset: CGSize = .zero
  @State private var magnifyStartScale: CGFloat?
  @State private var dragStartOffset: CGSize?
  @State private var loadedImage: ValidationGalleryLoadedImage?

  var body: some View {
    if let image = loadedImage {
      GeometryReader { geometry in
        let imageRect = aspectFitRect(for: image.pixelSize, in: geometry.size)

        annotationCanvas(image: image.image, imageRect: imageRect, containerSize: geometry.size)
      }
      .frame(maxWidth: .infinity, minHeight: minimumHeight)
    } else if !artifact.isAvailable {
      ContentUnavailableView(
        "Missing Image",
        systemImage: "photo.badge.exclamationmark",
        description: Text(artifact.fileURL.lastPathComponent)
      )
      .frame(maxWidth: .infinity, minHeight: minimumHeight)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
      .accessibilityIdentifier(accessibilityIdentifier)
    } else {
      ProgressView()
        .frame(maxWidth: .infinity, minHeight: minimumHeight)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityIdentifier(accessibilityIdentifier)
        .task(id: artifact.fileURL) {
          loadedImage = await ValidationGalleryThumbnailLoader.shared.fullImage(for: artifact.fileURL)
        }
    }
  }

  @ViewBuilder
  private func annotationCanvas(image: Image, imageRect: CGRect, containerSize: CGSize) -> some View {
    let canvas = ZStack {
      image
        .resizable()
        .scaledToFit()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.secondary.opacity(0.08))
        .accessibilityHidden(true)

      overlayLayer(in: imageRect)
    }
    .scaleEffect(zoomScale)
    .offset(panOffset)

    let content = ZStack {
      canvas
    }
    .contentShape(Rectangle())
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .accessibilityElement(children: .contain)
    .accessibilityLabel(ValidationGalleryFormatting.artifactTitle(artifact))
    .accessibilityHint("Validation screenshot preview with comment overlays.")
    .accessibilityIdentifier(accessibilityIdentifier)

    switch interactionMode {
    case .readOnly:
      zoomEnabledContent(content, containerSize: containerSize)
    case .addPoint:
      content.gesture(addPointGesture(in: imageRect))
    case .addArea:
      content.gesture(addAreaGesture(in: imageRect))
    }
  }

  @ViewBuilder
  private func zoomEnabledContent(_ content: some View, containerSize: CGSize) -> some View {
    if allowsZoom {
      content
        .gesture(magnifyGesture(in: containerSize))
        .simultaneousGesture(panGesture(in: containerSize))
        .onTapGesture(count: 2) {
          toggleZoom(in: containerSize)
        }
        .onTapGesture {
          onActivate?()
        }
    } else if let onActivate {
      content.onTapGesture(perform: onActivate)
    } else {
      content
    }
  }

  @ViewBuilder
  private func overlayLayer(in imageRect: CGRect) -> some View {
    ForEach(comments) { comment in
      ValidationGalleryCommentOverlay(
        numberedComment: comment,
        isSelected: comment.id == selectedCommentID,
        imageRect: imageRect,
        onSelect: { onSelectComment(comment.id) }
      )
    }

    if let draft {
      ValidationGalleryDraftOverlay(
        draft: draft,
        imageRect: imageRect
      )
    } else if interactionMode == .addArea, let draftRect = currentDraftArea(in: imageRect) {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
        .foregroundStyle(Color.accentColor)
        .frame(width: draftRect.width, height: draftRect.height)
        .position(x: draftRect.midX, y: draftRect.midY)
    }
  }

  private func addPointGesture(in imageRect: CGRect) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onEnded { value in
        guard interactionMode == .addPoint else {
          return
        }

        let start = value.startLocation
        let end = value.location
        let distance = hypot(end.x - start.x, end.y - start.y)
        guard distance < 12, imageRect.contains(end) else {
          return
        }

        onDraftCreated(
          ValidationGalleryCommentDraft(
            artifactID: artifact.id,
            anchor: .point(normalizedPoint(for: end, in: imageRect))
          )
        )
      }
  }

  private func addAreaGesture(in imageRect: CGRect) -> some Gesture {
    DragGesture(minimumDistance: 2)
      .onChanged { value in
        guard interactionMode == .addArea else {
          return
        }

        areaStartPoint = clamped(value.startLocation, to: imageRect)
        areaCurrentPoint = clamped(value.location, to: imageRect)
      }
      .onEnded { value in
        defer {
          areaStartPoint = nil
          areaCurrentPoint = nil
        }

        guard
          interactionMode == .addArea,
          let start = areaStartPoint ?? (imageRect.contains(value.startLocation) ? value.startLocation : nil),
          let end = areaCurrentPoint ?? (imageRect.contains(value.location) ? value.location : nil)
        else {
          return
        }

        let rect = CGRect(
          x: min(start.x, end.x),
          y: min(start.y, end.y),
          width: abs(end.x - start.x),
          height: abs(end.y - start.y)
        )

        guard rect.width >= 18, rect.height >= 18 else {
          return
        }

        onDraftCreated(
          ValidationGalleryCommentDraft(
            artifactID: artifact.id,
            anchor: .area(normalizedRect(for: rect, in: imageRect))
          )
        )
      }
  }

  private func magnifyGesture(in containerSize: CGSize) -> some Gesture {
    MagnifyGesture(minimumScaleDelta: 0.01)
      .onChanged { value in
        guard allowsZoom else {
          return
        }

        if magnifyStartScale == nil {
          magnifyStartScale = zoomScale
        }

        let baseScale = magnifyStartScale ?? zoomScale
        let proposedScale = clampedZoomScale(baseScale * value.magnification)
        zoomScale = proposedScale
        panOffset = clampedPanOffset(panOffset, for: proposedScale, in: containerSize)
      }
      .onEnded { _ in
        magnifyStartScale = nil
        if zoomScale <= 1.01 {
          resetZoom()
        } else {
          panOffset = clampedPanOffset(panOffset, for: zoomScale, in: containerSize)
        }
      }
  }

  private func panGesture(in containerSize: CGSize) -> some Gesture {
    DragGesture(minimumDistance: 1)
      .onChanged { value in
        guard allowsZoom, zoomScale > 1.001 else {
          return
        }

        if dragStartOffset == nil {
          dragStartOffset = panOffset
        }

        let baseOffset = dragStartOffset ?? panOffset
        let proposedOffset = CGSize(
          width: baseOffset.width + value.translation.width,
          height: baseOffset.height + value.translation.height
        )
        panOffset = clampedPanOffset(proposedOffset, for: zoomScale, in: containerSize)
      }
      .onEnded { _ in
        dragStartOffset = nil
        panOffset = clampedPanOffset(panOffset, for: zoomScale, in: containerSize)
      }
  }

  private func currentDraftArea(in imageRect: CGRect) -> CGRect? {
    guard let start = areaStartPoint, let current = areaCurrentPoint else {
      return nil
    }

    return CGRect(
      x: min(start.x, current.x),
      y: min(start.y, current.y),
      width: abs(current.x - start.x),
      height: abs(current.y - start.y)
    )
  }

  private func normalizedPoint(for point: CGPoint, in imageRect: CGRect) -> ValidationGalleryNormalizedPoint {
    ValidationGalleryNormalizedPoint(
      x: max(0, min(1, (point.x - imageRect.minX) / imageRect.width)),
      y: max(0, min(1, (point.y - imageRect.minY) / imageRect.height))
    )
  }

  private func normalizedRect(for rect: CGRect, in imageRect: CGRect) -> ValidationGalleryNormalizedRect {
    ValidationGalleryNormalizedRect(
      x: max(0, min(1, (rect.minX - imageRect.minX) / imageRect.width)),
      y: max(0, min(1, (rect.minY - imageRect.minY) / imageRect.height)),
      width: max(0, min(1, rect.width / imageRect.width)),
      height: max(0, min(1, rect.height / imageRect.height))
    )
  }

  private func clamped(_ point: CGPoint, to rect: CGRect) -> CGPoint? {
    guard rect.intersects(CGRect(origin: point, size: .zero).insetBy(dx: -1, dy: -1)) || rect.contains(point) else {
      return nil
    }

    return CGPoint(
      x: min(max(point.x, rect.minX), rect.maxX),
      y: min(max(point.y, rect.minY), rect.maxY)
    )
  }

  private func aspectFitRect(for imageSize: CGSize, in container: CGSize) -> CGRect {
    guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else {
      return CGRect(origin: .zero, size: container)
    }

    let scale = min(container.width / imageSize.width, container.height / imageSize.height)
    let width = imageSize.width * scale
    let height = imageSize.height * scale
    return CGRect(
      x: (container.width - width) / 2,
      y: (container.height - height) / 2,
      width: width,
      height: height
    )
  }

  private func toggleZoom(in containerSize: CGSize) {
    if zoomScale > 1.01 {
      resetZoom()
      return
    }

    zoomScale = 2
    panOffset = clampedPanOffset(.zero, for: zoomScale, in: containerSize)
  }

  private func resetZoom() {
    zoomScale = 1
    panOffset = .zero
    magnifyStartScale = nil
    dragStartOffset = nil
  }

  private func clampedZoomScale(_ proposedScale: CGFloat) -> CGFloat {
    min(max(proposedScale, 1), 6)
  }

  private func clampedPanOffset(_ proposedOffset: CGSize, for scale: CGFloat, in containerSize: CGSize) -> CGSize {
    guard scale > 1, containerSize.width > 0, containerSize.height > 0 else {
      return .zero
    }

    let maxX = max(0, ((containerSize.width * scale) - containerSize.width) / 2)
    let maxY = max(0, ((containerSize.height * scale) - containerSize.height) / 2)

    return CGSize(
      width: min(max(proposedOffset.width, -maxX), maxX),
      height: min(max(proposedOffset.height, -maxY), maxY)
    )
  }

}

struct ValidationGalleryLoadedImage {
  let image: Image
  let pixelSize: CGSize
}
