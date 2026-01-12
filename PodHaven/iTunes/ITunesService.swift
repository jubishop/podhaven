// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import IdentifiedCollections

extension Container {
  var iTunesServiceSession: Factory<any DataFetchable> {
    Factory(self) {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.allowsCellularAccess = true
      configuration.waitsForConnectivity = true
      let timeout = Double(10)
      configuration.timeoutIntervalForRequest = timeout
      configuration.timeoutIntervalForResource = timeout
      return URLSession(configuration: configuration)
    }
    .scope(.cached)
  }

  var iTunesService: Factory<ITunesService> {
    Factory(self) { ITunesService(session: self.iTunesServiceSession()) }.scope(.cached)
  }
}

struct ITunesService {
  // MARK: - Initialization

  private let session: any DataFetchable

  fileprivate init(session: any DataFetchable) {
    self.session = session
  }

  // MARK: - Public API

  func searchedPodcasts(matching term: String, limit: Int) async throws(SearchError)
    -> [PodcastWithEpisodeMetadata<UnsavedPodcast>]
  {
    let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty
    else { return [] }

    let searchResult: ITunesEntityResults =
      (try decode(try await performRequest(ITunesURL.searchRequest(for: trimmed, limit: limit))))

    return searchResult.podcastsWithMetadata
  }

  func topPodcasts(genreID: Int? = nil, limit: Int) async throws(SearchError)
    -> [PodcastWithEpisodeMetadata<UnsavedPodcast>]
  {
    let topPodcastResult: ITunesTopPodcastsFeed =
      (try decode(
        try await performRequest(ITunesURL.topPodcastsRequest(genreID: genreID, limit: limit))
      ))

    return try await lookupPodcasts(podcastIDs: topPodcastResult.podcastIDs)
  }

  func lookupPodcasts(podcastIDs: [ITunesPodcastID]) async throws(SearchError)
    -> [PodcastWithEpisodeMetadata<UnsavedPodcast>]
  {
    let lookupResult: ITunesEntityResults = try decode(
      try await performRequest(
        ITunesURL.lookupRequest(podcastIDs: podcastIDs)
      )
    )

    return lookupResult.podcastsWithMetadata
  }

  // MARK: - Private Helpers

  private func performRequest(_ request: URLRequest) async throws(SearchError) -> Data {
    do {
      return try await session.validatedData(for: request)
    } catch {
      throw SearchError.fetchFailure(request: request, caught: error)
    }
  }

  private func decode<T: Decodable>(_ data: Data) throws(SearchError) -> T {
    do {
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      return try decoder.decode(T.self, from: data)
    } catch {
      throw SearchError.parseFailure(data: data, caught: error)
    }
  }
}
