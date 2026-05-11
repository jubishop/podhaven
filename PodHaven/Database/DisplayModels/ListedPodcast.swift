// Copyright Justin Bishop, 2026

import Foundation

struct ListedPodcast:
  PodcastDisplayable,
  Searchable,
  Hashable,
  Sendable
{
  enum Source: Hashable, Sendable {
    case saved(ListablePodcast)
    case unsavedSearchResult(UnsavedPodcast)
    case savedSearchResult(SavedSearchResultPodcast)

    // Canonical podcast used to forward most list fields. For savedSearchResult
    // this is the saved podcast — not the bridged search row.
    var canonicalPodcast: any PodcastListable {
      switch self {
      case .saved(let podcast): return podcast
      case .unsavedSearchResult(let podcast): return podcast
      case .savedSearchResult(let result): return result.savedPodcast
      }
    }

    // Canonical identity for the underlying podcast. Matches `feedURL` —
    // the saved podcast's feedURL for `.savedSearchResult`, the row's own
    // feedURL for the other cases. Use this when you want "which podcast is
    // this?" semantics.
    var id: FeedURL { canonicalPodcast.feedURL }

    // Row-slot identity used by `IdentifiedArray` to keep a search result
    // pinned to its display slot. For `.savedSearchResult` this is the search
    // row's feedURL, which can differ from the canonical podcast's feedURL
    // once the row has been bridged to a saved podcast.
    var slotID: FeedURL {
      if case .savedSearchResult(let result) = self { return result.resultFeedURL }
      return canonicalPodcast.feedURL
    }

    var podcastID: Podcast.ID? { canonicalPodcast.podcastID }
    var feedURL: FeedURL { canonicalPodcast.feedURL }
    var iTunesID: ITunesPodcastID? { canonicalPodcast.iTunesID }
    var image: URL { canonicalPodcast.image }
    var title: String { canonicalPodcast.title }
    var subscriptionDate: Date? { canonicalPodcast.subscriptionDate }
    var toString: String { canonicalPodcast.toString }

    // Header fields beyond `PodcastListable`. The .saved arm has no list-row
    // source for these — surface the same placeholder the detail view already
    // showed pre-hydration; .savedSearchResult forwards the original search
    // metadata, .unsavedSearchResult its own.
    var description: String {
      switch self {
      case .saved: return ""
      case .unsavedSearchResult(let podcast): return podcast.description
      case .savedSearchResult(let result): return result.originalPodcast.description
      }
    }

    var link: URL? {
      switch self {
      case .saved: return nil
      case .unsavedSearchResult(let podcast): return podcast.link
      case .savedSearchResult(let result): return result.originalPodcast.link
      }
    }

    // For savedSearchResult, search uses the original (unsaved) search description,
    // not the saved podcast's searchableString.
    var searchableString: String {
      if case .savedSearchResult(let result) = self {
        return result.originalPodcast.searchableString
      }
      return canonicalPodcast.searchableString
    }

    func getOrCreatePodcast() async throws -> Podcast {
      switch self {
      case .saved(let podcast): return try await podcast.getPodcast()
      case .unsavedSearchResult(let podcast): return try await podcast.getOrCreatePodcast()
      case .savedSearchResult(let result): return try await result.getPodcast()
      }
    }

    var listablePodcast: ListablePodcast? {
      guard case .saved(let podcast) = self else { return nil }
      return podcast
    }

    var savedSearchResult: SavedSearchResultPodcast? {
      guard case .savedSearchResult(let result) = self else { return nil }
      return result
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
      case .saved: return nil
      case .unsavedSearchResult(let podcast):
        return SearchMetadata(
          podcast: podcast,
          episodeCount: episodeCount,
          mostRecentEpisodeDate: mostRecentEpisodeDate
        )
      case .savedSearchResult(let result):
        return SearchMetadata(
          podcast: result.originalPodcast,
          episodeCount: result.originalEpisodeCount,
          mostRecentEpisodeDate: result.originalMostRecentEpisodeDate
        )
      }
    }
  }

  struct SearchMetadata: Hashable, Sendable {
    let podcast: UnsavedPodcast
    let episodeCount: Int
    let mostRecentEpisodeDate: Date?
  }

  let source: Source

  init(saved podcast: ListablePodcast) { source = .saved(podcast) }
  init(unsavedSearchResult podcast: UnsavedPodcast) { source = .unsavedSearchResult(podcast) }
  init(savedSearchResult: SavedSearchResultPodcast) {
    source = .savedSearchResult(savedSearchResult)
  }

  // MARK: - PodcastListable

  var id: FeedURL { source.id }
  var slotID: FeedURL { source.slotID }
  var podcastID: Podcast.ID? { source.podcastID }
  var feedURL: FeedURL { source.feedURL }
  var iTunesID: ITunesPodcastID? { source.iTunesID }
  var image: URL { source.image }
  var title: String { source.title }
  var subscriptionDate: Date? { source.subscriptionDate }
  var toString: String { source.toString }
  var searchableString: String { source.searchableString }

  // MARK: - PodcastDisplayable

  var description: String { source.description }
  var link: URL? { source.link }

  // MARK: - Hashable / Equatable

  func hash(into hasher: inout Hasher) { hasher.combine(source) }
  static func == (lhs: ListedPodcast, rhs: ListedPodcast) -> Bool { lhs.source == rhs.source }

  // MARK: - Helpers

  func getOrCreatePodcast() async throws -> Podcast { try await source.getOrCreatePodcast() }
  var listablePodcast: ListablePodcast? { source.listablePodcast }
  var savedSearchResult: SavedSearchResultPodcast? { source.savedSearchResult }
  var unsavedSearchResult: UnsavedPodcast? { source.unsavedSearchResult }

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
