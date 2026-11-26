// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("of PodcastDetailViewModel refresh tests", .container)
@MainActor final class PodcastDetailRefreshTests {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.connectionState) private var connectionState
  @DynamicInjected(\.networkPathMonitor) private var networkPathMonitor
  @DynamicInjected(\.podcastFeedSession) private var podcastFeedSession

  private var fakeNetworkPathMonitor: FakeNetworkPathMonitor {
    networkPathMonitor as! FakeNetworkPathMonitor
  }
  private var feedSession: FakeDataFetchable { podcastFeedSession as! FakeDataFetchable }

  @Test(
    "pull-to-refresh alerts when a saved podcast's feed fails",
    arguments: [
      (URLError.Code.timedOut, FakeNetworkPath(isSatisfied: false)),
      (.cannotFindHost, FakeNetworkPath()),
    ]
  )
  func failedRefreshAlerts(code: URLError.Code, path: FakeNetworkPath) async throws {
    let feedURL = FeedURL(try #require(URL(string: "https://example.com/failed-refresh.rss")))
    let savedSeries = try await PodcastDetailTestHelpers.insertSeriesFromFeed(
      assetName: "hardfork_short",
      feedURL: feedURL
    )
    let viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(savedSeries.podcast))
    try await PodcastDetailTestHelpers.appear(viewModel)
    await feedSession.respond(to: feedURL.rawValue, error: URLError(code))
    _ = try await connectionState.currentPath()
    fakeNetworkPathMonitor.update(path)

    await viewModel.refreshSeries()

    #expect(alert.config?.title == "Error")
  }
}
