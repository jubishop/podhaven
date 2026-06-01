// Copyright Justin Bishop, 2026

import FactoryKit
import Logging
import SwiftUI
import WidgetKit

struct NowPlayingQueueProvider: TimelineProvider {
  private static let log = Log.as(LogSubsystem.Widget.nowPlayingQueue)

  func placeholder(in context: Context) -> NowPlayingQueueEntry {
    .preview
  }

  func getSnapshot(
    in context: Context,
    completion: @escaping (NowPlayingQueueEntry) -> Void
  ) {
    Self.log.debug("getSnapshot called (isPreview=\(context.isPreview))")
    completion(makeEntry())
  }

  func getTimeline(
    in context: Context,
    completion: @escaping (Timeline<NowPlayingQueueEntry>) -> Void
  ) {
    Self.log.debug("getTimeline called (family=\(context.family))")
    let entry = makeEntry()
    var entries = [entry]

    // Schedule a fallback entry for active states so the header recovers if
    // the app is killed. During playback the app reloads every 4 minutes via
    // a heartbeat (free during an active audio session), pushing this forward.
    let fallbackStatus = entry.playbackStatus.widgetFallback

    if let fallbackStatus {
      entries.append(
        NowPlayingQueueEntry(
          date: Date().addingTimeInterval(300),
          episodeTitle: entry.episodeTitle,
          playbackStatus: fallbackStatus,
          artwork: entry.artwork,
          skipForwardInterval: entry.skipForwardInterval,
          skipBackwardInterval: entry.skipBackwardInterval,
          queueItems: entry.queueItems
        )
      )
    }

    let timeline = Timeline(entries: entries, policy: .after(Date().addingTimeInterval(1800)))
    completion(timeline)
  }

  private func makeEntry() -> NowPlayingQueueEntry {
    let state = Container.shared.widgetState()
    state.$playbackStatus.refresh()
    state.$skipForwardInterval.refresh()
    state.$skipBackwardInterval.refresh()
    let playbackStatus = state.playbackStatus
    let queueItems = readQueue()

    if let loadingTitle = playbackStatus.loadingTitle {
      Self.log.debug("makeEntry: loading \(loadingTitle)")
      return NowPlayingQueueEntry(
        date: Date(),
        episodeTitle: loadingTitle,
        playbackStatus: playbackStatus,
        artwork: nil,
        skipForwardInterval: 0,
        skipBackwardInterval: 0,
        queueItems: queueItems
      )
    }

    guard
      let snapshot = WidgetSnapshotReader.readNowPlaying(),
      let nowPlaying = snapshot.nowPlaying
    else {
      Self.log.debug("makeEntry: no now-playing snapshot, rendering placeholder header")
      return NowPlayingQueueEntry(
        date: Date(),
        episodeTitle: "",
        playbackStatus: .stopped,
        artwork: nil,
        skipForwardInterval: state.skipForwardInterval,
        skipBackwardInterval: state.skipBackwardInterval,
        queueItems: queueItems
      )
    }

    Self.log.debug(
      "makeEntry: \(nowPlaying.episodeTitle) (\(playbackStatus)), queue=\(queueItems.count)"
    )

    return NowPlayingQueueEntry(
      date: Date(),
      episodeTitle: nowPlaying.episodeTitle,
      playbackStatus: playbackStatus,
      artwork: WidgetSnapshotReader.decodeArtwork(from: nowPlaying.artworkBase64),
      skipForwardInterval: state.skipForwardInterval,
      skipBackwardInterval: state.skipBackwardInterval,
      queueItems: queueItems
    )
  }

  private func readQueue() -> [QueueEntry.QueueEntryItem] {
    guard let snapshot = WidgetSnapshotReader.readQueue() else {
      Self.log.debug("readQueue: no snapshot available, returning empty")
      return []
    }

    return QueueEntry.items(from: snapshot)
  }
}

struct NowPlayingQueueWidget: Widget {
  let kind = WidgetInfo.nowPlayingQueueKind

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: NowPlayingQueueProvider()) { entry in
      NowPlayingQueueWidgetView(entry: entry)
        .containerBackground(.fill.tertiary, for: .widget)
    }
    .configurationDisplayName("Now Playing & Up Next")
    .description("See what's playing with controls, plus your upcoming queue.")
    .supportedFamilies([.systemLarge])
  }
}
