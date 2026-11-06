// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import IdentifiedCollections
import Testing

@testable import PodHaven

@Suite("of SearchViewModel selection tests", .container)
@MainActor final class SearchViewModelSelectionTests {
  @DynamicInjected(\.repo) private var repo

  private var feedSession: FakeDataFetchable {
    Container.shared.podcastFeedSession() as! FakeDataFetchable
  }

  @Test("subscribeSelectedPodcasts saves unsaved results and subscribes them with one count line")
  func subscribeSelectedSavesAndLogsSummary() async throws {
    let podcastCount = 5
    await SyntheticFeed.respond(feedSession, episodes: 1)

    let viewModel = SearchViewModel()
    viewModel.podcastList.allEntries = IdentifiedArray(
      uniqueElements: try (0..<podcastCount)
        .map { index in
          PodcastWithEpisodeMetadata(
            podcast: ListedPodcast(
              unsavedSearchResult: try Create.unsavedPodcast(
                feedURL: FeedURL(SyntheticFeed.url(index)),
                title: SyntheticFeed.title(index)
              )
            ),
            episodeCount: 1,
            mostRecentEpisodeDate: nil
          )
        }
    )
    try await Wait.until(
      { @MainActor in viewModel.podcastList.filteredEntries.count == podcastCount },
      { @MainActor in
        "filteredEntries didn't populate; got \(viewModel.podcastList.filteredEntries.count)"
      }
    )
    viewModel.podcastList.selectAllEntries()

    let captured = try await LogCapture.withSink { sink in
      viewModel.subscribeSelectedPodcasts()
      try await Wait.until(
        {
          sink.captured()
            .contains { $0.message.contains("subscribed \(podcastCount) of \(podcastCount)") }
        },
        { "no subscribe summary among \(sink.captured().map(\.message))" }
      )
      return sink.captured()
    }

    let podcasts = try await repo.allPodcasts(AppDB.noOp)
    #expect(podcasts.count == podcastCount)
    #expect(podcasts.allSatisfy { $0.subscribed })
    let perPodcastLines = captured.filter { $0.message.contains("to: subscribed") }
    #expect(perPodcastLines.isEmpty, "\(perPodcastLines.map(\.message))")
  }
}
