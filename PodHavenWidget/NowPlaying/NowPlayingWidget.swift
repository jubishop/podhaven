// Copyright Justin Bishop, 2026

import Logging
import SwiftUI
import WidgetKit

struct NowPlayingProvider: TimelineProvider {
  private static let log = Logger(label: "PodHavenWidget/NowPlaying")

  func placeholder(in context: Context) -> NowPlayingEntry {
    .preview
  }

  func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
    Self.log.debug("getSnapshot called (isPreview=\(context.isPreview))")
    completion(makeEntry())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
    Self.log.debug("getTimeline called (family=\(context.family))")
    let entry = makeEntry()
    let nextUpdate = Date().addingTimeInterval(300)
    let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
    completion(timeline)
  }

  private func makeEntry() -> NowPlayingEntry {
    guard let snapshot = WidgetSnapshotReader.read() else {
      Self.log.warning("makeEntry: no snapshot available, returning empty")
      return .empty
    }

    if let loadingTitle = snapshot.loadingTitle {
      Self.log.debug("makeEntry: loading \(loadingTitle)")
      return NowPlayingEntry(
        date: Date(),
        episodeTitle: loadingTitle,
        podcastTitle: nil,
        durationSeconds: 0,
        currentTimeSeconds: 0,
        playbackStatus: .loading(loadingTitle),
        artwork: nil
      )
    }

    guard let nowPlaying = snapshot.nowPlaying else {
      Self.log.info("makeEntry: snapshot has no nowPlaying, returning empty")
      return .empty
    }

    Self.log.debug(
      "makeEntry: \(nowPlaying.episodeTitle) (\(nowPlaying.playbackStatus)), artwork=\(nowPlaying.artworkBase64 != nil)"
    )

    return NowPlayingEntry(
      date: Date(),
      episodeTitle: nowPlaying.episodeTitle,
      podcastTitle: nowPlaying.podcastTitle,
      durationSeconds: nowPlaying.durationSeconds,
      currentTimeSeconds: nowPlaying.currentTimeSeconds,
      playbackStatus: nowPlaying.playbackStatus,
      artwork: WidgetSnapshotReader.decodeArtwork(from: nowPlaying.artworkBase64)
    )
  }
}

struct NowPlayingWidget: Widget {
  let kind = WidgetInfo.nowPlayingKind

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
