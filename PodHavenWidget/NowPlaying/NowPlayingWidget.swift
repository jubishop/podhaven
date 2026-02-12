// Copyright Justin Bishop, 2026

import SwiftUI
import WidgetKit

struct NowPlayingProvider: TimelineProvider {
  func placeholder(in context: Context) -> NowPlayingEntry {
    .preview
  }

  func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
    completion(makeEntry())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
    let entry = makeEntry()
    let nextUpdate = Date().addingTimeInterval(300)
    let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
    completion(timeline)
  }

  private func makeEntry() -> NowPlayingEntry {
    guard let snapshot = WidgetSnapshotReader.read(),
      let nowPlaying = snapshot.nowPlaying
    else {
      return .empty
    }

    return NowPlayingEntry(
      date: Date(),
      episodeTitle: nowPlaying.episodeTitle,
      podcastTitle: nowPlaying.podcastTitle,
      durationSeconds: nowPlaying.durationSeconds,
      currentTimeSeconds: nowPlaying.currentTimeSeconds,
      isPlaying: nowPlaying.playbackStatus == "playing",
      artwork: WidgetSnapshotReader.decodeArtwork(from: nowPlaying.artworkBase64)
    )
  }
}

struct NowPlayingWidget: Widget {
  let kind = WidgetConstants.nowPlayingKind

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: NowPlayingProvider()) { entry in
      NowPlayingWidgetView(entry: entry)
        .containerBackground(.fill.tertiary, for: .widget)
    }
    .configurationDisplayName("Now Playing")
    .description("See what's currently playing and control playback.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}
