// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("of PodcastDetailViewModel initial state tests", .container)
@MainActor final class InitialStateTests {
  @DynamicInjected(\.repo) private var repo

  @Test("shared unsaved podcast series is presented before appear")
  func unsavedPodcastSeriesIsPresentedBeforeAppear() async throws {
    let unsavedSeries = UnsavedPodcastSeries(
      unsavedPodcast: try Create.unsavedPodcast(
        feedURL: FeedURL(URL(string: "https://example.com/immediate-series.rss")!),
        title: "Immediate Series"
      ),
      unsavedEpisodes: [
        try Create.unsavedEpisode(
          guid: "immediate-1",
          title: "Immediate Episode 1",
          pubDate: Date(timeIntervalSince1970: 200)
        ),
        try Create.unsavedEpisode(
          guid: "immediate-2",
          title: "Immediate Episode 2",
          pubDate: Date(timeIntervalSince1970: 100)
        ),
      ]
    )

    let viewModel = PodcastDetailViewModel(unsavedPodcastSeries: unsavedSeries)

    #expect(viewModel.saved == false)
    #expect(viewModel.podcast.title == unsavedSeries.unsavedPodcast.title)
    try await Wait.until(
      { @MainActor in
        viewModel.episodeList.allEntries.map(\.title) == [
          "Immediate Episode 1",
          "Immediate Episode 2",
        ]
      },
      { @MainActor in
        """
        Expected shared unsaved podcast series episodes to be presented before appear.
        Actual titles: \(viewModel.episodeList.allEntries.map(\.title))
        """
      }
    )
  }

  @Test("viewModel.saved derives from the init seed shape immediately, before performAppear")
  func savedDerivesFromInitShapeImmediately() async throws {
    // .displayedPodcast(.saved): a saved Podcast jumps straight to .saved
    // (PodcastSeriesDetail with empty episodes/tags) — `saved` is true even
    // before performAppear hydrates the series.
    let savedPodcast = try await Create.podcast(title: "Already Saved")
    let savedDisplayedVM = PodcastDetailViewModel(podcast: DisplayedPodcast(savedPodcast))
    #expect(savedDisplayedVM.saved)

    // .displayedPodcast(.unsaved): unsaved arm, saved=false.
    let unsavedDisplayedVM = PodcastDetailViewModel(
      podcast: DisplayedPodcast(try Create.unsavedPodcast(title: "Unsaved Displayed"))
    )
    #expect(unsavedDisplayedVM.saved == false)

    // .listedPodcast(.saved): initial-bridge state, saved=false until
    // performAppear hydrates the saved series.
    let listedSavedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast(title: "Listed Saved"))
    )
    let listablePodcast = try await PodcastDetailTestHelpers.fetchListablePodcast(
      listedSavedSeries.id
    )
    let listedSavedVM = PodcastDetailViewModel(listedPodcast: ListedPodcast(saved: listablePodcast))
    #expect(listedSavedVM.saved == false)

    // .listedPodcast(.unsavedSearchResult): promoted to .unsaved, saved=false.
    let listedUnsavedSearchVM = PodcastDetailViewModel(
      listedPodcast: ListedPodcast(
        unsavedSearchResult: try Create.unsavedPodcast(title: "Search Hit")
      )
    )
    #expect(listedUnsavedSearchVM.saved == false)

    // .unsavedPodcastSeries: unsaved arm, saved=false.
    let seriesVM = PodcastDetailViewModel(
      unsavedPodcastSeries: UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(title: "Bulk Unsaved")
      )
    )
    #expect(seriesVM.saved == false)
  }
}
