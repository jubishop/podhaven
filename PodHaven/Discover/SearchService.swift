// Copyright Justin Bishop, 2025

import CryptoKit
import Foundation

enum SearchService: Sendable {
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
    let apiHeaderTime = Int(Date().timeIntervalSince1970)
    let data4Hash = apiKey + apiSecret + "\(apiHeaderTime)"
    let hashed = Insecure.SHA1.hash(data: Data(data4Hash.utf8))
    let hashString = hashed.compactMap { String(format: "%02x", $0) }.joined()

    let urlString = baseURLString + urlPath
    guard let url = URL(string: urlString) else { throw URLError(.badURL) }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.addValue("\(apiHeaderTime)", forHTTPHeaderField: "X-Auth-Date")
    request.addValue(apiKey, forHTTPHeaderField: "X-Auth-Key")
    request.addValue(hashString, forHTTPHeaderField: "Authorization")
    request.addValue("PodHaven", forHTTPHeaderField: "User-Agent")
    return request
  }
}
