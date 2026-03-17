// Copyright Justin Bishop, 2026

import FactoryKit
import Logging
import SwiftUI
import WidgetKit

struct LockScreenNowPlayingProvider: TimelineProvider {
  private static let log = Log.as(LogSubsystem.Widget.lockScreenNowPlaying)

  func placeholder(in context: Context) -> LockScreenNowPlayingEntry {
    .preview
  }

  func getSnapshot(in context: Context, completion: @escaping (LockScreenNowPlayingEntry) -> Void) {
    Self.log.debug("getSnapshot called (isPreview=\(context.isPreview))")
    completion(makeEntry())
  }

  func getTimeline(
    in context: Context,
    completion: @escaping (Timeline<LockScreenNowPlayingEntry>) -> Void
  ) {
    Self.log.debug("getTimeline called (family=\(context.family))")
    let entry = makeEntry()
    let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(1800)))
    completion(timeline)
  }

  private func makeEntry() -> LockScreenNowPlayingEntry {
    let state = Container.shared.widgetState()
    state.$playbackStatus.refresh()
    let playbackStatus = state.playbackStatus

    if playbackStatus.loadingTitle != nil {
      Self.log.debug("makeEntry: loading")
      return LockScreenNowPlayingEntry(
        date: Date(),
        episodeTitle: "",
        podcastTitle: "",
        playbackStatus: playbackStatus
      )
    }

    guard let snapshot = WidgetSnapshotReader.readNowPlaying() else {
      Self.log.warning("makeEntry: no snapshot available, returning empty")
      return .empty
    }

    guard let nowPlaying = snapshot.nowPlaying else {
      Self.log.warning("makeEntry: snapshot has no nowPlaying, returning empty")
      return .empty
    }

    Self.log.debug("makeEntry: \(nowPlaying.episodeTitle) (\(playbackStatus))")

    return LockScreenNowPlayingEntry(
      date: Date(),
      episodeTitle: nowPlaying.episodeTitle,
      podcastTitle: nowPlaying.podcastTitle,
      playbackStatus: playbackStatus
    )
  }
}

struct LockScreenNowPlayingWidget: Widget {
  let kind = WidgetInfo.lockScreenNowPlayingKind

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: LockScreenNowPlayingProvider()) { entry in
      LockScreenNowPlayingWidgetView(entry: entry)
        .containerBackground(.fill.tertiary, for: .widget)
    }
    .configurationDisplayName("Now Playing")
    .description("Pause or play the current episode from your Lock Screen.")
    .supportedFamilies([.accessoryCircular, .accessoryRectangular])
  }
}
