// Copyright Justin Bishop, 2025

import Foundation

enum SearchService: Sendable {
  // MARK: - Static Search Methods

  static func searchByTerm(_ term: String) async throws -> Data {
    let urlPath = "/search/byterm?q=\(term)"
    return try await performRequest(urlPath)
  }

  // MARK: - Private Helpers

  static private let apiKey = "G3SPKHRKRLCU7Z2PJXEW"
  static private let apiSecret = "tQcZQATRC5Yg#zG^s7jyaVsMU8fQx5rpuGU6nqC7"
  static private let baseURLString = "https://api.podcastindex.org/api/1.0"
  static private let urlSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.allowsCellularAccess = true
    configuration.waitsForConnectivity = true
    let timeout = Double(10)
    configuration.timeoutIntervalForRequest = timeout
    configuration.timeoutIntervalForResource = timeout
    return URLSession(configuration: configuration)
  }()

  static private func performRequest(_ urlPath: String) async throws -> Data {
    let request = try buildRequest(urlPath)
    let (data, response) = try await urlSession.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw SearchError.invalidResponse
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      throw SearchError.invalidStatusCode(httpResponse.statusCode)
    }
    return data
  }

  static private func buildRequest(_ urlPath: String) throws -> URLRequest {
    let urlString = baseURLString + urlPath
    guard let url = URL(string: urlString) else { throw SearchError.badURL(urlString) }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"

    request.addValue("PodHaven", forHTTPHeaderField: "User-Agent")
    request.addValue(apiKey, forHTTPHeaderField: "X-Auth-Key")

    let apiHeaderTime = String(Int(Date().timeIntervalSince1970))
    request.addValue(apiHeaderTime, forHTTPHeaderField: "X-Auth-Date")

    let hash = (apiKey + apiSecret + apiHeaderTime).sha1()
    request.addValue(hash, forHTTPHeaderField: "Authorization")

    return request
  }
}
