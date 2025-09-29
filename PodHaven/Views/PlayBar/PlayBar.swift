// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import SwiftUI

// Eventually we should replace this with TabViewBottomAccessoryPlacement
struct PlayBarAccessory: View {
  nonisolated static let CoordinateName = "TabRoot"

  @State private var isExpanded = true

  private let tabMaxY: CGFloat

  init(tabMaxY: CGFloat) {
    self.tabMaxY = tabMaxY
  }

  var body: some View {
    PlayBar(isExpanded: isExpanded)
      .onGeometryChange(for: CGFloat.self) { proxy in
        proxy.frame(in: .named(Self.CoordinateName)).maxY
      } action: { newMaxY in
        isExpanded = (tabMaxY - newMaxY) > 40
      }
  }
}

struct PlayBar: View {
  private let basicSpacing: CGFloat = 12

  private let viewModel = PlayBarViewModel()

  private let isExpanded: Bool

  init(isExpanded: Bool) {
    self.isExpanded = isExpanded
  }

  var body: some View {
    if viewModel.isLoading {
      loadingPlayBar
    } else if viewModel.isStopped {
      stoppedPlayBar
    } else if isExpanded {
      expandedPlayBar
    } else {
      inlinePlayBar
    }
  }

  // MARK: - Loading PlayBar

  private var loadingPlayBar: some View {
    HStack(spacing: basicSpacing) {
      ProgressView()
        .progressViewStyle(CircularProgressViewStyle(tint: .white))
        .scaleEffect(0.8)

      Text("Loading \(viewModel.loadingEpisodeTitle)")
        .foregroundColor(.white)
        .lineLimit(1)

      Spacer()
    }
    .padding(.horizontal, basicSpacing)
  }

  // MARK: - Stopped PlayBar

  private var stoppedPlayBar: some View {
    HStack(spacing: basicSpacing) {
      AppIcon.noEpisodeSelected.coloredImage

      Text("No episode selected")
        .foregroundColor(.white)

      Spacer()
    }
    .padding(.horizontal, basicSpacing * 2)
  }

  // MARK: - Inline PlayBar

  private var inlinePlayBar: some View {
    HStack {
      playbackControls
    }
    .padding(.horizontal, basicSpacing)
  }

  // MARK: - Progress Bar

  private var expandedPlayBar: some View {
    HStack {
      episodeImage

      Spacer()

      playbackControls

      Spacer()

      sheetControlsButton
    }
    .padding(.horizontal, basicSpacing * 2)
  }

  // MARK: - Shared Components

  private var episodeImage: some View {
    Button(
      action: viewModel.showEpisodeDetail,
      label: {
        if let image = viewModel.episodeImage {
          Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
          RoundedRectangle(cornerRadius: 8)
            .aspectRatio(contentMode: .fill)
            .overlay(AppIcon.audioPlaceholder.coloredImage)
        }
      }
    )
  }

  @ViewBuilder
  private var playbackControls: some View {
    Spacer()

    AppIcon.seekBackward.imageButton(action: viewModel.seekBackward)
      .font(.title3)

    Spacer()

    playPauseButton
      .font(.title)

    Spacer()

    AppIcon.seekForward.imageButton(action: viewModel.seekForward)
      .font(.title3)

    Spacer()
  }

  @ViewBuilder
  private var playPauseButton: some View {
    let action = viewModel.playOrPause
    if viewModel.isWaiting {
      AppIcon.loading.imageButton(action: action)
    } else if viewModel.isPlaying {
      AppIcon.pauseButton.imageButton(action: action)
    } else {
      AppIcon.playButton.imageButton(action: action)
    }
  }

  private var sheetControlsButton: some View {
    AppIcon.expandUp.imageButton(action: viewModel.showControlSheet)
  }
}

// MARK: - Preview

#if DEBUG
struct PlayBarPreview: View {
  var playState: PlayState { Container.shared.playState() }

  let image: UIImage?

  init(
    _ status: PlaybackStatus,
    image: UIImage? = PreviewBundle.loadImage(
      named: "pod-save-america-podcast",
      in: .EpisodeThumbnails
    )
  ) {
    self.image = image
    playState.setStatus(status)
  }

  var body: some View {
    ContentView()
      .preview()
      .task {
        playState.setOnDeck(
          OnDeck(
            episodeID: Episode.ID(1),
            feedURL: FeedURL(URL.valid()),
            guid: GUID(String.random()),
            podcastTitle: "Podcast Title",
            podcastURL: URL.valid(),
            episodeTitle: "Episode Title",
            duration: CMTime.minutes(60),
            image: image,
            mediaURL: MediaURL(URL.valid()),
            pubDate: 48.hoursAgo
          )
        )
        playState.setCurrentTime(CMTime.minutes(30))

        for _ in 1...10 {
          _ = try! await Create.podcastEpisode()
        }
        Container.shared.navigation().showPodcastList(.unsubscribed)
      }
  }
}

#Preview("waiting") {
  PlayBarPreview(.waiting)
}

#Preview("playing") {
  PlayBarPreview(.playing)
}

#Preview("no image") {
  PlayBarPreview(.playing, image: nil)
}

#Preview("paused") {
  PlayBarPreview(.paused)
}

#Preview("stopped") {
  PlayBarPreview(.stopped)
}

#Preview("loading") {
  PlayBarPreview(.loading("Episode Title Here"))
}

#endif
