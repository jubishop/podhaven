// Copyright Justin Bishop, 2026

import AppIntents
import SwiftUI
import WidgetKit

struct LockScreenNowPlayingWidgetView: View {
  @Environment(\.widgetFamily) var family

  let entry: LockScreenNowPlayingEntry

  var body: some View {
    switch family {
    case .accessoryCircular:
      circularView
    case .accessoryRectangular:
      rectangularView
    default:
      Assert.fatal("Incorrect LockScreenNowPlaying widget size: \(family)")
    }
  }

  // MARK: - Accessory Circular

  @ViewBuilder
  private var circularView: some View {
    if entry.playbackStatus.stopped {
      AppIcon.noEpisodeSelected.image
        .font(.title2)
        .widgetAccentable()
    } else if entry.playbackStatus.loading || entry.playbackStatus.waiting {
      AppIcon.loading.image
        .font(.title2)
        .widgetAccentable()
    } else {
      Button(intent: PlayPauseIntent()) {
        (entry.playbackStatus.playing
          ? AppIcon.pauseButton.image
          : AppIcon.playButton.image)
          .font(.title2)
          .widgetAccentable()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }

  // MARK: - Accessory Rectangular

  @ViewBuilder
  private var rectangularView: some View {
    if entry.playbackStatus.stopped {
      HStack(spacing: 6) {
        AppIcon.noEpisodeSelected.image
          .font(.title3)
        Text("Nothing Playing")
          .font(.headline)
      }
    } else if entry.playbackStatus.loading || entry.playbackStatus.waiting {
      HStack(spacing: 6) {
        AppIcon.loading.image
          .font(.title3)
        Text("Loading...")
          .font(.headline)
      }
    } else {
      HStack(spacing: 4) {
        Button(intent: PlayPauseIntent()) {
          (entry.playbackStatus.playing
            ? AppIcon.pauseButton.image
            : AppIcon.playButton.image)
            .font(.title2)
            .widgetAccentable()
        }
        .buttonStyle(.borderless)

        VStack(alignment: .leading) {
          Text(entry.episodeTitle)
            .font(.caption)
            .lineLimit(2, reservesSpace: true)

          Spacer(minLength: 0)

          Text(entry.podcastTitle)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.vertical, 4)
      }
    }
  }
}

#if DEBUG
#Preview("Lock Screen - Circular", as: .accessoryCircular) {
  LockScreenNowPlayingWidget()
} timeline: {
  LockScreenNowPlayingEntry.preview
  LockScreenNowPlayingEntry.empty
}

#Preview("Lock Screen - Rectangular", as: .accessoryRectangular) {
  LockScreenNowPlayingWidget()
} timeline: {
  LockScreenNowPlayingEntry.preview
  LockScreenNowPlayingEntry.empty
}
#endif
