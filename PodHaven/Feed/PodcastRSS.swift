// Copyright Justin Bishop, 2025

import Foundation
import XMLCoder

// MARK: - XMLCoder Extensions for Empty Elements

extension KeyedDecodingContainer {
  /// Decodes an optional value that may be present but empty in XML
  /// Returns nil if the key is missing, the value is empty, or decoding fails
  func decodeOptionalNonEmpty<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
    guard contains(key),
          let stringValue = try? decode(String.self, forKey: key),
          !stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }
    return try? decode(T.self, forKey: key)
  }
  
  /// Decodes an optional URL that may be present but empty in XML
  /// Returns nil if the key is missing, the value is empty, or not a valid URL
  func decodeOptionalURL(forKey key: Key) -> URL? {
    guard contains(key),
          let stringValue = try? decode(String.self, forKey: key),
          !stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }
    return URL(string: stringValue)
  }
}

struct PodcastRSS: Decodable, Sendable {
  private static let log = Log.as(LogSubsystem.Feed.podcast)

  // MARK: - Static Parsing Methods

  static func parse(_ data: Data) async throws(ParseError) -> Podcast {
    do {
      return try await withCheckedThrowingContinuation { continuation in
        do {
          let decoder = XMLDecoder()
          decoder.dateDecodingStrategy = .formatted(Date.rfc2822)
          let rssPodcast = try decoder.decode(PodcastRSS.self, from: data)
          continuation.resume(returning: rssPodcast.channel)
        } catch let error {
          continuation.resume(throwing: error)
        }
      }
    } catch {
      throw ParseError.invalidData(data: data, caught: error)
    }
  }

  // MARK: - Models

  @dynamicMemberLookup struct Episode: Decodable, Sendable {
    struct TopLevelValues: Decodable, Sendable {
      struct Enclosure: Decodable, Sendable {
        let url: MediaURL
      }
      let title: String
      let enclosure: Enclosure?
      let guid: GUID?
      let link: URL?
      let description: String?
      let pubDate: Date?
    }
    private let values: TopLevelValues

    struct iTunesNamespace: Decodable, Sendable {
      struct Image: Decodable, Sendable {
        let href: URL
      }
      let image: Image?
      let duration: String?

      enum CodingKeys: String, CodingKey {
        case image = "itunes:image"
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

  @dynamicMemberLookup struct Podcast: Decodable, Sendable {
    // Mark: - Attributes

    struct TopLevelValues: Decodable, Sendable {
      struct AtomLink: Decodable, Sendable {
        let href: URL
        let rel: String
      }
      let title: String
      let description: String
      let link: URL?
      let episodes: [Episode]
      let atomLinks: [AtomLink]

      enum CodingKeys: String, CodingKey {
        case title, description, link
        case episodes = "item"
        case atomLinks = "atom:link"
      }

      init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        episodes = try container.decode([Episode].self, forKey: .episodes)

        // Handle link - skip if missing or empty
        link = container.decodeOptionalURL(forKey: .link)

        // Try atom:link first, fallback to empty array if not found
        atomLinks = (try? container.decode([AtomLink].self, forKey: .atomLinks)) ?? []
      }
    }
    private let values: TopLevelValues

    struct iTunesNamespace: Decodable, Sendable {
      struct Image: Decodable, Sendable {
        let href: URL
      }
      let image: Image
      let newFeedURL: FeedURL?

      enum CodingKeys: String, CodingKey {
        case image = "itunes:image"
        case newFeedURL = "itunes:new-feed-url"
      }
    }
    let iTunes: iTunesNamespace

    // MARK: - Convenience Getters

    var feedURL: FeedURL? {
      guard let url = self.atomLinks.first(where: { $0.rel == "self" })?.href
      else { return nil }

      return FeedURL(url)
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

  private let channel: Podcast
}
