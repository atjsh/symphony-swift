import AVKit
import SwiftUI

#if os(macOS)
  import AppKit
#endif

struct ValidationGalleryArtifactMediaSurface: View {
  let artifact: ValidationGalleryArtifact
  let minimumHeight: CGFloat
  let accessibilityIdentifier: String
  @State private var player: AVPlayer?

  var body: some View {
    ZStack {
      Group {
        if artifact.record.artifactType == .video {
          if artifact.isAvailable {
            #if os(macOS)
              ValidationGalleryMacVideoPlayerView(
                url: artifact.fileURL,
                accessibilityIdentifier: accessibilityIdentifier
              )
              .frame(minHeight: minimumHeight)
              .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            #else
              VideoPlayer(player: player)
                .frame(minHeight: minimumHeight)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .onAppear {
                  if player == nil {
                    player = AVPlayer(url: artifact.fileURL)
                  }
                }
                .onDisappear {
                  player?.pause()
                }
            #endif
          } else {
            ContentUnavailableView(
              "Missing Video",
              systemImage: "play.rectangle.badge.exclamationmark",
              description: Text(artifact.fileURL.lastPathComponent)
            )
            .frame(maxWidth: .infinity, minHeight: minimumHeight)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
          }
        } else {
          ValidationGalleryDetailImageView(
            url: artifact.fileURL,
            isAvailable: artifact.isAvailable,
            minimumHeight: minimumHeight
          )
        }
      }
      #if os(macOS)
        if artifact.record.artifactType == .video {
          ValidationGalleryAccessibilityMarker(
            identifier: accessibilityIdentifier,
            label: "Video preview"
          )
        }
      #endif
    }
    .accessibilityIdentifier(accessibilityIdentifier)
  }
}

#if os(macOS)
  private struct ValidationGalleryAccessibilityMarker: View {
    let identifier: String
    let label: String

    var body: some View {
      Color.clear
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
        .allowsHitTesting(false)
    }
  }
#endif

#if os(macOS)
  private struct ValidationGalleryMacVideoPlayerView: NSViewRepresentable {
    let url: URL
    let accessibilityIdentifier: String

    func makeNSView(context: Context) -> AVPlayerView {
      let view = AVPlayerView()
      view.controlsStyle = .floating
      view.showsFullScreenToggleButton = true
      view.updatesNowPlayingInfoCenter = false
      view.identifier = NSUserInterfaceItemIdentifier(accessibilityIdentifier)
      view.player = AVPlayer(url: url)
      view.setAccessibilityIdentifier(accessibilityIdentifier)
      return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
      let currentURL = (nsView.player?.currentItem?.asset as? AVURLAsset)?.url
      if currentURL != url {
        nsView.player?.pause()
        nsView.player = AVPlayer(url: url)
      }
      nsView.identifier = NSUserInterfaceItemIdentifier(accessibilityIdentifier)
      nsView.setAccessibilityIdentifier(accessibilityIdentifier)
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: ()) {
      nsView.player?.pause()
      nsView.player = nil
    }
  }
#endif

private struct ValidationGalleryDetailImageView: View {
  let url: URL
  let isAvailable: Bool
  var minimumHeight: CGFloat = 220

  var body: some View {
    if isAvailable {
      ScrollView([.horizontal, .vertical]) {
        ValidationGalleryThumbnailView(url: url, isAvailable: isAvailable)
          .padding(.bottom, 4)
      }
      .frame(maxWidth: .infinity, minHeight: minimumHeight)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    } else {
      ContentUnavailableView(
        "Missing Image",
        systemImage: "photo.badge.exclamationmark",
        description: Text(url.lastPathComponent)
      )
      .frame(maxWidth: .infinity, minHeight: minimumHeight)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
  }
}
