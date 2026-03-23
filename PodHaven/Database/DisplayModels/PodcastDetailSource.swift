// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import IdentifiedCollections

struct PodcastDetailPresentation: Sendable {
  let podcast: DisplayedPodcast
  let episodes: IdentifiedArrayOf<DisplayedEpisode>
}

struct PodcastDetailSource: Sendable {
  @DynamicInjected(\.repo) private var repo

  let initialPresentation: PodcastDetailPresentation
  let requiresHydratedPresentation: Bool

  init(podcast: DisplayedPodcast) {
    initialPresentation = PodcastDetailPresentation(
      podcast: podcast,
      episodes: []
    )
    requiresHydratedPresentation = false
  }

  init(listedPodcast: ListedPodcast) {
    initialPresentation = PodcastDetailPresentation(
      podcast: DisplayedPodcast(PodcastDetailSnapshot(listedPodcast)),
      episodes: []
    )
    requiresHydratedPresentation = listedPodcast.getListablePodcast() != nil
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
    requiresHydratedPresentation = false
  }

  func savedSeries(currentPodcast: DisplayedPodcast) async throws -> PodcastSeries? {
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
