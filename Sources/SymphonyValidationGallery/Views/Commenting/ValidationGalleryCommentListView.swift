import SwiftUI

struct ValidationGalleryCommentList: View {
  let comments: [ValidationGalleryNumberedComment]
  let selectedCommentID: ValidationGalleryComment.ID?
  let isAddingComment: Bool
  let onSelectComment: (ValidationGalleryNumberedComment) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Comments")
        .font(.headline.weight(.semibold))

      if comments.isEmpty {
        ContentUnavailableView {
          Label("No Comments Yet", systemImage: "text.bubble")
        } description: {
          Text(
            ValidationGalleryFormatting.commentListEmptyDescription(
              isAddingComment: isAddingComment
            )
          )
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityIdentifier("comment-list-empty-state")
      } else {
        VStack(spacing: 0) {
          ForEach(Array(comments.enumerated()), id: \.element.id) { index, comment in
            Button {
              onSelectComment(comment)
            } label: {
              HStack(alignment: .top, spacing: 12) {
                Text("\(comment.annotationID)")
                  .font(.caption.monospacedDigit().weight(.semibold))
                  .foregroundStyle(comment.id == selectedCommentID ? .white : .secondary)
                  .frame(width: 24, height: 24)
                  .background(
                    comment.id == selectedCommentID ? Color.accentColor : Color.clear,
                    in: Circle()
                  )

                VStack(alignment: .leading, spacing: 4) {
                  Text(comment.comment.body)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                  Text(anchorSummary(comment.comment.anchor))
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
              }
              .padding(.vertical, 12)
              .padding(.horizontal, 2)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(comment.id == selectedCommentID ? Color.accentColor.opacity(0.08) : Color.clear)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("comment-row-\(comment.annotationID)")

            if index < comments.count - 1 {
              Divider()
                .padding(.leading, 38)
            }
          }
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("comment-list-container")
  }

  private func anchorSummary(_ anchor: ValidationGalleryCommentAnchor) -> String {
    switch anchor {
    case .point(let point):
      return String(format: "point (%.3f, %.3f)", point.x, point.y)
    case .area(let rect):
      return String(
        format: "area (%.3f, %.3f, %.3f, %.3f)",
        rect.x,
        rect.y,
        rect.width,
        rect.height
      )
    }
  }
}
