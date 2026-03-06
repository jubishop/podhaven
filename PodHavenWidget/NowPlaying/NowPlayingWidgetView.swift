// Copyright Justin Bishop, 2026

import AppIntents
import SwiftUI
import WidgetKit

struct NowPlayingWidgetView: View {
  let entry: NowPlayingEntry

  @Environment(\.widgetFamily) var family

  var body: some View {
    switch family {
    case .systemSmall:
      smallView
    case .systemMedium:
      mediumView
    default:
      smallView
    }
  }

  // MARK: - System Small

  private var smallView: some View {
    VStack(alignment: .leading, spacing: 6) {
      if entry.playbackStatus.loading, let episodeTitle = entry.episodeTitle {
        loadingState(episodeTitle: episodeTitle)
      } else if entry.playbackStatus.stopped || entry.episodeTitle == nil {
        emptyState
      } else if let episodeTitle = entry.episodeTitle {
        artworkView(size: 44)

        Text(episodeTitle)
          .font(.caption)
          .fontWeight(.semibold)
          .lineLimit(2)
          .foregroundStyle(.primary)

        Spacer(minLength: 0)

        HStack {
          playPauseButton
          Spacer()
          Text(entry.durationFormatted)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
    }
    .widgetURL(URL(string: "podhaven://widget/now-playing"))
  }

  // MARK: - System Medium

  private var mediumView: some View {
    HStack(spacing: 12) {
      if entry.playbackStatus.loading, let episodeTitle = entry.episodeTitle {
        loadingState(episodeTitle: episodeTitle)
      } else if entry.playbackStatus.stopped || entry.episodeTitle == nil {
        emptyState
      } else if let episodeTitle = entry.episodeTitle {
        artworkView(size: 80)

        VStack(alignment: .leading, spacing: 4) {
          Text(episodeTitle)
            .font(.subheadline)
            .fontWeight(.semibold)
            .lineLimit(2)
            .foregroundStyle(.primary)

          if let podcastTitle = entry.podcastTitle {
            Text(podcastTitle)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }

          Spacer(minLength: 0)

          HStack(spacing: 16) {
            seekBackwardButton(interval: entry.skipBackwardInterval)
            playPauseButton
            seekForwardButton(interval: entry.skipForwardInterval)

            Spacer()

            Text(entry.durationFormatted)
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
    .widgetURL(URL(string: "podhaven://widget/now-playing"))
  }

  // MARK: - Components

  private func artworkView(size: CGFloat) -> some View {
    SquareImage(
      image: entry.artwork,
      cornerRadius: 8,
      size: size,
      placeholderIcon: .audioPlaceholder
    )
  }

  private var playPauseButton: some View {
    Group {
      if entry.playbackStatus.waiting {
        AppIcon.loading.image
          .disabled(true)
      } else {
        Button(intent: PlayPauseIntent()) {
          if entry.playbackStatus.playing {
            AppIcon.pauseButton.image
          } else {
            AppIcon.playButton.image
          }
        }
        .buttonStyle(.plain)
      }
    }
  }

  private func seekForwardButton(interval: Int) -> some View {
    Button(intent: SkipForwardIntent()) {
      AppIcon.seekForward(interval).image
    }
    .buttonStyle(.plain)
  }

  private func seekBackwardButton(interval: Int) -> some View {
    Button(intent: SkipBackwardIntent()) {
      AppIcon.seekBackward(interval).image
    }
    .buttonStyle(.plain)
  }

  private func loadingState(episodeTitle: String) -> some View {
    VStack(spacing: 8) {
      ProgressView()
        .scaleEffect(0.8)
      Text("Loading \(episodeTitle)")
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var emptyState: some View {
    VStack(spacing: 8) {
      Image(systemName: AppIcon.noEpisodeSelected.systemImageName)
        .font(.title2)
        .foregroundStyle(.secondary)
      Text("Nothing Playing")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

#if DEBUG
#Preview("Now Playing - Small", as: .systemSmall) {
  NowPlayingWidget()
} timeline: {
  NowPlayingEntry.preview
  NowPlayingEntry.empty
}

#Preview("Now Playing - Medium", as: .systemMedium) {
  NowPlayingWidget()
} timeline: {
  NowPlayingEntry.preview
  NowPlayingEntry.empty
}

#Preview("Loading - Small", as: .systemSmall) {
  NowPlayingWidget()
} timeline: {
  NowPlayingEntry(
    date: Date(),
    episodeTitle: "Understanding Swift Concurrency",
    podcastTitle: nil,
    durationFormatted: "",
    playbackStatus: .loading("Understanding Swift Concurrency"),
    artwork: nil,
    skipForwardInterval: 30,
    skipBackwardInterval: 15
  )
}

#Preview("Loading - Medium", as: .systemMedium) {
  NowPlayingWidget()
} timeline: {
  NowPlayingEntry(
    date: Date(),
    episodeTitle: "Understanding Swift Concurrency",
    podcastTitle: nil,
    durationFormatted: "",
    playbackStatus: .loading("Understanding Swift Concurrency"),
    artwork: nil,
    skipForwardInterval: 30,
    skipBackwardInterval: 15
  )
}

#Preview("Waiting - Small", as: .systemSmall) {
  NowPlayingWidget()
} timeline: {
  NowPlayingEntry(
    date: Date(),
    episodeTitle: "Understanding Swift Concurrency",
    podcastTitle: "Swift Talk",
    durationFormatted: "41:00",
    playbackStatus: .waiting,
    artwork: nil,
    skipForwardInterval: 30,
    skipBackwardInterval: 15
  )
}

#Preview("Waiting - Medium", as: .systemMedium) {
  NowPlayingWidget()
} timeline: {
  NowPlayingEntry(
    date: Date(),
    episodeTitle: "Understanding Swift Concurrency",
    podcastTitle: "Swift Talk",
    durationFormatted: "41:00",
    playbackStatus: .waiting,
    artwork: nil,
    skipForwardInterval: 30,
    skipBackwardInterval: 15
  )
}
#endif
