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

  func searchPodcasts(matching term: String, limit: Int) async throws(SearchError)
    -> IdentifiedArray<
      FeedURL, UnsavedPodcast
    >
  {
    let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return IdentifiedArray(uniqueElements: [], id: \.feedURL)
    }

//    let request = buildSearchRequest(for: trimmed, limit: limit)
//    let data = try await perform(request)
//    let response: ITunesSearchResponse = try decode(data)

//    let podcasts = response.unsavedPodcasts
    return IdentifiedArray()
  }

  func topPodcasts(genreID: Int? = nil, limit: Int) async throws(SearchError)
    -> IdentifiedArray<FeedURL, UnsavedPodcast>
  {
    let response: ITunesTopPodcastsResponse =
      (try decode(
        try await perform(ITunesURL.topPodcastsRequest(genreID: genreID, limit: limit))
      ))

    return IdentifiedArray(
      uniqueElements: try await lookup(iTunesIDs: response.iTunesIDs),
      id: \.feedURL
    )
  }

  // MARK: - Networking

  private func lookup(iTunesIDs: [ITunesPodcastID]) async throws(SearchError) -> [UnsavedPodcast] {
//    let data = try await perform(
//      ApplePodcastsURL.lookupRequest(
//        iTunesIDs: iTunesIDs,
//        entity: "podcast"
//      )
//    )
    return []
//    let iTunesSearchResponse = return try decode(data)
  }

  private func perform(_ request: URLRequest) async throws(SearchError) -> Data {
    do {
      return try await session.validatedData(for: request)
    } catch {
      throw SearchError.fetchFailure(request: request, caught: error)
    }
  }

  // MARK: - Private Helpers

  private func decode<T: Decodable>(_ data: Data) throws(SearchError) -> T {
    do {
      return try JSONDecoder().decode(data)
    } catch {
      throw SearchError.parseFailure(data)
    }
  }
}
