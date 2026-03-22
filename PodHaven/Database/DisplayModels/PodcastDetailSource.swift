// Copyright Justin Bishop, 2026

import Foundation
import IdentifiedCollections

struct PodcastDetailPresentation: Sendable {
  let podcast: DisplayedPodcast
  let episodes: IdentifiedArrayOf<DisplayedEpisode>
}

struct PodcastDetailSource: Sendable {
  let initialPresentation: PodcastDetailPresentation

  init(podcast: DisplayedPodcast) {
    initialPresentation = PodcastDetailPresentation(
      podcast: podcast,
      episodes: []
    )
  }

  init(listedPodcast: ListedPodcast) {
    initialPresentation = PodcastDetailPresentation(
      podcast: DisplayedPodcast(PodcastDetailSnapshot(listedPodcast)),
      episodes: []
    )
  }

  init(unsavedPodcastSeries: UnsavedPodcastSeries) {
    initialPresentation = PodcastDetailPresentation(
      podcast: DisplayedPodcast(unsavedPodcastSeries.unsavedPodcast),
      episodes: IdentifiedArrayOf(
        uniqueElements: unsavedPodcastSeries.unsavedEpisodes.map {
          DisplayedEpisode(
            UnsavedPodcastEpisode(
              unsavedPodcast: unsavedPodcastSeries.unsavedPodcast,
              unsavedEpisode: $0
            )
          )
        }
      )
    )
  }

  func savedSeries(
    using repo: any Databasing,
    currentPodcast: DisplayedPodcast
  ) async throws -> PodcastSeries? {
    try await repo.podcastSeries(
      currentPodcast.feedURL,
      iTunesID: currentPodcast.iTunesID
    )
  }

  func parsedFeedPresentation(currentPodcast: DisplayedPodcast) async throws
    -> PodcastDetailPresentation
  {
    let podcastFeed = try await PodcastFeed.parse(currentPodcast.feedURL)
    let unsavedPodcast = try podcastFeed.toUnsavedPodcast(iTunesID: currentPodcast.iTunesID)
    return PodcastDetailPresentation(
      podcast: DisplayedPodcast(unsavedPodcast),
      episodes: IdentifiedArray(
        uniqueElements: podcastFeed.toUnsavedEpisodes()
          .map {
            DisplayedEpisode(
              UnsavedPodcastEpisode(
                unsavedPodcast: unsavedPodcast,
                unsavedEpisode: $0
              )
            )
          },
        id: \.mediaGUID
      )
    )
  }
}
