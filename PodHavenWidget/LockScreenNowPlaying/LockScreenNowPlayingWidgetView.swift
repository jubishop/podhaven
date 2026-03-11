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
      Image(systemName: AppIcon.noEpisodeSelected.systemImageName)
        .font(.title2)
        .foregroundStyle(.secondary)
        .widgetAccentable()
    } else if entry.playbackStatus.loading || entry.playbackStatus.waiting {
      Image(systemName: AppIcon.loading.systemImageName)
        .font(.title2)
        .foregroundStyle(.secondary)
        .widgetAccentable()
    } else {
      Button(intent: PlayPauseIntent()) {
        Image(
          systemName: entry.playbackStatus.playing
            ? AppIcon.pauseButton.systemImageName
            : AppIcon.playButton.systemImageName
        )
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
        Image(systemName: AppIcon.noEpisodeSelected.systemImageName)
          .font(.title3)
          .foregroundStyle(.secondary)
        Text("Nothing Playing")
          .font(.headline)
          .foregroundStyle(.secondary)
      }
    } else if entry.playbackStatus.loading || entry.playbackStatus.waiting {
      HStack(spacing: 6) {
        Image(systemName: AppIcon.loading.systemImageName)
          .font(.title3)
          .foregroundStyle(.secondary)
        Text("Loading...")
          .font(.headline)
          .foregroundStyle(.secondary)
      }
    } else {
      HStack(spacing: 8) {
        Button(intent: PlayPauseIntent()) {
          Image(
            systemName: entry.playbackStatus.playing
              ? AppIcon.pauseButton.systemImageName
              : AppIcon.playButton.systemImageName
          )
          .font(.title2)
          .widgetAccentable()
        }

        VStack(alignment: .leading, spacing: 1) {
          Text(entry.episodeTitle)
            .font(.headline)
            .lineLimit(1)
          Text(entry.podcastTitle)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
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
