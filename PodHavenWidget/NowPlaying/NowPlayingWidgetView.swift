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
      } else if let episodeTitle = entry.episodeTitle {
        artworkView(size: 44)

        Text(episodeTitle)
          .font(.caption)
          .fontWeight(.semibold)
          .lineLimit(2)
          .foregroundStyle(.primary)

        Spacer(minLength: 0)

        HStack {
          playPauseButton(size: 28)
          Spacer()
          Text(entry.durationFormatted)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      } else {
        emptyState
      }
    }
    .widgetURL(URL(string: "podhaven://widget/now-playing"))
  }

  // MARK: - System Medium

  private var mediumView: some View {
    HStack(spacing: 12) {
      if entry.playbackStatus.loading, let episodeTitle = entry.episodeTitle {
        loadingState(episodeTitle: episodeTitle)
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
            skipBackwardButton(size: 24)
            playPauseButton(size: 28)
            skipForwardButton(size: 24)

            Spacer()

            Text(entry.durationFormatted)
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
      } else {
        emptyState
      }
    }
    .widgetURL(URL(string: "podhaven://widget/now-playing"))
  }

  // MARK: - Components

  private func artworkView(size: CGFloat) -> some View {
    Group {
      if let artwork = entry.artwork {
        Image(uiImage: artwork)
          .resizable()
          .aspectRatio(contentMode: .fill)
      } else {
        Image(systemName: "music.note")
          .font(.title2)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(.quaternary)
      }
    }
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }

  private func playPauseButton(size: CGFloat) -> some View {
    Button(intent: PlayPauseIntent()) {
      Image(systemName: entry.playbackStatus == .paused ? "play.fill" : "pause.fill")
        .font(.system(size: size * 0.55))
        .frame(width: size, height: size)
    }
    .buttonStyle(.plain)
  }

  private func skipForwardButton(size: CGFloat) -> some View {
    Button(intent: SkipForwardIntent()) {
      Image(systemName: "forward.fill")
        .font(.system(size: size * 0.45))
        .frame(width: size, height: size)
    }
    .buttonStyle(.plain)
  }

  private func skipBackwardButton(size: CGFloat) -> some View {
    Button(intent: SkipBackwardIntent()) {
      Image(systemName: "backward.fill")
        .font(.system(size: size * 0.45))
        .frame(width: size, height: size)
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
      Image(systemName: "headphones")
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
    artwork: nil
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
    artwork: nil
  )
}
#endif
