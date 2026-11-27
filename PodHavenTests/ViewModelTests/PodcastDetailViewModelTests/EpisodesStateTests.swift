// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("of PodcastDetailViewModel episodes state tests", .container)
@MainActor final class EpisodesStateTests {
  @DynamicInjected(\.connectionState) private var connectionState
  @DynamicInjected(\.podcastFeedSession) private var podcastFeedSession
  @DynamicInjected(\.repo) private var repo

  private var feedSession: FakeDataFetchable { podcastFeedSession as! FakeDataFetchable }

  @Test(
    "a first load whose feed fails while online ends in the failed state",
    arguments: [URLError.Code.timedOut, .cannotFindHost]
  )
  func failedFirstLoadEndsFailed(code: URLError.Code) async throws {
    let viewModel = try unsavedViewModel()
    await feedSession.respond(to: viewModel.podcast.feedURL.rawValue, error: URLError(code))
    #expect(try await connectionState.currentPath().isSatisfied)

    try await finishFirstLoad(viewModel)

    #expect(viewModel.episodesState == .failed(ErrorKit.message(for: URLError(code))))
  }

  @Test("pull-to-refresh after a failed first load loads the episodes")
  func refreshAfterFailedFirstLoadLoadsEpisodes() async throws {
    let viewModel = try unsavedViewModel()
    let feedURL = viewModel.podcast.feedURL.rawValue
    await feedSession.respond(to: feedURL, error: URLError(.timedOut))
    try await finishFirstLoad(viewModel)
    #expect(viewModel.episodesState == .failed(ErrorKit.message(for: URLError(.timedOut))))

    await feedSession.respond(to: feedURL, data: PreviewFeed.rss(for: feedURL, episodeCount: 2))
    await viewModel.refreshSeries()

    try await Wait.until(
      { @MainActor in viewModel.episodesState == .loaded },
      { @MainActor in "Expected the retry to load episodes, got \(viewModel.episodesState)" }
    )
    #expect(viewModel.episodeList.allEntries.count == 2)
  }

  @Test("pull-to-refresh after a failed first load finds the saved podcast its feed moved to")
  func refreshAfterFailedFirstLoadFindsMovedSavedPodcast() async throws {
    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(feedURL: FeedURL(SyntheticFeed.movedURL(0))),
        unsavedEpisodes: [try Create.unsavedEpisode()]
      )
    )
    let feedURL = SyntheticFeed.url(0)
    let viewModel = PodcastDetailViewModel(
      podcast: DisplayedPodcast(try Create.unsavedPodcast(feedURL: FeedURL(feedURL)))
    )
    await feedSession.respond(to: feedURL, error: URLError(.timedOut))
    try await finishFirstLoad(viewModel)
    #expect(viewModel.episodesState == .failed(ErrorKit.message(for: URLError(.timedOut))))

    await feedSession.respond(
      to: feedURL,
      data: SyntheticFeed.rss(index: 0, episodes: 2, moved: true)
    )
    await viewModel.refreshSeries()

    #expect(viewModel.saved)
    #expect(viewModel.podcast.feedURL == savedSeries.podcast.feedURL)
    try await Wait.until(
      { @MainActor in viewModel.episodesState == .loaded },
      { @MainActor in "Expected the saved podcast's episodes, got \(viewModel.episodesState)" }
    )
  }

  @Test("a first load of a feed with no episodes ends in the empty state")
  func emptyFeedEndsEmpty() async throws {
    let viewModel = try unsavedViewModel()
    let feedURL = viewModel.podcast.feedURL.rawValue
    await feedSession.respond(to: feedURL, data: PreviewFeed.rss(for: feedURL, episodeCount: 0))

    try await finishFirstLoad(viewModel)

    #expect(viewModel.episodesState == .empty)
    #expect(viewModel.podcast.title == "Preview Podcast")
  }

  @Test("a first load of a saved podcast with no episodes ends in the empty state")
  func emptySavedPodcastEndsEmpty() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast(), unsavedEpisodes: [])
    )
    let viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(series.podcast))

    try await finishFirstLoad(viewModel)

    #expect(viewModel.episodesState == .empty)
    #expect(viewModel.saved)
  }

  @Test("a podcast with no episodes has no latest-episode date while loading or once empty")
  func noEpisodesHaveNoMostRecentEpisodeDate() async throws {
    let viewModel = try unsavedViewModel()
    let feedURL = viewModel.podcast.feedURL.rawValue
    await feedSession.respond(to: feedURL, data: PreviewFeed.rss(for: feedURL, episodeCount: 0))
    #expect(viewModel.episodesState == .loading)
    #expect(viewModel.mostRecentEpisodeDate == nil)

    try await finishFirstLoad(viewModel)

    #expect(viewModel.episodesState == .empty)
    #expect(viewModel.mostRecentEpisodeDate == nil)
  }

  // MARK: - Helpers

  private func unsavedViewModel() throws -> PodcastDetailViewModel {
    PodcastDetailViewModel(podcast: DisplayedPodcast(try Create.unsavedPodcast()))
  }

  private func finishFirstLoad(_ viewModel: PodcastDetailViewModel) async throws {
    viewModel.appear()
    try await Wait.until(
      { @MainActor in viewModel.episodesState != .loading },
      { @MainActor in
        "Expected the first load to end, still loading \(viewModel.podcast.toString)"
      }
    )
  }
}
