// Copyright Justin Bishop, 2026

import AppIntents
import SwiftUI
import WidgetKit

struct NowPlayingQueueWidgetView: View {
  private let artworkSize: CGFloat = 72

  let entry: NowPlayingQueueEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      header
      Divider()
      QueueListView(items: entry.queueItems)
    }
    .dynamicTypeSize(.small ... .xxxLarge)
  }

  // MARK: - Header

  @ViewBuilder
  private var header: some View {
    if let loadingTitle = entry.playbackStatus.loadingTitle {
      placeholderHeader(title: loadingTitle.isEmpty ? "Loading…" : "Loading \(loadingTitle)")
    } else if entry.playbackStatus.stopped {
      placeholderHeader(title: "Nothing playing")
    } else {
      HStack(spacing: 12) {
        OptionalLink(url: URL(string: "podhaven://widget/now-playing/episode")) {
          SquareImage(
            image: entry.artwork,
            cornerRadius: 8,
            size: artworkSize,
            placeholderIcon: .audioPlaceholder
          )
        }

        VStack(alignment: .leading, spacing: 0) {
          Text(entry.episodeTitle)
            .font(.subheadline)
            .fontWeight(.semibold)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .topLeading)

          Spacer(minLength: 4)

          transportControls
        }
        .frame(height: artworkSize)
      }
    }
  }

  private func placeholderHeader(title: String) -> some View {
    HStack(spacing: 12) {
      SquareImage(
        image: nil,
        cornerRadius: 8,
        size: artworkSize,
        placeholderIcon: .audioPlaceholder
      )

      Text(title)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(height: artworkSize)
  }

  private var transportControls: some View {
    HStack(spacing: 0) {
      Button(intent: SkipBackwardIntent()) {
        AppIcon.seekBackward(entry.skipBackwardInterval).image
      }
      .font(.callout)

      Spacer(minLength: 0)

      playPauseButton.font(.title3)

      Spacer(minLength: 0)

      Button(intent: SkipForwardIntent()) {
        AppIcon.seekForward(entry.skipForwardInterval).image
      }
      .font(.callout)

      Spacer(minLength: 0)

      Button(intent: FinishEpisodeIntent()) {
        AppIcon.finishEpisode.image
      }
      .font(.callout)
    }
    .frame(maxWidth: .infinity)
  }

  @ViewBuilder
  private var playPauseButton: some View {
    if entry.playbackStatus.waiting {
      AppIcon.loading.image
        .disabled(true)
    } else {
      Button(intent: PlayPauseIntent(playing: !entry.playbackStatus.playing)) {
        if entry.playbackStatus.playing {
          AppIcon.pauseButton.image
        } else {
          AppIcon.playButton.image
        }
      }
    }
  }
}

#if DEBUG
#Preview("Now Playing & Up Next", as: .systemLarge) {
  NowPlayingQueueWidget()
} timeline: {
  NowPlayingQueueEntry.preview
  NowPlayingQueueEntry(
    date: Date(),
    episodeTitle: "",
    playbackStatus: .loading("Understanding Swift Concurrency"),
    artwork: nil,
    skipForwardInterval: 30,
    skipBackwardInterval: 15,
    queueItems: QueueEntry.preview.items
  )
  NowPlayingQueueEntry.empty
}
#endif
