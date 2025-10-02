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
  private static let searchLimit = 100
  private static let trendingLimit = 100
  private static let lookupChunkSize = 50

  private static var defaultCountryCode: String {
    Locale.current.region?.identifier.lowercased() ?? "us"
  }

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

  func searchPodcasts(matching term: String) async throws(SearchError) -> IdentifiedArray<
    FeedURL, UnsavedPodcast
  > {
    let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return IdentifiedArray(uniqueElements: [], id: \.feedURL)
    }

    let request = buildSearchRequest(for: trimmed, limit: Self.searchLimit)
    let data = try await perform(request)
    let response: ITunesSearchResponse = try decode(data)

    let podcasts = response.podcasts.compactMap(convertToUnsavedPodcast)
    return deduplicate(podcasts)
  }

  func topPodcasts(
    countryCode overrideCountryCode: String? = nil,
    genreID: Int? = nil,
    limit: Int = Self.trendingLimit
  ) async throws(SearchError) -> IdentifiedArray<FeedURL, UnsavedPodcast> {
    let countryCode = (overrideCountryCode ?? Self.defaultCountryCode).lowercased()
    let request = buildTopPodcastsRequest(countryCode: countryCode, genreID: genreID, limit: limit)
    let data = try await perform(request)
    let response: ITunesTopPodcastsResponse = try decode(data)
    let ids = response.feed.entries.map(\.id.attributes.imId)
    guard !ids.isEmpty else {
      return IdentifiedArray(uniqueElements: [], id: \.feedURL)
    }

    let lookupResults = try await lookup(ids: ids, countryCode: countryCode)
    var lookupMap: [String: ITunesSearchResponse.Podcast] = [:]
    for result in lookupResults {
      if let identifier = result.collectionId ?? result.trackId {
        lookupMap[String(identifier)] = result
      }
    }

    let orderedPodcasts = ids.compactMap { lookupMap[$0].flatMap(convertToUnsavedPodcast) }
    return deduplicate(orderedPodcasts)
  }

  // MARK: - Networking

  private func perform(_ request: URLRequest) async throws(SearchError) -> Data {
    do {
      return try await session.validatedData(for: request)
    } catch {
      throw SearchError.fetchFailure(request: request, caught: error)
    }
  }

  private func lookup(ids: [String], countryCode: String) async throws(SearchError)
    -> [ITunesSearchResponse.Podcast]
  {
    guard !ids.isEmpty else { return [] }

    var aggregated: [ITunesSearchResponse.Podcast] = []
    for chunk in chunked(ids, size: Self.lookupChunkSize) {
      let request = ApplePodcastsURL.lookupRequest(
        ids: chunk,
        entity: "podcast",
        countryCode: countryCode
      )
      let data = try await perform(request)
      let response: ITunesSearchResponse
      do {
        response = try ApplePodcastsURL.decodeLookupResponse(
          data,
          as: ITunesSearchResponse.self
        )
      } catch {
        throw SearchError.parseFailure(data)
      }
      aggregated.append(contentsOf: response.podcasts)
    }
    return aggregated
  }

  // MARK: - Request Building

  private func buildSearchRequest(for term: String, limit: Int) -> URLRequest {
    var components = URLComponents()
    components.scheme = "https"
    components.host = Self.baseHost
    components.path = "/search"
    components.queryItems = [
      URLQueryItem(name: "term", value: term),
      URLQueryItem(name: "media", value: "podcast"),
      URLQueryItem(name: "entity", value: "podcast"),
      URLQueryItem(name: "limit", value: String(limit)),
    ]

    return buildRequest(from: components)
  }

  private func buildTopPodcastsRequest(countryCode: String, genreID: Int?, limit: Int)
    -> URLRequest
  {
    var pathComponents = ["", countryCode, "rss", "toppodcasts", "limit=\(limit)"]
    if let genreID {
      pathComponents.append("genre=\(genreID)")
    }
    pathComponents.append("json")

    var components = URLComponents()
    components.scheme = "https"
    components.host = Self.baseHost
    components.path = pathComponents.joined(separator: "/")

    return buildRequest(from: components)
  }

  private func buildRequest(from components: URLComponents) -> URLRequest {
    guard let url = components.url else {
      Assert.fatal("Unable to build request from components: \(components)")
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.addValue("PodHaven", forHTTPHeaderField: "User-Agent")
    return request
  }

  // MARK: - Helpers

  private func decode<T: Decodable>(_ data: Data) throws(SearchError) -> T {
    do {
      return try decoder.decode(T.self, from: data)
    } catch {
      throw SearchError.parseFailure(data)
    }
  }

  private func convertToUnsavedPodcast(_ result: ITunesSearchResponse.Podcast) -> UnsavedPodcast? {
    guard let feedURLString = result.feedUrl, let feedURL = URL(string: feedURLString) else {
      return nil
    }

    let artworkURLString =
      result.artworkUrl600 ?? result.artworkUrl100 ?? result.artworkUrl60
      ?? result.artworkUrl30
    guard let imageURLString = artworkURLString, let imageURL = URL(string: imageURLString) else {
      return nil
    }

    let title =
      result.collectionName ?? result.trackName ?? result.collectionCensoredName
      ?? result.trackCensoredName ?? "Podcast"

    let description =
      result.collectionDescription ?? result.longDescription ?? result.description
      ?? result.shortDescription ?? ""

    let linkString = result.collectionViewUrl ?? result.trackViewUrl
    let link = linkString.flatMap(URL.init)

    do {
      return try UnsavedPodcast(
        feedURL: FeedURL(feedURL),
        title: title,
        image: imageURL,
        description: description,
        link: link
      )
    } catch {
      return nil
    }
  }

  private func deduplicate(_ podcasts: [UnsavedPodcast]) -> IdentifiedArray<FeedURL, UnsavedPodcast>
  {
    var unique: [UnsavedPodcast] = []
    var seen = Set<FeedURL>()

    for podcast in podcasts where seen.insert(podcast.feedURL).inserted {
      unique.append(podcast)
    }

    return IdentifiedArray(uniqueElements: unique, id: \.feedURL)
  }

  private func chunked<T>(_ values: [T], size: Int) -> [[T]] {
    guard size > 0 else { return [] }
    return stride(from: 0, to: values.count, by: size)
      .map { index in
        Array(values[index..<min(index + size, values.count)])
      }
  }
}
