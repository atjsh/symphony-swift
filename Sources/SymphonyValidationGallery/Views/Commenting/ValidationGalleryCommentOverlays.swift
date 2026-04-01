import SwiftUI

struct ValidationGalleryCommentOverlay: View {
  let numberedComment: ValidationGalleryNumberedComment
  let isSelected: Bool
  let imageRect: CGRect
  let onSelect: () -> Void

  var body: some View {
    switch numberedComment.comment.anchor {
    case .point(let point):
      Button(action: onSelect) {
        Text("\(numberedComment.annotationID)")
          .font(.caption.monospacedDigit().weight(.semibold))
          .foregroundStyle(.white)
          .frame(width: 28, height: 28)
          .background(isSelected ? Color.accentColor : Color.black.opacity(0.78), in: Circle())
          .overlay {
            Circle()
              .strokeBorder(.white.opacity(0.8), lineWidth: 1)
          }
          .shadow(color: Color.black.opacity(0.24), radius: 6, y: 2)
          .scaleEffect(isSelected ? 1.08 : 1)
          .animation(.spring(response: 0.22, dampingFraction: 0.82), value: isSelected)
      }
      .buttonStyle(.plain)
      .position(x: imageRect.minX + point.x * imageRect.width, y: imageRect.minY + point.y * imageRect.height)
      .accessibilityIdentifier("comment-overlay-\(numberedComment.annotationID)")

    case .area(let rect):
      let renderedRect = CGRect(
        x: imageRect.minX + rect.x * imageRect.width,
        y: imageRect.minY + rect.y * imageRect.height,
        width: rect.width * imageRect.width,
        height: rect.height * imageRect.height
      )

      Button(action: onSelect) {
        ZStack(alignment: .topLeading) {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(isSelected ? Color.accentColor : Color.white.opacity(0.85), lineWidth: isSelected ? 2.5 : 2)
            .background(
              RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor.opacity(isSelected ? 0.14 : 0.08))
            )

          Text("\(numberedComment.annotationID)")
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor : Color.black.opacity(0.8), in: Capsule())
            .padding(8)
        }
      }
      .buttonStyle(.plain)
      .frame(width: renderedRect.width, height: renderedRect.height)
      .position(x: renderedRect.midX, y: renderedRect.midY)
      .accessibilityIdentifier("comment-overlay-\(numberedComment.annotationID)")
    }
  }
}

struct ValidationGalleryDraftOverlay: View {
  let draft: ValidationGalleryCommentDraft
  let imageRect: CGRect

  var body: some View {
    switch draft.anchor {
    case .point(let point):
      Circle()
        .fill(Color.accentColor)
        .frame(width: 18, height: 18)
        .overlay {
          Circle().strokeBorder(.white, lineWidth: 2)
        }
        .position(x: imageRect.minX + point.x * imageRect.width, y: imageRect.minY + point.y * imageRect.height)
        .transition(.scale.combined(with: .opacity))
    case .area(let rect):
      let renderedRect = CGRect(
        x: imageRect.minX + rect.x * imageRect.width,
        y: imageRect.minY + rect.y * imageRect.height,
        width: rect.width * imageRect.width,
        height: rect.height * imageRect.height
      )

      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
        .foregroundStyle(Color.accentColor)
        .frame(width: renderedRect.width, height: renderedRect.height)
        .position(x: renderedRect.midX, y: renderedRect.midY)
    }
  }
}
