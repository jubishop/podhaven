// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("of PodcastDetailViewModel filter tests", .container)
@MainActor final class FilterTests {
  @DynamicInjected(\.repo) private var repo

  // Saved podcast detail intentionally filters by row title and parent podcast
  // title only. Episode.description stays outside the slim row so detail-list
  // hydration does not widen every saved detail read; adding description search
  // needs a deliberate alternate path rather than piggybacking on the row model.
  @Test(
    "saved podcast detail intentionally filters by episode and podcast title only"
  )
  func savedDetailFilterIsIntentionallyTitleOnly() async throws {
    let descriptionToken = "rutabaga-flagstone-3471"
    let titleToken = "tangerine-dropper"
    let podcastTitleToken = "kaleidoscope-cassette"
    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(
          title: "Detail Search \(podcastTitleToken)",
          description: "Series-level blurb without any of the tokens"
        ),
        unsavedEpisodes: [
          try Create.unsavedEpisode(
            guid: "title-match",
            title: "Episode \(titleToken)",
            description: "intro with no special tokens"
          ),
          try Create.unsavedEpisode(
            guid: "description-only",
            title: "Episode With Plain Title",
            description: "intro that mentions \(descriptionToken)"
          ),
        ]
      )
    )
    let titleMatchID = savedSeries.episodes[0].id
    let descriptionOnlyID = savedSeries.episodes[1].id

    let viewModel = PodcastDetailViewModel(
      podcast: DisplayedPodcast(savedSeries.podcast)
    )
    try await PodcastDetailTestHelpers.appear(viewModel)

    try await Wait.until(
      { @MainActor in viewModel.episodeList.allEntries.count == 2 },
      { @MainActor in
        "Expected both saved episodes to load before filtering; got \(viewModel.episodeList.allEntries.count)"
      }
    )

    // Drop the debounce so each search term applies immediately.
    viewModel.episodeList.debounceDuration = .zero

    // Episode title token matches just the first row.
    viewModel.episodeList.entryFilter = titleToken
    try await Wait.until(
      { @MainActor in
        viewModel.episodeList.filteredEntries.map(\.episodeID) == [titleMatchID]
      },
      { @MainActor in
        """
        Expected episode-title token '\(titleToken)' to match the first row.
        filteredEntries: \(viewModel.episodeList.filteredEntries.map { ($0.title, $0.episodeID) })
        """
      }
    )

    // Podcast title token matches every row (both share the parent podcast).
    viewModel.episodeList.entryFilter = podcastTitleToken
    try await Wait.until(
      { @MainActor in
        viewModel.episodeList.filteredEntries.count == 2
      },
      { @MainActor in
        """
        Expected podcast-title token '\(podcastTitleToken)' to match both rows.
        filteredEntries: \(viewModel.episodeList.filteredEntries.map { ($0.title, $0.episodeID) })
        """
      }
    )

    // Description-only token must NOT match under this title-only contract.
    viewModel.episodeList.entryFilter = descriptionToken
    try await Wait.until(
      { @MainActor in viewModel.episodeList.filteredEntries.isEmpty },
      { @MainActor in
        """
        Expected description-only token '\(descriptionToken)' to filter to nothing on saved detail.
        If this test fails because filteredEntries now contains \(descriptionOnlyID), saved detail description search has been reintroduced. Make that product change explicit and keep it off the slim row model unless the query cost is acceptable.
        filteredEntries: \(viewModel.episodeList.filteredEntries.map { ($0.title, $0.episodeID) })
        """
      }
    )
  }
}
