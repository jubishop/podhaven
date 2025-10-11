// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import SwiftUI

struct PlayBar: View {
  private let spacing: CGFloat = 12

  @State private var playBarSheetIsPresented = false

  private let viewModel: PlayBarViewModel

  init(viewModel: PlayBarViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    Group {
      if viewModel.isLoading {
        loadingPlayBar
      } else if viewModel.isStopped {
        stoppedPlayBar
      } else if viewModel.isExpanded {
        expandedPlayBar
      } else {
        inlinePlayBar
      }
    }
    .sheet(isPresented: $playBarSheetIsPresented) {
      PlayBarSheet(viewModel: viewModel)
    }
  }

  // MARK: - Loading PlayBar

  private var loadingPlayBar: some View {
    HStack(spacing: spacing) {
      ProgressView()
        .progressViewStyle(CircularProgressViewStyle(tint: .primary))
        .scaleEffect(0.8)

      Text("Loading \(viewModel.loadingEpisodeTitle)")
        .foregroundColor(.primary)
        .lineLimit(1)

      Spacer()
    }
    .padding(.horizontal, spacing)
  }

  // MARK: - Stopped PlayBar

  private var stoppedPlayBar: some View {
    HStack(spacing: spacing) {
      AppIcon.noEpisodeSelected.image

      Text("No episode selected")
        .foregroundColor(.primary)

      Spacer()
    }
    .padding(.horizontal, spacing * 2)
  }

  // MARK: - Inline PlayBar

  private var inlinePlayBar: some View {
    HStack {
      playbackControls
    }
    .padding(.horizontal, spacing)
  }

  // MARK: - Expanded PlayBar

  private var expandedPlayBar: some View {
    HStack {
      Button(
        action: viewModel.showEpisodeDetail,
        label: { episodeThumbnail }
      )

      Spacer()

      playbackControls

      Spacer()

      AppIcon.expandUp.imageButton {
        playBarSheetIsPresented = true
      }
    }
    .padding(.horizontal, spacing * 2)
  }

  // MARK: - Shared Components

  @ViewBuilder
  private var playbackControls: some View {
    Spacer()

    AppIcon.seekBackward.imageButton(action: viewModel.seekBackward)

    Spacer()

    PlayPauseButton(action: viewModel.playOrPause)
      .font(.title3)

    Spacer()

    AppIcon.seekForward.imageButton(action: viewModel.seekForward)

    Spacer()
  }

  private var episodeThumbnail: some View {
    SquareImage(
      image: viewModel.episodeImage,
      placeholderIcon: .audioPlaceholder
    )
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
