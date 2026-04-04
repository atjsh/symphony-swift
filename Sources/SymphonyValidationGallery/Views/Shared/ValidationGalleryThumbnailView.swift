import AVFoundation
import AVKit
import SwiftUI

#if os(macOS)
  import AppKit
#endif

#if os(iOS)
  import UIKit
#endif

struct ValidationGalleryThumbnailView: View {
  let url: URL
  let isAvailable: Bool
  var minimumHeight: CGFloat = 180
  var maximumHeight: CGFloat = 220

  @State private var loadedImage: Image?

  var body: some View {
    Group {
      if isAvailable, let image = loadedImage {
        image
          .resizable()
          .scaledToFit()
          .frame(maxWidth: .infinity, minHeight: minimumHeight, maxHeight: maximumHeight)
          .background(Color.secondary.opacity(0.08))
          .accessibilityHidden(true)
      } else if isAvailable {
        Color.secondary.opacity(0.08)
          .frame(maxWidth: .infinity, minHeight: minimumHeight, maxHeight: maximumHeight)
      } else {
        ContentUnavailableView(
          "Missing Image",
          systemImage: "photo.badge.exclamationmark",
          description: Text(url.lastPathComponent)
        )
        .frame(maxWidth: .infinity, minHeight: minimumHeight, maxHeight: maximumHeight)
      }
    }
    .accessibilityHidden(true)
    .task(id: url) {
      loadedImage = nil
      guard isAvailable else { return }
      let image = await ValidationGalleryThumbnailLoader.shared.thumbnail(
        for: url,
        maxPixelSize: Int(maximumHeight * 2)
      )
      guard !Task.isCancelled else { return }
      loadedImage = image
    }
  }
}

struct ValidationGalleryVideoPreview: View {
  let url: URL
  let isAvailable: Bool
  var minimumHeight: CGFloat = 180
  var maximumHeight: CGFloat = 220
  @State private var player: AVPlayer?
  #if os(macOS)
    @State private var posterImage: Image?
  #endif

  var body: some View {
    Group {
      if isAvailable {
        previewBody
          .frame(maxWidth: .infinity, minHeight: minimumHeight, maxHeight: maximumHeight)
          .background(Color.secondary.opacity(0.08))
          .accessibilityIdentifier("validation-gallery-video-preview")
          .accessibilityHidden(true)
      } else {
        ContentUnavailableView(
          "Missing Video",
          systemImage: "play.rectangle.badge.exclamationmark",
          description: Text(url.lastPathComponent)
        )
        .frame(maxWidth: .infinity, minHeight: minimumHeight, maxHeight: maximumHeight)
      }
    }
    .accessibilityHidden(true)
    #if os(macOS)
      .task(id: url) {
        posterImage = await loadPosterImage()
      }
    #endif
  }

  @ViewBuilder
  private var previewBody: some View {
    #if os(macOS)
      if let posterImage = posterImage {
        posterImage
          .resizable()
          .scaledToFit()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .overlay {
            Image(systemName: "play.circle.fill")
              .font(.system(size: 32))
              .foregroundStyle(.white, .black.opacity(0.4))
          }
      } else {
        VStack(spacing: 12) {
          Image(systemName: "play.rectangle.fill")
            .font(.system(size: 42))
            .foregroundStyle(validationGalleryMutedForeground())
          Text(url.lastPathComponent)
            .font(.footnote.monospaced())
            .foregroundStyle(validationGalleryMutedForeground())
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    #else
      VideoPlayer(player: player)
        .onAppear {
          if player == nil {
            player = AVPlayer(url: url)
          }
        }
        .onDisappear {
          player?.pause()
        }
    #endif
  }

  #if os(macOS)
    private func loadPosterImage() async -> Image? {
      guard isAvailable else {
        return nil
      }

      let asset = AVURLAsset(url: url)
      let generator = AVAssetImageGenerator(asset: asset)
      generator.appliesPreferredTrackTransform = true
      guard
        let poster = try? await generator.image(
          at: CMTime(seconds: 0, preferredTimescale: 600)
        )
      else {
        return nil
      }

      return Image(nsImage: NSImage(cgImage: poster.image, size: .zero))
    }
  #endif
}
