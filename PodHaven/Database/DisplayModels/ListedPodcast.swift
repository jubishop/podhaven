// Copyright Justin Bishop, 2026

import Foundation

struct ListedPodcast:
  PodcastListable,
  Searchable,
  Hashable,
  Sendable
{
  enum Source: Hashable, Sendable {
    case saved(ListablePodcast)
    case unsavedSearchResult(UnsavedPodcast)
    case savedSearchResult(SavedSearchResultPodcast)

    func getOrCreatePodcast() async throws -> Podcast {
      switch self {
      case .saved(let podcast):
        return try await podcast.getPodcast()
      case .unsavedSearchResult(let podcast):
        return try await podcast.getOrCreatePodcast()
      case .savedSearchResult(let searchResult):
        return try await searchResult.getPodcast()
      }
    }

    var listablePodcast: ListablePodcast? {
      guard case .saved(let podcast) = self else { return nil }
      return podcast
    }

    var savedSearchResult: SavedSearchResultPodcast? {
      guard case .savedSearchResult(let searchResult) = self else { return nil }
      return searchResult
    }

    var unsavedSearchResult: UnsavedPodcast? {
      guard case .unsavedSearchResult(let podcast) = self else { return nil }
      return podcast
    }

    func searchMetadata(
      episodeCount: Int,
      mostRecentEpisodeDate: Date?
    ) -> SearchMetadata? {
      switch self {
      case .saved:
        return nil
      case .unsavedSearchResult(let podcast):
        return SearchMetadata(
          podcast: podcast,
          episodeCount: episodeCount,
          mostRecentEpisodeDate: mostRecentEpisodeDate
        )
      case .savedSearchResult(let searchResult):
        return SearchMetadata(
          podcast: searchResult.originalPodcast,
          episodeCount: searchResult.originalEpisodeCount,
          mostRecentEpisodeDate: searchResult.originalMostRecentEpisodeDate
        )
      }
    }
  }

  struct SearchMetadata: Hashable, Sendable {
    let podcast: UnsavedPodcast
    let episodeCount: Int
    let mostRecentEpisodeDate: Date?
  }

  let id: FeedURL
  let source: Source
  let podcastID: Podcast.ID?
  let feedURL: FeedURL
  let iTunesID: ITunesPodcastID?
  let image: URL
  let title: String
  let subscriptionDate: Date?
  let subscribed: Bool
  let toString: String
  let searchableString: String

  init(saved podcast: ListablePodcast) {
    id = podcast.feedURL
    source = .saved(podcast)
    podcastID = podcast.id
    feedURL = podcast.feedURL
    iTunesID = podcast.iTunesID
    image = podcast.image
    title = podcast.title
    subscriptionDate = podcast.subscriptionDate
    subscribed = podcast.subscribed
    toString = podcast.toString
    searchableString = podcast.searchableString
  }

  init(unsavedSearchResult podcast: UnsavedPodcast) {
    id = podcast.feedURL
    source = .unsavedSearchResult(podcast)
    podcastID = podcast.podcastID
    feedURL = podcast.feedURL
    iTunesID = podcast.iTunesID
    image = podcast.image
    title = podcast.title
    subscriptionDate = podcast.subscriptionDate
    subscribed = podcast.subscribed
    toString = podcast.toString
    searchableString = podcast.searchableString
  }

  init(savedSearchResult: SavedSearchResultPodcast) {
    let savedPodcast = savedSearchResult.savedPodcast
    id = savedSearchResult.resultFeedURL
    source = .savedSearchResult(savedSearchResult)
    podcastID = savedPodcast.id
    feedURL = savedPodcast.feedURL
    iTunesID = savedPodcast.iTunesID
    image = savedPodcast.image
    title = savedPodcast.title
    subscriptionDate = savedPodcast.subscriptionDate
    subscribed = savedPodcast.subscribed
    toString = savedPodcast.toString
    searchableString = savedSearchResult.originalPodcast.searchableString
  }

  // MARK: - Hashable / Equatable

  func hash(into hasher: inout Hasher) {
    hasher.combine(source)
  }

  static func == (lhs: ListedPodcast, rhs: ListedPodcast) -> Bool {
    lhs.source == rhs.source
  }

  // MARK: - Helpers

  func getOrCreatePodcast() async throws -> Podcast {
    try await source.getOrCreatePodcast()
  }

  var listablePodcast: ListablePodcast? {
    source.listablePodcast
  }

  var savedSearchResult: SavedSearchResultPodcast? {
    source.savedSearchResult
  }

  var unsavedSearchResult: UnsavedPodcast? {
    source.unsavedSearchResult
  }

  func searchMetadata(
    episodeCount: Int,
    mostRecentEpisodeDate: Date?
  ) -> SearchMetadata? {
    // The arguments only apply to unsaved search results; saved search results
    // already carry the original metadata needed to restore the search row.
    source.searchMetadata(
      episodeCount: episodeCount,
      mostRecentEpisodeDate: mostRecentEpisodeDate
    )
  }
}
