// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import IdentifiedCollections

extension Container {
  var searchServiceSession: Factory<DataFetchable> {
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

  var searchService: Factory<SearchService> {
    Factory(self) { SearchService(session: self.searchServiceSession()) }.scope(.cached)
  }
}

struct SearchService {
  // MARK: - Configuration

  private static let baseHost = "itunes.apple.com"

  // MARK: - Initialization

  private let session: DataFetchable
  private let decoder: JSONDecoder

  fileprivate init(session: DataFetchable) {
    self.session = session
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .useDefaultKeys
    self.decoder = decoder
  }

  // MARK: - Public API

  func searchedPodcasts(matching term: String, limit: Int) async throws(SearchError)
    -> IdentifiedArray<FeedURL, UnsavedPodcast>
  {
    let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty
    else { return IdentifiedArray(uniqueElements: [], id: \.feedURL) }

    let searchResult: ITunesEntityResults =
      (try decode(try await performRequest(ITunesURL.searchRequest(for: trimmed, limit: limit))))

    return IdentifiedArray(
      uniqueElements: searchResult.unsavedPodcasts,
      id: \.feedURL
    )
  }

  func topPodcasts(genreID: Int? = nil, limit: Int) async throws(SearchError)
    -> IdentifiedArray<FeedURL, UnsavedPodcast>
  {
    let topPodcastResult: ITunesTopPodcastsFeed =
      (try decode(
        try await performRequest(ITunesURL.topPodcastsRequest(genreID: genreID, limit: limit))
      ))

    let lookupResult: ITunesEntityResults = try decode(
      try await performRequest(
        ITunesURL.lookupRequest(podcastIDs: topPodcastResult.podcastIDs)
      )
    )

    return IdentifiedArray(
      uniqueElements: lookupResult.unsavedPodcasts,
      id: \.feedURL
    )
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
      return try JSONDecoder().decode(data)
    } catch {
      throw SearchError.parseFailure(data: data, caught: error)
    }
  }
}
