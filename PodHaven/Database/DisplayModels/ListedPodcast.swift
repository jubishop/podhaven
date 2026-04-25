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
  }

  struct SearchMetadata: Hashable, Sendable {
    let podcast: UnsavedPodcast
    let episodeCount: Int
    let mostRecentEpisodeDate: Date?
  }

  private struct ListFields: Hashable, Sendable {
    let podcastID: Podcast.ID?
    let feedURL: FeedURL
    let iTunesID: ITunesPodcastID?
    let image: URL
    let title: String
    let subscriptionDate: Date?
    let subscribed: Bool
    let toString: String
    let searchableString: String

    init(_ podcast: ListablePodcast) {
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

    init(_ podcast: UnsavedPodcast) {
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

    init(_ searchResult: SavedSearchResultPodcast) {
      let savedPodcast = searchResult.savedPodcast
      podcastID = savedPodcast.id
      feedURL = savedPodcast.feedURL
      iTunesID = savedPodcast.iTunesID
      image = savedPodcast.image
      title = savedPodcast.title
      subscriptionDate = savedPodcast.subscriptionDate
      subscribed = savedPodcast.subscribed
      toString = savedPodcast.toString
      searchableString = searchResult.originalPodcast.searchableString
    }
  }

  let source: Source
  private let fields: ListFields

  init(saved podcast: ListablePodcast) {
    source = .saved(podcast)
    fields = ListFields(podcast)
  }

  init(unsavedSearchResult podcast: UnsavedPodcast) {
    source = .unsavedSearchResult(podcast)
    fields = ListFields(podcast)
  }

  init(savedSearchResult: SavedSearchResultPodcast) {
    source = .savedSearchResult(savedSearchResult)
    fields = ListFields(savedSearchResult)
  }

  // MARK: - Identifiable

  var id: FeedURL {
    if let searchResult = savedSearchResult {
      return searchResult.resultFeedURL
    }
    return feedURL
  }

  // MARK: - Hashable / Equatable

  func hash(into hasher: inout Hasher) {
    hasher.combine(source)
  }

  static func == (lhs: ListedPodcast, rhs: ListedPodcast) -> Bool {
    lhs.source == rhs.source
  }

  // MARK: - Stringable / Searchable

  var toString: String { fields.toString }
  var searchableString: String { fields.searchableString }

  // MARK: - PodcastListable

  var podcastID: Podcast.ID? { fields.podcastID }
  var feedURL: FeedURL { fields.feedURL }
  var iTunesID: ITunesPodcastID? { fields.iTunesID }
  var image: URL { fields.image }
  var title: String { fields.title }
  var subscriptionDate: Date? { fields.subscriptionDate }
  var subscribed: Bool { fields.subscribed }

  // MARK: - Helpers

  func getOrCreatePodcast() async throws -> Podcast {
    switch source {
    case .unsavedSearchResult(let unsavedPodcast):
      return try await unsavedPodcast.getOrCreatePodcast()
    case .savedSearchResult(let searchResult):
      return try await searchResult.getPodcast()
    case .saved(let listablePodcast):
      return try await listablePodcast.getPodcast()
    }
  }

  var listablePodcast: ListablePodcast? {
    guard case .saved(let podcast) = source else { return nil }
    return podcast
  }

  var savedSearchResult: SavedSearchResultPodcast? {
    guard case .savedSearchResult(let searchResult) = source else { return nil }
    return searchResult
  }

  var unsavedSearchResult: UnsavedPodcast? {
    guard case .unsavedSearchResult(let podcast) = source else { return nil }
    return podcast
  }

  func searchMetadata(
    episodeCount: Int,
    mostRecentEpisodeDate: Date?
  ) -> SearchMetadata? {
    switch source {
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
