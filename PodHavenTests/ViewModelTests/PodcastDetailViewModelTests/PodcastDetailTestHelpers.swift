// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

enum PodcastDetailTestHelpers {
  private static var feedSession: FakeDataFetchable {
    Container.shared.podcastFeedSession() as! FakeDataFetchable
  }
  private static var observatory: any Observing { Container.shared.observatory() }
  private static var repo: any Databasing { Container.shared.repo() }

  @MainActor
  static func appear(_ viewModel: PodcastDetailViewModel) async throws {
    viewModel.appear()
    try await Wait.until(
      { @MainActor in
        guard viewModel.isOnScreen else { return false }
        guard viewModel.appearTask == nil else { return false }
        if viewModel.saved {
          return true
        }
        return !viewModel.episodeList.allEntries.isEmpty || viewModel.podcast.loaded != nil
      },
      { @MainActor in
        """
        Expected appear to finish with a hydrated projection.
        isOnScreen: \(viewModel.isOnScreen)
        appearTask: \(String(describing: viewModel.appearTask))
        saved: \(viewModel.saved)
        entries: \(viewModel.episodeList.allEntries.count)
        podcast: \(viewModel.podcast.toString)
        """
      }
    )
  }

  static func insertSeriesFromFeed(assetName: String, feedURL: FeedURL) async throws
    -> PodcastSeries
  {
    let data = PreviewBundle.loadAsset(named: assetName, in: .FeedRSS)
    await feedSession.respond(to: feedURL.rawValue, data: data)
    let podcastFeed = try await PodcastFeed.parse(data, from: feedURL)
    return try await repo.insertSeries(podcastFeed.toUnsavedSeries())
  }

  static func fetchListablePodcast(_ podcastID: Podcast.ID) async throws -> ListablePodcast {
    let results: [PodcastWithEpisodeMetadata<ListablePodcast>] =
      try await observatory.listablePodcastsWithEpisodeMetadata(
        { $0.filter(Podcast.Columns.id == podcastID) },
        limit: 1
      )
      .get()

    return try #require(results.first?.podcast)
  }

  static func searchResultFeedURL() throws -> FeedURL {
    FeedURL(try #require(URL(string: "https://example.com/search-result.rss")))
  }

  @MainActor
  static func select(_ viewModel: PodcastDetailViewModel, episodeIDs: [Episode.ID]) throws {
    for episodeID in episodeIDs {
      let entry = try #require(viewModel.episodeList.allEntries.first { $0.episodeID == episodeID })
      viewModel.episodeList.isSelected[entry.id] = true
    }
  }
}
