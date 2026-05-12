// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of PodcastDetailViewModel observation tests", .container)
@MainActor final class ObservationTests {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.appDB) private var appDB
  @DynamicInjected(\.podcastFeedSession) private var podcastFeedSession
  @DynamicInjected(\.repo) private var repo

  private var feedSession: FakeDataFetchable { podcastFeedSession as! FakeDataFetchable }

  @Test("deleting an observed saved series reparses the feed into unsaved detail")
  func observedDeletionReparsesFeed() async throws {
    let feedURL = FeedURL(URL(string: "https://feeds.simplecast.com/l2i9YnTd")!)
    let savedSeries = try await PodcastDetailTestHelpers.insertSeriesFromFeed(
      assetName: "hardfork_short",
      feedURL: feedURL
    )
    let viewModel = PodcastDetailViewModel(
      podcast: DisplayedPodcast(savedSeries.podcast)
    )

    try await viewModel.performAppear()
    await feedSession.respond(
      to: feedURL.rawValue,
      data: PreviewBundle.loadAsset(named: "hardfork_short", in: .FeedRSS)
    )

    _ = try await repo.deletePodcast(savedSeries.id)

    try await Wait.until(
      { @MainActor in
        viewModel.saved == false
          && viewModel.podcast.loaded?.source.unsaved != nil
          && viewModel.episodeList.allEntries.isEmpty == false
      },
      { @MainActor in
        """
        Expected deleted saved podcast to reparse back into unsaved detail.
        saved: \(viewModel.saved)
        podcast: \(viewModel.podcast.toString)
        episode count: \(viewModel.episodeList.allEntries.count)
        """
      }
    )
  }

  @Test("deleting an observed saved series alerts when feed recovery fails")
  func observedDeletionFailureAlerts() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/deleted-podcast.rss")!)
    let feedData = PreviewBundle.loadAsset(named: "hardfork_short", in: .FeedRSS)
    await feedSession.respond(to: feedURL.rawValue, data: feedData)
    let podcastFeed = try await PodcastFeed.parse(feedData, from: feedURL)
    let savedSeries = try await repo.insertSeries(podcastFeed.toUnsavedSeries())
    let displayedPodcast = DisplayedPodcast(savedSeries.podcast)

    let viewModel = PodcastDetailViewModel(podcast: displayedPodcast)

    try await viewModel.performAppear()

    await feedSession.respond(to: feedURL.rawValue, error: URLError(.cannotLoadFromNetwork))
    _ = try await repo.deletePodcast(savedSeries.id)

    try await Wait.until(
      { @MainActor [self] in alert.config != nil },
      { @MainActor [self] in
        """
        Expected failed feed recovery after deletion to alert.
        alert presented: \(alert.config != nil)
        """
      }
    )
  }

  @Test("podcastSeries observation prunes episodes that have been removed from the DB")
  func podcastSeriesObservationPrunesRemovedEpisodes() async throws {
    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(title: "Prune Test"),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: "keep-1"),
          try Create.unsavedEpisode(guid: "remove-me"),
          try Create.unsavedEpisode(guid: "keep-2"),
        ]
      )
    )
    let removedID = savedSeries.episodes[1].id

    let viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(savedSeries.podcast))
    try await viewModel.performAppear()
    try await Wait.until(
      { @MainActor in viewModel.episodeList.allEntries.count == 3 },
      { @MainActor in
        "Expected 3 entries after initial observation; got \(viewModel.episodeList.allEntries.count)"
      }
    )

    _ = try await appDB.db.write { db in
      try Episode.deleteOne(db, key: removedID)
    }

    try await Wait.until(
      { @MainActor in
        viewModel.episodeList.allEntries.count == 2
          && viewModel.episodeList.allEntries.allSatisfy { $0.episodeID != removedID }
      },
      { @MainActor in
        """
        Expected the removed episode to be pruned from allEntries.
        count: \(viewModel.episodeList.allEntries.count)
        episodeIDs: \(viewModel.episodeList.allEntries.map(\.episodeID))
        """
      }
    )
  }
}
