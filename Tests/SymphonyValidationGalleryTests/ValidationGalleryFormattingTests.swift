import Testing

@testable import SymphonyValidationGallery
import SymphonyXcodeValidation

@Suite("ValidationGalleryFormatting")
struct ValidationGalleryFormattingTests {
  @Test func browserSubtitleKeepsOnlyDiscriminatingArtifactMetadata() async throws {
    let artifact = try await artifact(
      platform: "macos",
      plan: "ui-tests",
      checkpoint: "root",
      variant: "base",
      type: .screenshot
    )

    #expect(ValidationGalleryFormatting.artifactBrowserSubtitle(artifact) == "portrait · base")
  }

  @Test func inspectorSummaryCombinesOperationalContextIntoSingleLine() async throws {
    let artifact = try await artifact(
      platform: "macos",
      plan: "ui-tests",
      checkpoint: "root",
      variant: "base",
      type: .screenshot
    )

    #expect(
      ValidationGalleryFormatting.artifactInspectorSummary(artifact)
        == "macOS · UI Tests · portrait · base screenshot"
    )
  }

  @Test func recentBundleLabelsNormalizeOpaqueNames() {
    let recent = ValidationRecentBundle(
      kind: .folder,
      displayName: "20260330-011411",
      bookmarkData: nil,
      fallbackPath: "/tmp/validation/20260330-011411",
      lastOpenedAt: .init(timeIntervalSince1970: 0)
    )

    #expect(ValidationGalleryFormatting.recentBundleTitle(recent) == "Validation Bundle")
    #expect(ValidationGalleryFormatting.recentBundleSubtitle(recent) == "20260330-011411")
    #expect(
      ValidationGalleryFormatting.recentBundleMenuTitle(recent)
        == "Validation Bundle (20260330-011411)"
    )
  }

  @Test func outcomeFormattingAddsExplicitStatusIcons() {
    #expect(ValidationGalleryFormatting.outcomeTitle(.passed) == "Passed")
    #expect(ValidationGalleryFormatting.outcomeSymbolName(.passed) == "checkmark.circle.fill")
    #expect(ValidationGalleryFormatting.outcomeTitle(.failed) == "Failed")
    #expect(ValidationGalleryFormatting.outcomeSymbolName(.failed) == "exclamationmark.triangle.fill")
  }

  @Test func noResultsCopyExplainsHowToRecover() {
    #expect(
      ValidationGalleryFormatting.noResultsDescription(
        searchText: "",
        visibleScopeTitle: "All Artifacts"
      ) == "No artifacts are visible in All Artifacts. Clear or change the current filters to keep browsing."
    )
    #expect(
      ValidationGalleryFormatting.noResultsDescription(
        searchText: "walkthrough",
        visibleScopeTitle: "iPhone · UI Tests"
      ) == "No artifacts match “walkthrough” in iPhone · UI Tests. Try a different term or clear the search to keep browsing."
    )
  }

  @Test func exportSummaryCopyUsesNativeUtilityLanguage() {
    #expect(
      ValidationGalleryFormatting.exportSummaryDescription(applyAreaDiagram: true)
        == "Saved screenshots include numbered markers for each comment."
    )
    #expect(
      ValidationGalleryFormatting.exportSummaryDescription(applyAreaDiagram: false)
        == "Saved screenshots stay unmarked, and comment numbering remains in comments.json."
    )
  }

  @Test func emptyExportCopyExplainsHowToEnableExport() {
    #expect(
      ValidationGalleryFormatting.emptyExportDescription(scope: .selectedArtifact)
        == "Add a comment to this screenshot to enable Export."
    )
    #expect(
      ValidationGalleryFormatting.emptyExportDescription(scope: .currentBundle)
        == "Add at least one comment in this bundle to enable Export."
    )
  }

  @Test func exportAnnotationColorCopyExplainsCurrentSelection() {
    #expect(
      ValidationGalleryFormatting.exportAnnotationColorDescription(.red)
        == "Numbered markers use red in exported media."
    )
    #expect(
      ValidationGalleryFormatting.exportAnnotationColorDescription(.indigo)
        == "Numbered markers use indigo in exported media."
    )
  }

  @Test func recoveryCopyGuidesSelectionAndEmptyStates() async throws {
    let artifact = try await artifact(
      platform: "macos",
      plan: "app-tests",
      checkpoint: "progress-report",
      variant: "base",
      type: .screenshot
    )

    #expect(
      ValidationGalleryFormatting.selectionUpdatedMessage(for: artifact)
        == "The previous selection is hidden by the current filters, so Progress Report is now selected."
    )
    #expect(
      ValidationGalleryFormatting.inspectorEmptyStateTitle(hasActiveFilters: false)
        == "Choose an Artifact"
    )
    #expect(
      ValidationGalleryFormatting.inspectorEmptyStateDescription(hasActiveFilters: false)
        == "Select a screenshot or video from the browser to inspect its preview, metadata, and audit context."
    )
    #expect(
      ValidationGalleryFormatting.inspectorEmptyStateTitle(hasActiveFilters: true)
        == "No Artifact in View"
    )
    #expect(
      ValidationGalleryFormatting.inspectorEmptyStateDescription(hasActiveFilters: true)
        == "Clear or change the current filters to restore the detail view."
    )
    #expect(
      ValidationGalleryFormatting.commentListEmptyDescription(isAddingComment: false)
        == "Choose Add Comment from the detail view to place the first marker on this screenshot."
    )
    #expect(
      ValidationGalleryFormatting.commentListEmptyDescription(isAddingComment: true)
        == "Place a marker on the screenshot to create the first comment."
    )
  }

  @Test func destructiveFlowCopyExplainsConsequences() {
    #expect(
      ValidationGalleryFormatting.discardDraftTitle == "Discard New Comment?"
    )
    #expect(
      ValidationGalleryFormatting.discardDraftMessage == "This draft comment hasn’t been saved yet."
    )
    #expect(
      ValidationGalleryFormatting.deleteCommentTitle(annotationID: 3)
        == "Delete Comment #3?"
    )
    #expect(
      ValidationGalleryFormatting.deleteCommentMessage
        == "This removes the comment from the screenshot and from any future export."
    )
  }

  private func artifact(
    platform: String,
    plan: String,
    checkpoint: String,
    variant: String,
    type: MediaArtifactType
  ) async throws -> ValidationGalleryArtifact {
    let snapshot = try await ValidationBundleLoader().load(from: .folder(ValidationGalleryTestFixture.bundleRoot))
    guard
      let artifact = snapshot.artifacts.first(where: {
        $0.record.platform == platform
          && $0.record.plan == plan
          && $0.record.checkpoint == checkpoint
          && $0.record.variant == variant
          && $0.record.artifactType == type
      })
    else {
      Issue.record("Expected artifact missing from bundled fixture.")
      throw TestFailure()
    }

    return artifact
  }
}

private struct TestFailure: Error {}
