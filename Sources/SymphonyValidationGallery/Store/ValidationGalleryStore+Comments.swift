import Foundation

extension ValidationGalleryStore {

  public func comments(for artifact: ValidationGalleryArtifact?) -> [ValidationGalleryComment] {
    numberedComments(for: artifact).map(\.comment)
  }

  public func numberedComments(
    for artifact: ValidationGalleryArtifact?
  ) -> [ValidationGalleryNumberedComment] {
    guard
      let artifact,
      let bundleRootKey = currentBundleRootKey
    else {
      return []
    }

    let artifactComments = commentsByBundleRoot[bundleRootKey]?[artifact.id] ?? []
    guard artifactComments.isEmpty == false else {
      return []
    }

    let numberedIDs = Dictionary(
      uniqueKeysWithValues: numberedCurrentBundleComments().map { ($0.comment.id, $0.annotationID) }
    )
    return artifactComments
      .sorted(by: compareLocalComments(_:_:))
      .compactMap { comment in
        guard let annotationID = numberedIDs[comment.id] else {
          return nil
        }
        return ValidationGalleryNumberedComment(annotationID: annotationID, comment: comment)
      }
  }

  public func makePointCommentDraft(
    at point: ValidationGalleryNormalizedPoint,
    for artifact: ValidationGalleryArtifact
  ) -> ValidationGalleryCommentDraft {
    ValidationGalleryCommentDraft(
      artifactID: artifact.id,
      anchor: .point(point)
    )
  }

  public func makeAreaCommentDraft(
    _ rect: ValidationGalleryNormalizedRect,
    for artifact: ValidationGalleryArtifact
  ) -> ValidationGalleryCommentDraft {
    ValidationGalleryCommentDraft(
      artifactID: artifact.id,
      anchor: .area(rect)
    )
  }

  public func saveCommentDraft(_ draft: ValidationGalleryCommentDraft, for artifact: ValidationGalleryArtifact) {
    guard
      draft.artifactID == artifact.id,
      artifact.record.artifactType == .screenshot,
      let bundleRootKey = currentBundleRootKey
    else {
      return
    }

    let trimmedBody = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmedBody.isEmpty == false else {
      return
    }

    var bundleComments = commentsByBundleRoot[bundleRootKey] ?? [:]
    var artifactComments = bundleComments[artifact.id] ?? []
    let comment = ValidationGalleryComment(
      artifactID: artifact.id,
      body: trimmedBody,
      anchor: draft.anchor,
      createdAt: now()
    )
    artifactComments.append(comment)
    bundleComments[artifact.id] = artifactComments
    commentsByBundleRoot[bundleRootKey] = bundleComments
    selectedCommentID = comment.id
  }

  public func updateCommentBody(
    _ commentID: ValidationGalleryComment.ID,
    body: String,
    in artifact: ValidationGalleryArtifact
  ) {
    guard
      let bundleRootKey = currentBundleRootKey,
      var bundleComments = commentsByBundleRoot[bundleRootKey],
      var artifactComments = bundleComments[artifact.id],
      let commentIndex = artifactComments.firstIndex(where: { $0.id == commentID })
    else {
      return
    }

    let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmedBody.isEmpty == false else {
      return
    }

    let existingComment = artifactComments[commentIndex]
    artifactComments[commentIndex] = ValidationGalleryComment(
      id: existingComment.id,
      artifactID: existingComment.artifactID,
      body: trimmedBody,
      anchor: existingComment.anchor,
      createdAt: existingComment.createdAt
    )
    bundleComments[artifact.id] = artifactComments
    commentsByBundleRoot[bundleRootKey] = bundleComments
  }

  public func deleteComment(
    _ commentID: ValidationGalleryComment.ID,
    from artifact: ValidationGalleryArtifact
  ) {
    guard
      let bundleRootKey = currentBundleRootKey,
      var bundleComments = commentsByBundleRoot[bundleRootKey],
      var artifactComments = bundleComments[artifact.id]
    else {
      return
    }

    artifactComments.removeAll { $0.id == commentID }

    if artifactComments.isEmpty {
      bundleComments.removeValue(forKey: artifact.id)
    } else {
      bundleComments[artifact.id] = artifactComments
    }

    commentsByBundleRoot[bundleRootKey] = bundleComments

    if selectedCommentID == commentID {
      selectedCommentID = artifactComments.first?.id
    } else {
      normalizeSelectedComment()
    }
  }

  func compareLocalComments(_ lhs: ValidationGalleryComment, _ rhs: ValidationGalleryComment) -> Bool {
    let lhsKey = (lhs.createdAt, lhs.id)
    let rhsKey = (rhs.createdAt, rhs.id)
    return lhsKey < rhsKey
  }
}
