// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

// Saved detail filters via FTS (title, description, parent-podcast text);
// unsaved previews match their in-memory searchableString.
@Suite("of PodcastDetailViewModel filter tests", .container)
@MainActor final class FilterTests {
  @DynamicInjected(\.repo) private var repo

  private static let podcastTitleToken = "kaleidoscope"
  private static let episodeTitleToken = "tangerine"
  private static let descriptionToken = "rutabaga"

  private func makeSavedSeries() async throws -> PodcastSeries {
    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(
          title: "Detail Search \(Self.podcastTitleToken)",
          description: "Series blurb without episode-specific tokens"
        ),
        unsavedEpisodes: [
          try Create.unsavedEpisode(
            guid: "title-match",
            title: "Episode \(Self.episodeTitleToken)",
            description: "intro with no special tokens"
          ),
          try Create.unsavedEpisode(
            guid: "description-only",
            title: "Episode With Plain Title",
            description: "intro that mentions \(Self.descriptionToken)"
          ),
        ]
      )
    )
  }

  @MainActor
  private func appearedViewModel(
    for series: PodcastSeries
  ) async throws -> PodcastDetailViewModel {
    let viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(series.podcast))
    try await PodcastDetailTestHelpers.appear(viewModel)
    try await Wait.until(
      { @MainActor in viewModel.episodeList.allEntries.count == 2 },
      { @MainActor in
        "Expected both saved episodes to load before filtering; got \(viewModel.episodeList.allEntries.count)"
      }
    )
    // Drop the debounce so each query applies without waiting on the timer.
    viewModel.filterDebouncer.debounceDuration = .zero
    return viewModel
  }

  // Regression: a description-only word matched nothing before the FTS switch.
  @Test("saved detail filter matches a word only in the episode description")
  func savedDetailFilterMatchesDescriptionViaFTS() async throws {
    let series = try await makeSavedSeries()
    let descriptionOnlyID = series.episodes[1].id
    let viewModel = try await appearedViewModel(for: series)

    viewModel.filterDebouncer.currentValue = Self.descriptionToken

    try await Wait.until(
      { @MainActor in
        viewModel.episodeList.filteredEntries.map(\.episodeID) == [descriptionOnlyID]
      },
      { @MainActor in
        """
        Expected description token '\(Self.descriptionToken)' to match the row whose \
        description mentions it via FTS.
        filteredEntries: \(viewModel.episodeList.filteredEntries.map { ($0.title, $0.episodeID) })
        """
      }
    )
  }

  @Test("saved detail filter matches a word in the episode title")
  func savedDetailFilterMatchesEpisodeTitle() async throws {
    let series = try await makeSavedSeries()
    let titleMatchID = series.episodes[0].id
    let viewModel = try await appearedViewModel(for: series)

    viewModel.filterDebouncer.currentValue = Self.episodeTitleToken

    try await Wait.until(
      { @MainActor in
        viewModel.episodeList.filteredEntries.map(\.episodeID) == [titleMatchID]
      },
      { @MainActor in
        """
        Expected episode-title token '\(Self.episodeTitleToken)' to match only the first row.
        filteredEntries: \(viewModel.episodeList.filteredEntries.map { ($0.title, $0.episodeID) })
        """
      }
    )
  }

  @Test("saved detail filter matches the parent podcast title across all episodes")
  func savedDetailFilterMatchesParentPodcastTitle() async throws {
    let series = try await makeSavedSeries()
    let viewModel = try await appearedViewModel(for: series)

    viewModel.filterDebouncer.currentValue = Self.podcastTitleToken

    try await Wait.until(
      { @MainActor in viewModel.episodeList.filteredEntries.count == 2 },
      { @MainActor in
        """
        Expected podcast-title token '\(Self.podcastTitleToken)' to match both rows.
        filteredEntries: \(viewModel.episodeList.filteredEntries.map { ($0.title, $0.episodeID) })
        """
      }
    )
  }

  @Test("saved detail filter restores every episode when the query is cleared")
  func savedDetailFilterClearingRestoresAllEpisodes() async throws {
    let series = try await makeSavedSeries()
    let viewModel = try await appearedViewModel(for: series)

    viewModel.filterDebouncer.currentValue = Self.episodeTitleToken
    try await Wait.until(
      { @MainActor in viewModel.episodeList.filteredEntries.count == 1 },
      { @MainActor in
        "Expected a single match before clearing; got \(viewModel.episodeList.filteredEntries.count)"
      }
    )

    viewModel.filterDebouncer.currentValue = ""
    try await Wait.until(
      { @MainActor in viewModel.episodeList.filteredEntries.count == 2 },
      { @MainActor in
        "Expected clearing the filter to restore both rows; got \(viewModel.episodeList.filteredEntries.count)"
      }
    )
  }

  @Test("unsaved detail preview still matches a word in the episode description")
  func unsavedDetailFilterMatchesDescription() async throws {
    let viewModel = PodcastDetailViewModel(
      unsavedPodcastSeries: UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(
          title: "Preview \(Self.podcastTitleToken)",
          description: "Preview blurb without episode-specific tokens"
        ),
        unsavedEpisodes: [
          try Create.unsavedEpisode(
            guid: "u-title",
            title: "Episode \(Self.episodeTitleToken)",
            description: "intro with no special tokens"
          ),
          try Create.unsavedEpisode(
            guid: "u-description",
            title: "Episode With Plain Title",
            description: "intro that mentions \(Self.descriptionToken)"
          ),
        ]
      )
    )
    try await PodcastDetailTestHelpers.appear(viewModel)
    try await Wait.until(
      { @MainActor in viewModel.episodeList.allEntries.count == 2 },
      { @MainActor in
        "Expected both preview episodes to load; got \(viewModel.episodeList.allEntries.count)"
      }
    )
    viewModel.filterDebouncer.debounceDuration = .zero

    viewModel.filterDebouncer.currentValue = Self.descriptionToken

    try await Wait.until(
      { @MainActor in
        viewModel.episodeList.filteredEntries.map(\.title) == ["Episode With Plain Title"]
      },
      { @MainActor in
        """
        Expected description token '\(Self.descriptionToken)' to match the preview row that \
        mentions it.
        filteredEntries: \(viewModel.episodeList.filteredEntries.map(\.title))
        """
      }
    )
  }
}
