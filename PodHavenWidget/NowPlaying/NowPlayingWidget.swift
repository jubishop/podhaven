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
    let nextUpdate = Date().addingTimeInterval(1800)
    let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
    completion(timeline)
  }

  private func makeEntry() -> NowPlayingEntry {
    let playbackStatus = WidgetInfo.playbackStatus

    if let loadingTitle = playbackStatus.loadingTitle {
      Self.log.debug("makeEntry: loading \(loadingTitle)")
      return NowPlayingEntry(
        date: Date(),
        episodeTitle: loadingTitle,
        podcastTitle: "",
        pubDateFormatted: "",
        durationFormatted: "",
        playbackStatus: playbackStatus,
        artwork: nil,
        skipForwardInterval: 0,
        skipBackwardInterval: 0
      )
    }

    guard let snapshot = WidgetSnapshotReader.read() else {
      Self.log.warning("makeEntry: no snapshot available, returning empty")
      return .empty
    }

    guard let nowPlaying = snapshot.nowPlaying else {
      Self.log.warning("makeEntry: snapshot has no nowPlaying, returning empty")
      return .empty
    }

    Self.log.debug(
      """
      makeEntry: \(nowPlaying.episodeTitle) \
      (\(playbackStatus)), \
      artwork=\(nowPlaying.artworkBase64 != nil)
      """
    )

    return NowPlayingEntry(
      date: Date(),
      episodeTitle: nowPlaying.episodeTitle,
      podcastTitle: nowPlaying.podcastTitle,
      pubDateFormatted: Date(timeIntervalSince1970: nowPlaying.pubDateTimestamp).usShort,
      durationFormatted: nowPlaying.durationSeconds.playbackTimeFormat,
      playbackStatus: playbackStatus,
      artwork: WidgetSnapshotReader.decodeArtwork(from: nowPlaying.artworkBase64),
      skipForwardInterval: snapshot.skipForwardInterval,
      skipBackwardInterval: snapshot.skipBackwardInterval
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
