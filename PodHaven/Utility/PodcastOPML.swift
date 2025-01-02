// Copyright Justin Bishop, 2025

import Foundation
import XMLCoder

struct PodcastOPML: Decodable, Sendable {
  // MARK: - Static Parsing Methods

  static func parse(_ url: URL) async throws -> [Feed] {
    let data = try Data(contentsOf: url)
    return try await parse(data)
  }

  static func parse(_ data: Data) async throws -> [Feed] {
    try await withCheckedThrowingContinuation { continuation in
      do {
        let decoder = XMLDecoder()
        let podcastOPML = try decoder.decode(PodcastOPML.self, from: data)
        continuation.resume(returning: podcastOPML.body.feeds)
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }

  // MARK: - Models

  struct Feed: Decodable, Sendable {
    let text: String
    let xmlUrl: String
  }

  struct Body: Decodable, Sendable {
    let feeds: [Feed]

    enum CodingKeys: String, CodingKey {
      case feeds = "outline"
    }
  }
  let body: Body
}
