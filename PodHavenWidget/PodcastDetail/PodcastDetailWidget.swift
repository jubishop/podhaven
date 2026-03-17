// Copyright Justin Bishop, 2026

import AppIntents
import Logging
import SwiftUI
import WidgetKit

struct PodcastDetailProvider: AppIntentTimelineProvider {
  private static let log = Log.as(LogSubsystem.Widget.podcastDetail)

  private static let podcastDetailBaseURL = WidgetInfo.podcastDetailBaseURL

  func placeholder(in context: Context) -> PodcastDetailEntry {
    .preview
  }

  func snapshot(for configuration: SelectPodcastIntent, in context: Context) async
    -> PodcastDetailEntry
  {
    Self.log.debug(
      "PodcastDetail snapshot called (isPreview=\(context.isPreview))"
    )
    return makeEntry(for: configuration)
  }

  func timeline(for configuration: SelectPodcastIntent, in context: Context) async -> Timeline<
    PodcastDetailEntry
  > {
    Self.log.debug("PodcastDetail timeline called (family=\(context.family))")
    let entry = makeEntry(for: configuration)
    return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600)))
  }

  private func makeEntry(for configuration: SelectPodcastIntent) -> PodcastDetailEntry {
    guard let selectedPodcast = configuration.podcast else {
      Self.log.debug("PodcastDetail makeEntry: no podcast selected")
      return .empty
    }

    guard let snapshot = WidgetSnapshotReader.readPodcastDetail() else {
      Self.log.warning("PodcastDetail makeEntry: no snapshot available")
      return .empty
    }

    guard
      let podcast = snapshot.subscribedPodcasts.first(where: {
        $0.feedURLString == selectedPodcast.id
      })
    else {
      Self.log.warning(
        "PodcastDetail makeEntry: podcast \(selectedPodcast.id) not found in snapshot"
      )
      return .empty
    }

    let recentEpisodes = podcast.recentEpisodes ?? []

    Self.log.debug(
      "PodcastDetail makeEntry: \(podcast.title) with \(recentEpisodes.count) episodes"
    )

    let artworkDict = WidgetSnapshotReader.loadArtwork()

    let episodes = recentEpisodes.map { episode in
      WidgetEpisodeList.Episode(
        id: episode.episodeID,
        title: episode.episodeTitle,
        pubDateFormatted: Date(timeIntervalSince1970: episode.pubDateTimestamp).usShort,
        durationFormatted: episode.durationSeconds.compactReadableFormat,
        artwork: WidgetSnapshotReader.decodeArtwork(
          forKey: episode.artworkURL,
          from: artworkDict
        ),
        deepLinkURL: Self.podcastDetailBaseURL.appending(
          path: "episode/\(episode.episodeID)"
        )
      )
    }

    let lastUpdated =
      recentEpisodes
      .map { Date(timeIntervalSince1970: $0.pubDateTimestamp) }
      .max()?
      .usShort ?? ""

    var podcastURLComponents = URLComponents(string: "podhaven://widget/podcast-detail")!
    podcastURLComponents.queryItems = [URLQueryItem(name: "feedURL", value: podcast.feedURLString)]
    let podcastURL = podcastURLComponents.url

    return PodcastDetailEntry(
      date: Date(),
      podcastTitle: podcast.title,
      lastUpdatedFormatted: lastUpdated,
      podcastArtwork: WidgetSnapshotReader.decodeArtwork(
        forKey: podcast.artworkURL,
        from: artworkDict
      ),
      podcastURL: podcastURL,
      episodes: episodes,
      isPlaceholder: false
    )
  }
}

struct PodcastDetailWidget: Widget {
  let kind = WidgetInfo.podcastDetailKind

  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: kind,
      intent: SelectPodcastIntent.self,
      provider: PodcastDetailProvider()
    ) { entry in
      PodcastDetailWidgetView(entry: entry)
        .widgetURL(entry.podcastURL)
        .containerBackground(.fill.tertiary, for: .widget)
    }
    .configurationDisplayName("Podcast Detail")
    .description("See recent episodes from a podcast.")
    .supportedFamilies([.systemLarge])
  }
}
