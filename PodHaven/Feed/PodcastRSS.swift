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

  struct Podcast: Decodable, Sendable {
    let title: String?
    let description: String?
    let episodes: [Episode]
    let iTunes: iTunesNamespace

    struct iTunesNamespace: Codable, Sendable {
      let summary: String?

      enum CodingKeys: String, CodingKey {
        case summary = "itunes:summary"
      }
    }

    enum CodingKeys: String, CodingKey {
      case title, description
      case episodes = "item"
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      title = try container.decodeIfPresent(String.self, forKey: .title)
      description = try container.decodeIfPresent(String.self, forKey: .description)
      episodes = try container.decodeIfPresent([Episode].self, forKey: .episodes) ?? []
      iTunes = try iTunesNamespace(from: decoder)
    }
  }

  struct Episode: Codable, Sendable {
    let title: String
  }

  // MARK: - Private

  private let channel: Podcast
}
