// Copyright Justin Bishop, 2025

import Foundation

struct SearchService: Sendable {
  private let session: DataFetchable
  init(session: DataFetchable) {
    self.session = session
  }

  // MARK: - Search Methods

  func searchByTerm(_ term: String) async throws -> SearchResult {
    let urlPath = "/search/byterm?q=\(term)"
    return try await parse(try await performRequest(urlPath))
  }

  func listCategories() async throws -> CategoriesResult {
    let urlPath = "/categories/list"
    return try await parse(try await performRequest(urlPath))
  }

  // MARK: - Static Private Helpers

  static private let apiKey = "G3SPKHRKRLCU7Z2PJXEW"
  static private let apiSecret = "tQcZQATRC5Yg#zG^s7jyaVsMU8fQx5rpuGU6nqC7"
  static private let baseURLString = "https://api.podcastindex.org/api/1.0"

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

  private func performRequest(_ urlPath: String) async throws -> Data {
    let request = try buildRequest(urlPath)
    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw SearchError.invalidResponse
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      throw SearchError.invalidStatusCode(httpResponse.statusCode)
    }
    return data
  }

  private func buildRequest(_ urlPath: String) throws -> URLRequest {
    let urlString = Self.baseURLString + urlPath
    guard let url = URL(string: urlString) else { fatalError("Can't make url from: \(urlString)?") }
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
