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

  enum RefreshedPodcast: CaseIterable {
    case saved
    case unsaved
  }

  @Test(
    "pull-to-refresh alerts when a saved podcast's feed fails",
    arguments: [
      (URLError.Code.timedOut, FakeNetworkPath(isSatisfied: false)),
      (.cannotFindHost, FakeNetworkPath()),
    ]
  )
  func failedRefreshAlerts(code: URLError.Code, path: FakeNetworkPath) async throws {
    let viewModel = try await appearedViewModel(.saved)
    await feedSession.respond(to: viewModel.podcast.feedURL.rawValue, error: URLError(code))
    _ = try await connectionState.currentPath()
    fakeNetworkPathMonitor.update(path)

    await viewModel.refreshSeries()

    #expect(alert.config?.title == "Error")
  }

  @Test(
    "pull-to-refresh alerts when the feed times out while online",
    arguments: RefreshedPodcast.allCases
  )
  func onlineTimeoutAlerts(podcast: RefreshedPodcast) async throws {
    let viewModel = try await appearedViewModel(podcast)
    await feedSession.respond(to: viewModel.podcast.feedURL.rawValue, error: URLError(.timedOut))
    #expect(try await connectionState.currentPath().isSatisfied)

    await viewModel.refreshSeries()

    #expect(alert.config?.title == "Error")
  }

  @Test(
    "pull-to-refresh raises no alert when the refresh is cancelled",
    arguments: RefreshedPodcast.allCases
  )
  func cancelledRefreshDoesNotAlert(podcast: RefreshedPodcast) async throws {
    let viewModel = try await appearedViewModel(podcast)
    let (started, finish) = await feedSession.releaseWaitRespond(
      to: viewModel.podcast.feedURL.rawValue
    )
    defer { finish.signal() }
    let refresh = Task { await viewModel.refreshSeries() }
    try await started.waitUnlessCancelled()

    refresh.cancel()
    await refresh.value

    #expect(alert.config == nil)
  }

  @Test(
    "pull-to-refresh raises no alert when the feed fetch is cancelled",
    arguments: RefreshedPodcast.allCases
  )
  func cancelledFetchDoesNotAlert(podcast: RefreshedPodcast) async throws {
    let viewModel = try await appearedViewModel(podcast)
    await feedSession.respond(to: viewModel.podcast.feedURL.rawValue, error: URLError(.cancelled))

    await viewModel.refreshSeries()

    #expect(alert.config == nil)
  }

  // MARK: - Helpers

  // hardfork_short names a new feed URL, which refreshes then fetch.
  private func appearedViewModel(_ podcast: RefreshedPodcast) async throws
    -> PodcastDetailViewModel
  {
    let feedURL = FeedURL(try #require(URL(string: "https://example.com/refresh.rss")))
    let viewModel: PodcastDetailViewModel
    switch podcast {
    case .saved:
      let savedSeries = try await PodcastDetailTestHelpers.insertSeriesFromFeed(
        assetName: "hardfork_short",
        feedURL: feedURL
      )
      viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(savedSeries.podcast))
    case .unsaved:
      let data = PreviewBundle.loadAsset(named: "hardfork_short", in: .FeedRSS)
      await feedSession.respond(to: feedURL.rawValue, data: data)
      viewModel = PodcastDetailViewModel(
        podcast: DisplayedPodcast(try Create.unsavedPodcast(feedURL: feedURL))
      )
    }
    try await PodcastDetailTestHelpers.appear(viewModel)
    #expect(viewModel.saved == (podcast == .saved))
    return viewModel
  }
}
