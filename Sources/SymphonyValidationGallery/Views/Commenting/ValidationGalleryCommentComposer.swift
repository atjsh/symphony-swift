import SwiftUI

struct ValidationGalleryCommentComposer: View {
  let title: String
  @Binding var bodyText: String
  let saveButtonTitle: String
  let onSave: () -> Void
  let onCancel: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title)
        .font(.headline.weight(.semibold))

      TextEditor(text: $bodyText)
        .font(.body)
        .frame(minHeight: 96)
        .scrollContentBackground(.hidden)
        .padding(8)
        .background(
          validationGallerySecondaryActionBackgroundColor(),
          in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .accessibilityIdentifier("comment-draft-editor")

      HStack(spacing: 10) {
        Button("Cancel", action: onCancel)
          .buttonStyle(.bordered)
          .accessibilityIdentifier("cancel-comment-button")
        Button(saveButtonTitle, action: onSave)
          .buttonStyle(.borderedProminent)
          .tint(validationGalleryProminentActionTint())
          .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          .accessibilityIdentifier("save-comment-button")
      }
    }
    .padding(.vertical, 4)
  }
}

struct ValidationGalleryCommentEditor: View {
  let numberedComment: ValidationGalleryNumberedComment
  @Binding var bodyText: String
  let onSave: () -> Void
  let onDelete: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text("Comment")
          .font(.headline.weight(.semibold))

        Text("#\(numberedComment.annotationID)")
          .font(.caption.monospacedDigit().weight(.semibold))
          .foregroundStyle(.secondary)
      }

      TextEditor(text: $bodyText)
        .font(.body)
        .frame(minHeight: 84)
        .scrollContentBackground(.hidden)
        .padding(8)
        .background(
          validationGallerySecondaryActionBackgroundColor(),
          in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .accessibilityIdentifier("selected-comment-editor")

      HStack(spacing: 10) {
        Button("Delete Comment", role: .destructive, action: onDelete)
          .buttonStyle(.bordered)
          .accessibilityIdentifier("delete-comment-button")
        Button("Update Comment", action: onSave)
          .buttonStyle(.borderedProminent)
          .tint(validationGalleryProminentActionTint())
          .disabled(
            bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              || bodyText == numberedComment.comment.body
          )
      }
    }
    .padding(.vertical, 4)
  }
}
