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
        decoder.dateDecodingStrategy = .formatted(Date.rfc2822)
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
      let title: String
      let description: String
      let link: String
      let episodes: [Episode]

      enum CodingKeys: String, CodingKey {
        case title, description, link
        case episodes = "item"
      }
    }
    private let values: TopLevelValues

    struct iTunesNamespace: Decodable, Sendable {
      struct Image: Decodable, Sendable {
        let href: String
      }
      let image: Image
      let newFeedURL: String?

      enum CodingKeys: String, CodingKey {
        case image = "itunes:image"
        case newFeedURL = "itunes:new-feed-url"
      }
    }
    let iTunes: iTunesNamespace

    // MARK: - Meta

    subscript<T>(dynamicMember keyPath: KeyPath<TopLevelValues, T>) -> T {
      values[keyPath: keyPath]
    }

    init(from decoder: Decoder) throws {
      values = try TopLevelValues(from: decoder)
      iTunes = try iTunesNamespace(from: decoder)
    }
  }

  @dynamicMemberLookup
  struct Episode: Decodable, Sendable {
    struct TopLevelValues: Decodable, Sendable {
      struct Enclosure: Decodable, Sendable {
        let url: String
      }
      let title: String
      let enclosure: Enclosure
      let guid: String
      let pubDate: Date?
    }
    private let values: TopLevelValues

    struct iTunesNamespace: Decodable, Sendable {
      let duration: String?

      enum CodingKeys: String, CodingKey {
        case duration = "itunes:duration"
      }
    }
    let iTunes: iTunesNamespace

    // MARK: - Meta

    subscript<T>(dynamicMember keyPath: KeyPath<TopLevelValues, T>) -> T {
      values[keyPath: keyPath]
    }

    init(from decoder: Decoder) throws {
      values = try TopLevelValues(from: decoder)
      iTunes = try iTunesNamespace(from: decoder)
    }
  }

  private let channel: Podcast
}
