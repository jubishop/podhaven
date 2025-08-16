// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging

@Observable @MainActor class SearchedPodcastGridItemViewModel {
  @ObservationIgnored @DynamicInjected(\.repo) private var repo

  private static let log = Log.as(LogSubsystem.SearchView.trending)

  let unsavedPodcast: UnsavedPodcast

  init(unsavedPodcast: UnsavedPodcast) {
    self.unsavedPodcast = unsavedPodcast
  }

  func subscribe() {
    Task { [weak self] in
      guard let self else { return }
      do {
        // Fetch the podcast feed to get real episodes
        let podcastFeed = try await PodcastFeed.parse(unsavedPodcast.feedURL)

        // Create the podcast with subscription date
        var unsavedPodcast = try podcastFeed.toUnsavedPodcast()
        unsavedPodcast.subscriptionDate = Date()
        unsavedPodcast.lastUpdate = Date()

        // Get the episodes from the feed
        let unsavedEpisodes = podcastFeed.toEpisodeArray(merging: nil).elements

        // Insert the podcast series with real episodes
        let newPodcastSeries = try await repo.insertSeries(
          unsavedPodcast,
          unsavedEpisodes: unsavedEpisodes
        )

        Self.log.info("Subscribed to podcast: \(newPodcastSeries.podcast.title)")
      } catch {
        Self.log.error(error)
      }
    }
  }
}
