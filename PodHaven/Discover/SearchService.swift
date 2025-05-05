// Copyright Justin Bishop, 2025

import ErrorKit
import Factory
import Foundation

extension Container {
  var searchService: Factory<SearchService> {
    Factory(self) {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.allowsCellularAccess = true
      configuration.waitsForConnectivity = true
      let timeout = Double(10)
      configuration.timeoutIntervalForRequest = timeout
      configuration.timeoutIntervalForResource = timeout
      return SearchService(session: URLSession(configuration: configuration))
    }
    .scope(.singleton)
  }
}

struct SearchService: Sendable {
  // MARK: - Static Helpers

  #if DEBUG
  static func initForTest(session: DataFetchable) -> SearchService {
    SearchService(session: session)
  }
  static func parseForPreview<T: Decodable>(_ data: Data) async throws(SearchError) -> T {
    try await parse(data)
  }
  #endif

  // MARK: - Initialization

  private let session: DataFetchable

  fileprivate init(session: DataFetchable) {
    self.session = session
  }

  // MARK: - Search Methods

  func searchByTerm(_ term: String) async throws(SearchError) -> TermResult {
    try await Self.parse(
      try await performRequest("/search/byterm", [URLQueryItem(name: "q", value: term)])
    )
  }

  func searchByTitle(_ title: String) async throws(SearchError) -> TitleResult {
    try await Self.parse(
      try await performRequest(
        "/search/bytitle",
        [URLQueryItem(name: "q", value: title), URLQueryItem(name: "similar", value: "true")]
      )
    )
  }

  func searchByPerson(_ person: String) async throws(SearchError) -> PersonResult {
    try await Self.parse(
      try await performRequest("/search/byperson", [URLQueryItem(name: "q", value: person)])
    )
  }

  func searchTrending(categories: [String] = [], language: String? = nil) async throws(SearchError)
    -> TrendingResult
  {
    var queryItems: [URLQueryItem] = []
    if !categories.isEmpty {
      queryItems.append(URLQueryItem(name: "cat", value: categories.joined(separator: ",")))
    }
    if let language = language {
      queryItems.append(URLQueryItem(name: "lang", value: language))
    }
    return try await Self.parse(try await performRequest("/podcasts/trending", queryItems))
  }

  // MARK: - Private Helpers

  static private let apiKey = "G3SPKHRKRLCU7Z2PJXEW"
  static private let apiSecret = "tQcZQATRC5Yg#zG^s7jyaVsMU8fQx5rpuGU6nqC7"
  static private let baseHost = "api.podcastindex.org"
  static private let basePath = "/api/1.0"

  private static func parse<T: Decodable>(_ data: Data) async throws(SearchError) -> T {
    do {
      return try await withCheckedThrowingContinuation { continuation in
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        do {
          let searchResult = try decoder.decode(T.self, from: data)
          continuation.resume(returning: searchResult)
        } catch {
          continuation.resume(throwing: error)
        }
      }
    } catch {
      throw SearchError.parseFailure(data)
    }
  }

  private func performRequest(_ path: String, _ query: [URLQueryItem] = [])
    async throws(SearchError) -> Data
  {
    let request = buildRequest(path, query)
    do {
      return try await NetworkError.catch {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
          throw NetworkError.decodingFailure
        }
        guard (200...299).contains(httpResponse.statusCode) else {
          throw NetworkError.serverError(
            code: httpResponse.statusCode,
            message: "Invalid response code for: \(request)"
          )
        }
        return data
      }
    } catch {
      throw SearchError.fetchFailure(request: request, caught: error)
    }
  }

  private func buildRequest(_ path: String, _ queryItems: [URLQueryItem] = []) -> URLRequest {
    var components = URLComponents()
    components.scheme = "https"
    components.host = Self.baseHost
    components.path = Self.basePath + path
    if !queryItems.isEmpty {
      components.queryItems = queryItems
    }
    guard let url = components.url
    else { Log.fatal("Can't make url from: \(components)?") }

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
