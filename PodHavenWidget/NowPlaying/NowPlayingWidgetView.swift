// Copyright Justin Bishop, 2026

import AppIntents
import SwiftUI
import WidgetKit

struct NowPlayingWidgetView: View {
  @Environment(\.widgetFamily) var family

  private let mediumImageSize: CGFloat = 80

  let entry: NowPlayingEntry

  private var isMedium: Bool { family == .systemMedium }

  var body: some View {
    switch family {
    case .systemSmall:
      smallView.dynamicTypeSize(.small ... .xxLarge)
    case .systemMedium:
      mediumView.dynamicTypeSize(.small ... .xxLarge)
    default:
      Assert.fatal("Incorrect NowPlaying widget size: \(family)")
    }
  }

  // MARK: - System Small

  @ViewBuilder
  private var smallView: some View {
    if let loadingTitle = entry.playbackStatus.loadingTitle {
      loadingState(episodeTitle: loadingTitle)
    } else if entry.playbackStatus.stopped {
      emptyState
    } else {
      VStack(alignment: .leading, spacing: 0) {
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

        Text(entry.episodeTitle)
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
  }

  // MARK: - System Medium

  @ViewBuilder
  private var mediumView: some View {
    if let loadingTitle = entry.playbackStatus.loadingTitle {
      loadingState(episodeTitle: loadingTitle)
    } else if entry.playbackStatus.stopped {
      emptyState
    } else {
      VStack(spacing: 0) {
        HStack(spacing: 12) {
          artworkView(size: mediumImageSize)

          VStack(alignment: .leading, spacing: 0) {
            Text(entry.episodeTitle)
              .font(.subheadline)
              .fontWeight(.semibold)
              .lineLimit(2, reservesSpace: true)
              .frame(maxWidth: .infinity, alignment: .topLeading)

            Spacer(minLength: 4)
            Spacer(minLength: 0)

            Text(entry.podcastTitle)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)

            Spacer(minLength: 0)

            HStack {
              CompactMetadataItem(appIcon: .publishDate, value: entry.pubDateFormatted)
              Spacer()
              CompactMetadataItem(appIcon: .duration, value: entry.durationFormatted)
            }
            .font(.caption)
          }
          .frame(minHeight: mediumImageSize)
          .fixedSize(horizontal: false, vertical: true)
        }

        Spacer(minLength: 0)

        ZStack {
          HStack(spacing: 0) {
            Spacer(minLength: 0)
            seekBackwardButton(interval: entry.skipBackwardInterval).font(.callout)
            Spacer(minLength: 0)
            playPauseButton.font(.headline)
            Spacer(minLength: 0)
            seekForwardButton(interval: entry.skipForwardInterval).font(.callout)
            Spacer(minLength: 0)
          }

          HStack {
            Spacer()
            finishEpisodeButton.font(.callout)
          }
          .padding(.trailing, 4)
        }
        .frame(maxWidth: .infinity)
      }
    }
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

  private var finishEpisodeButton: some View {
    Button(intent: FinishEpisodeIntent()) {
      AppIcon.finishEpisode.image
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
      Text("Stopped")
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
    podcastTitle: "",
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
    podcastTitle: "",
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
