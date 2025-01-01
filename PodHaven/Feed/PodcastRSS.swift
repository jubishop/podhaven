// Copyright Justin Bishop, 2025

import Foundation
import XMLCoder

struct PodcastRSS: Decodable, Sendable {
  // MARK: - Static Parsing Methods

  static func parse(_ url: URL) async throws -> Podcast {
    let data = try Data(contentsOf: url)
    return try await parse(data)
  }

  static func parse(_ data: Data) async throws -> Podcast {
    try await withCheckedThrowingContinuation { continuation in
      do {
        let decoder = XMLDecoder()
        let podcastRSS = try decoder.decode(PodcastRSS.self, from: data)
        continuation.resume(returning: podcastRSS.channel)
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }

  // MARK: - Models

  @dynamicMemberLookup
  struct Podcast: Decodable, Sendable {
    // Mark: - Attributes

    struct TopLevelValues: Decodable, Sendable {
      let title: String?
      let description: String?
      let episodes: [Episode]?

      enum CodingKeys: String, CodingKey {
        case title, description
        case episodes = "item"
      }
    }
    private let values: TopLevelValues

    let iTunes: iTunesNamespace
    struct iTunesNamespace: Codable, Sendable {
      let summary: String?

      enum CodingKeys: String, CodingKey {
        case summary = "itunes:summary"
      }
    }

    // MARK: - Meta

    subscript<T>(dynamicMember keyPath: KeyPath<TopLevelValues, T>) -> T {
      values[keyPath: keyPath]
    }

    init(from decoder: Decoder) throws {
      values = try TopLevelValues(from: decoder)
      iTunes = try iTunesNamespace(from: decoder)
    }
  }

  struct Episode: Codable, Sendable {
    let title: String
  }

  private let channel: Podcast
}
