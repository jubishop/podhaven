// Copyright Justin Bishop, 2025

import Foundation

struct SearchService: Sendable {
  private let session: DataFetchable
  init(session: DataFetchable) {
    self.session = session
  }

  // MARK: - Search Methods

  func searchByTerm(_ term: String) async throws -> SearchResult {
    try await parse(
      try await performRequest("/search/byterm", [URLQueryItem(name: "q", value: term)])
    )
  }

  func searchByTitle(_ title: String) async throws -> SearchResult {
    try await parse(
      try await performRequest("/search/bytitle", [URLQueryItem(name: "q", value: title)])
    )
  }

  func searchByPerson(_ person: String) async throws -> EpisodeResult {
    try await parse(
      try await performRequest("/search/byperson", [URLQueryItem(name: "q", value: person)])
    )
  }

  func searchTrending(categories: [String] = [], language: String? = nil) async throws
    -> TrendingResult
  {
    var queryItems: [URLQueryItem] = []
    if !categories.isEmpty {
      queryItems.append(URLQueryItem(name: "cat", value: categories.joined(separator: ",")))
    }
    if let language = language {
      queryItems.append(URLQueryItem(name: "lang", value: language))
    }
    return try await parse(try await performRequest("/podcasts/trending", queryItems))
  }

  // MARK: - Static Private Helpers

  static private let apiKey = "G3SPKHRKRLCU7Z2PJXEW"
  static private let apiSecret = "tQcZQATRC5Yg#zG^s7jyaVsMU8fQx5rpuGU6nqC7"
  static private let baseHost = "api.podcastindex.org"
  static private let basePath = "/api/1.0"

  private func parse<T: Decodable>(_ data: Data) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
      do {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let searchResult = try decoder.decode(T.self, from: data)
        continuation.resume(returning: searchResult)
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }

  private func performRequest(_ path: String, _ query: [URLQueryItem]? = nil) async throws -> Data {
    let request = try buildRequest(path, query)
    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw Err.msg("Invalid HTTP Response")
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      throw Err.msg("Invalid Status Code: \(httpResponse.statusCode)")
    }
    return data
  }

  private func buildRequest(_ path: String, _ query: [URLQueryItem]? = nil) throws -> URLRequest {
    var components = URLComponents()
    components.scheme = "https"
    components.host = Self.baseHost
    components.path = Self.basePath + path
    components.queryItems = query
    guard let url = components.url else { fatalError("Can't make url from: \(components)?") }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"

    request.addValue("PodHaven", forHTTPHeaderField: "User-Agent")
    request.addValue(Self.apiKey, forHTTPHeaderField: "X-Auth-Key")

    let apiHeaderTime = String(Int(Date().timeIntervalSince1970))
    request.addValue(apiHeaderTime, forHTTPHeaderField: "X-Auth-Date")

    let hash = (Self.apiKey + Self.apiSecret + apiHeaderTime).sha1()
    request.addValue(hash, forHTTPHeaderField: "Authorization")

    return request
  }
}
