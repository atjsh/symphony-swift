# Xcode Validation Gallery App

`XcodeValidationGalleryApp` is the native SwiftUI viewer for validation bundles produced by `SymphonyXcodeValidationRunner`.

## What it opens

- A validation bundle folder that contains `manifest.json`, `summary.json`, `audit-summary.json`, and exported media files.
- A standalone `manifest.json` file when opening the full folder is not convenient.

## What it shows

- Grouped browsing by platform, plan, and checkpoint
- Screenshot inspection with enlarged preview
- Local video playback
- Summary and audit context
- Recent bundles restored from persisted bookmarks

## Development fixture

- Checked-in fixture bundle: `Sources/SymphonyValidationGallery/Resources/XcodeValidationGalleryFixture`
- UI tests bootstrap the app with `XCODE_VALIDATION_GALLERY_UI_TEST_USE_BUNDLED_FIXTURE=1`

## Running it

- Open the `XcodeValidationGalleryApp` scheme in `SymphonyApps.xcodeproj`
- Launch the app on macOS, iPhone simulator, or iPad simulator
- Use `Open Bundle` or `Open Manifest` from the toolbar
