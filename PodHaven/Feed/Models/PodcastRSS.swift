// Copyright Justin Bishop, 2025

import Foundation
import Logging
import Tagged
import XMLCoder

struct PodcastRSS: Decodable, Sendable {
  private static let log = Log.as(LogSubsystem.Feed.podcast)

  // MARK: - Static Parsing Methods

  @concurrent static func parse(_ data: Data) async throws -> Podcast {
    let decoder = XMLDecoder()
    return try decoder.decode(PodcastRSS.self, from: data).channel
  }

  // MARK: - Episode

  @dynamicMemberLookup struct Episode: Decodable, Sendable {
    // MARK: - Attributes

    struct TopLevelValues: Decodable, Sendable {
      struct Enclosure: Decodable, Sendable {
        let url: MediaURL
      }
      let title: String
      let enclosure: Enclosure?
      let guid: GUID?
      let link: String?  // URL?
      let description: String?
      let contentEncoded: String?
      let pubDateString: String?

      enum CodingKeys: String, CodingKey {
        case title, enclosure, guid, link, description
        case pubDateString = "pubDate"
        case contentEncoded = "content:encoded"
      }
    }
    private let values: TopLevelValues

    struct ITunesNamespace: Decodable, Sendable {
      struct Image: Decodable, Sendable {
        let href: URL
      }
      let image: Image?
      let duration: String?
      let summary: String?

      enum CodingKeys: String, CodingKey {
        case image = "itunes:image"
        case duration = "itunes:duration"
        case summary = "itunes:summary"
      }
    }
    let iTunes: ITunesNamespace

    struct PodcastNamespace: Decodable, Sendable {
      private struct ElementKey: CodingKey {
        let stringValue: String
        let intValue: Int?

        init?(stringValue: String) {
          self.stringValue = stringValue
          intValue = nil
        }

        init?(intValue: Int) {
          stringValue = String(intValue)
          self.intValue = intValue
        }
      }

      private struct DecodedTranscriptReference: Decodable {
        let value: PublisherTranscriptReference?

        init(from decoder: any Decoder) throws {
          do {
            value = try PublisherTranscriptReference(from: decoder)
          } catch {
            PodcastRSS.log.caughtError(
              "Ignoring malformed publisher transcript reference",
              error,
              level: .info
            )
            value = nil
          }
        }
      }

      let transcripts: [PublisherTranscriptReference]

      init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: ElementKey.self)
        var decoded: [DecodedTranscriptReference] = []
        var decodedElementNames = Set<String>()
        for key in container.allKeys
        where key.stringValue.split(separator: ":").last == "transcript" {
          guard decodedElementNames.insert(key.stringValue).inserted else { continue }
          decoded.append(
            contentsOf: try container.decodeIfPresent(
              [DecodedTranscriptReference].self,
              forKey: key
            ) ?? []
          )
        }
        transcripts = decoded.compactMap(\.value)
      }
    }
    let podcast: PodcastNamespace

    // MARK: - Convenience Getters

    var description: String? {
      if let contentEncoded = values.contentEncoded, !contentEncoded.isEmpty {
        return contentEncoded
      }
      if let summary = iTunes.summary, !summary.isEmpty {
        return summary
      }
      return values.description
    }

    var link: URL? {
      URL(string: values.link ?? "")
    }

    var pubDate: Date? {
      guard let pubDateString = values.pubDateString else { return nil }
      guard let date = Date.parseFeedDate(pubDateString) else {
        PodcastRSS.log.warning("Unparseable pubDate '\(pubDateString)' for \(values.title)")
        return nil
      }
      return date
    }

    // MARK: - Meta

    subscript<T>(dynamicMember keyPath: KeyPath<TopLevelValues, T>) -> T {
      values[keyPath: keyPath]
    }

    init(from decoder: any Decoder) throws {
      values = try TopLevelValues(from: decoder)
      iTunes = try ITunesNamespace(from: decoder)
      podcast = try PodcastNamespace(from: decoder)
    }
  }

  // MARK: - Podcast

  @dynamicMemberLookup struct Podcast: Decodable, Sendable {

    // MARK: - Attributes

    struct TopLevelValues: Decodable, Sendable {
      struct AtomLink: Decodable, Sendable {
        let href: URL
        let rel: String
      }
      let title: String
      let description: String
      let contentEncoded: String?
      let link: String?  // URL?
      let episodes: [Episode]
      let atomLinks: [AtomLink]
      let language: String?

      enum CodingKeys: String, CodingKey {
        case title, description, language, link
        case episodes = "item"
        case atomLinks = "atom:link"
        case contentEncoded = "content:encoded"
      }
    }
    private let values: TopLevelValues

    struct ITunesNamespace: Decodable, Sendable {
      struct Image: Decodable, Sendable {
        let href: URL
      }
      let image: Image
      let newFeedURL: FeedURL?
      let summary: String?

      enum CodingKeys: String, CodingKey {
        case image = "itunes:image"
        case newFeedURL = "itunes:new-feed-url"
        case summary = "itunes:summary"
      }
    }
    let iTunes: ITunesNamespace

    // MARK: - Convenience Getters

    var description: String {
      if let contentEncoded = values.contentEncoded, !contentEncoded.isEmpty {
        return contentEncoded
      }
      if let summary = iTunes.summary, !summary.isEmpty {
        return summary
      }
      return values.description
    }

    var feedURL: FeedURL? {
      guard let url = self.atomLinks.first(where: { $0.rel == "self" })?.href
      else { return nil }

      return FeedURL(url)
    }

    var link: URL? {
      URL(string: values.link ?? "")
    }

    // MARK: - Meta

    subscript<T>(dynamicMember keyPath: KeyPath<TopLevelValues, T>) -> T {
      values[keyPath: keyPath]
    }

    init(from decoder: any Decoder) throws {
      values = try TopLevelValues(from: decoder)
      iTunes = try ITunesNamespace(from: decoder)
    }
  }

  private let channel: Podcast
}
