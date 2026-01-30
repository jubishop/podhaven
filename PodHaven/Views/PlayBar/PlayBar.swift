// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import Sharing
import SwiftUI
import Tagged

struct PlayBar: View {
  @Environment(\.tabViewBottomAccessoryPlacement) var placement

  private let spacing: CGFloat = 12

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
      } else if placement == .expanded {
        expandedPlayBar
      } else {
        inlinePlayBar
      }
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
        action: PlayBar.showOnDeckEpisodeDetail,
        label: { episodeThumbnail }
      )

      Spacer()

      playbackControls

      Spacer()

      AppIcon.expandUp.imageButton {
        viewModel.playBarSheetIsPresented = true
      }
    }
    .padding(.horizontal, spacing * 2)
  }

  // MARK: - Shared Components

  private var episodeThumbnail: some View {
    SquareImage(
      image: viewModel.episodeImage,
      placeholderIcon: .audioPlaceholder
    )
    .padding(.vertical, 4)
  }

  @ViewBuilder
  private var playbackControls: some View {
    Spacer()

    SeekBackwardButton(action: viewModel.seekBackward)
      .font(.title2)

    Spacer()

    PlayPauseButton(action: viewModel.playOrPause)
      .font(.title)

    Spacer()

    SeekForwardButton(action: viewModel.seekForward)
      .font(.title2)

    Spacer()
  }

}

// MARK: - Static Actions

extension PlayBar {
  static func showOnDeckEpisodeDetail() {
    @DynamicInjected(\.alert) var alert

    Task {
      do {
        try await presentOnDeckEpisodeDetail()
      } catch {
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.coreMessage(for: error))
      }
    }
  }

  private static func presentOnDeckEpisodeDetail() async throws {
    @DynamicInjected(\.repo) var repo
    @DynamicInjected(\.sharedState) var sharedState
    @DynamicInjected(\.sheet) var sheet

    guard let onDeck = sharedState.onDeck,
      let podcastEpisode = try await repo.podcastEpisode(onDeck.id)
    else { return }

    sheet {
      NavigationStack {
        EpisodeDetailView(
          viewModel: EpisodeDetailViewModel(
            episode: DisplayedEpisode.getDisplayedEpisode(podcastEpisode)
          )
        )
      }
    }
  }
}

// MARK: - Preview

#if DEBUG
struct PlayBarPreview: View {
  var sharedState: SharedState { Container.shared.sharedState() }

  let image: UIImage?

  let status: PlaybackStatus

  init(
    _ status: PlaybackStatus,
    image: UIImage? = PreviewBundle.loadImage(
      named: "pod-save-america-podcast",
      in: .EpisodeThumbnails
    )
  ) {
    self.status = status
    self.image = image
  }

  var body: some View {
    ContentView()
      .preview()
      .task {
        sharedState.setPlaybackStatus(status)

        let podcastEpisode = try! await Create.podcastEpisode()
        sharedState.$onDeck.withLock { $0 = OnDeck(podcastEpisode: podcastEpisode, artwork: image) }

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
