// Copyright Justin Bishop, 2026

import AppIntents
import SwiftUI
import WidgetKit

struct NowPlayingWidgetView: View {
  @Environment(\.widgetFamily) var family

  let entry: NowPlayingEntry

  private var isMedium: Bool { family == .systemMedium }

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
    VStack(alignment: .leading, spacing: 0) {
      if let loadingTitle = entry.playbackStatus.loadingTitle {
        loadingState(episodeTitle: loadingTitle)
      } else if entry.playbackStatus.stopped || entry.episodeTitle == nil {
        emptyState
      } else if let episodeTitle = entry.episodeTitle {
        HStack(alignment: .top) {
          artworkView(size: 52)
          Spacer()
          VStack(alignment: .leading, spacing: 8) {
            CompactMetadataItem(appIcon: .publishDate, value: entry.pubDateFormatted)
            CompactMetadataItem(appIcon: .duration, value: entry.durationFormatted)
          }
          .font(.caption2)
        }

        Spacer(minLength: 0)

        Text(episodeTitle)
          .font(.caption)
          .fontWeight(.semibold)
          .lineLimit(2)

        Spacer(minLength: 0)

        HStack(spacing: 0) {
          seekBackwardButton(interval: entry.skipBackwardInterval).font(.caption2)
          Spacer(minLength: 0)
          playPauseButton.font(.caption)
          Spacer(minLength: 0)
          seekForwardButton(interval: entry.skipForwardInterval).font(.caption2)
        }
        .frame(maxWidth: .infinity)
      }
    }
    .dynamicTypeSize(.small ... .xLarge)
  }

  // MARK: - System Medium

  private var mediumView: some View {
    HStack(spacing: 12) {
      if let loadingTitle = entry.playbackStatus.loadingTitle {
        loadingState(episodeTitle: loadingTitle)
      } else if entry.playbackStatus.stopped || entry.episodeTitle == nil {
        emptyState
      } else if let episodeTitle = entry.episodeTitle {
        artworkView(size: 80)

        VStack(alignment: .leading, spacing: 4) {
          Text(episodeTitle)
            .font(.subheadline)
            .fontWeight(.semibold)
            .lineLimit(2)

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
    .dynamicTypeSize(.small ... .xxxLarge)
  }

  // MARK: - Components

  private func artworkView(size: CGFloat) -> some View {
    OptionalLink(url: URL(string: "podhaven://widget/now-playing")) {
      SquareImage(
        image: entry.artwork,
        cornerRadius: 8,
        size: size,
        placeholderIcon: .audioPlaceholder
      )
    }
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
      }
    }
  }

  private func seekForwardButton(interval: Int) -> some View {
    Button(intent: SkipForwardIntent()) {
      AppIcon.seekForward(interval).image
    }
  }

  private func seekBackwardButton(interval: Int) -> some View {
    Button(intent: SkipBackwardIntent()) {
      AppIcon.seekBackward(interval).image
    }
  }

  private func loadingState(episodeTitle: String) -> some View {
    VStack(spacing: isMedium ? 10 : 8) {
      AppIcon.loading.image
        .font(isMedium ? .title2 : .title3)
        .foregroundStyle(.secondary)
      Text("Loading \(episodeTitle)")
        .font(isMedium ? .subheadline : .caption)
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var emptyState: some View {
    VStack(spacing: isMedium ? 10 : 8) {
      Image(systemName: AppIcon.noEpisodeSelected.systemImageName)
        .font(isMedium ? .title : .title2)
        .foregroundStyle(.secondary)
      Text("Nothing Playing")
        .font(isMedium ? .subheadline : .caption)
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
  NowPlayingEntry(
    date: Date(),
    episodeTitle: "Understanding Swift Concurrency",
    podcastTitle: nil,
    pubDateFormatted: "",
    durationFormatted: "",
    playbackStatus: .loading("Understanding Swift Concurrency"),
    artwork: nil,
    skipForwardInterval: 30,
    skipBackwardInterval: 15
  )
  NowPlayingEntry.empty
}

#Preview("Now Playing - Medium", as: .systemMedium) {
  NowPlayingWidget()
} timeline: {
  NowPlayingEntry.preview
  NowPlayingEntry(
    date: Date(),
    episodeTitle: "Understanding Swift Concurrency",
    podcastTitle: nil,
    pubDateFormatted: "",
    durationFormatted: "",
    playbackStatus: .loading("Understanding Swift Concurrency"),
    artwork: nil,
    skipForwardInterval: 30,
    skipBackwardInterval: 15
  )
  NowPlayingEntry.empty
}
#endif
