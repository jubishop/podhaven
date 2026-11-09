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

  private static func url(from string: String?) -> URL? {
    guard let string else { return nil }
    return URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  // MARK: - Episode

  @dynamicMemberLookup struct Episode: Decodable, Sendable {
    // MARK: - Attributes

    struct TopLevelValues: Decodable, Sendable {
      struct Enclosure: Decodable, Sendable {
        private let urlString: String?

        var url: MediaURL? {
          guard let url = PodcastRSS.url(from: urlString) else { return nil }
          return MediaURL(url)
        }

        enum CodingKeys: String, CodingKey {
          case urlString = "url"
        }
      }
      let title: String
      let enclosure: Enclosure?
      private let guidString: String?
      let link: String?  // URL?
      let description: String?
      let contentEncoded: String?
      let pubDateString: String?

      var guid: GUID? {
        guard let guidString, !guidString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return GUID(guidString)
      }

      enum CodingKeys: String, CodingKey {
        case title, enclosure, link, description
        case guidString = "guid"
        case pubDateString = "pubDate"
        case contentEncoded = "content:encoded"
      }
    }
    private let values: TopLevelValues

    struct ITunesNamespace: Decodable, Sendable {
      struct Image: Decodable, Sendable {
        private let hrefString: String?

        var href: URL? { PodcastRSS.url(from: hrefString) }

        enum CodingKeys: String, CodingKey {
          case hrefString = "href"
        }
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
        private let hrefString: String?
        let rel: String?

        var href: URL? { PodcastRSS.url(from: hrefString) }

        enum CodingKeys: String, CodingKey {
          case hrefString = "href"
          case rel
        }
      }
      let title: String
      let description: String
      let contentEncoded: String?
      let link: String?  // URL?
      let atomLinks: [AtomLink]
      let language: String?

      enum CodingKeys: String, CodingKey {
        case title, description, language, link
        case atomLinks = "atom:link"
        case contentEncoded = "content:encoded"
      }
    }
    private let values: TopLevelValues

    private enum ItemKey: String, CodingKey {
      case item
    }

    private struct DecodedEpisode: Decodable {
      let result: Result<Episode, any Error>

      init(from decoder: any Decoder) throws {
        result = Result { try Episode(from: decoder) }
      }
    }

    let episodes: [Episode]

    struct ITunesNamespace: Decodable, Sendable {
      struct Image: Decodable, Sendable {
        let href: URL
      }
      let image: Image
      private let newFeedURLString: String?
      let summary: String?

      var newFeedURL: FeedURL? {
        guard let url = PodcastRSS.url(from: newFeedURLString) else { return nil }
        return FeedURL(url)
      }

      enum CodingKeys: String, CodingKey {
        case image = "itunes:image"
        case newFeedURLString = "itunes:new-feed-url"
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
      guard let url = values.atomLinks.filter({ $0.rel == "self" }).compactMap(\.href).first
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

      let items = try decoder.container(keyedBy: ItemKey.self)
        .decode([DecodedEpisode].self, forKey: .item)
      var episodes: [Episode] = []
      var failures: [any Error] = []
      for item in items {
        switch item.result {
        case .success(let episode): episodes.append(episode)
        case .failure(let error): failures.append(error)
        }
      }
      if let firstFailure = failures.first {
        guard !episodes.isEmpty else { throw firstFailure }
        PodcastRSS.log.caughtError(
          "Dropped \(failures.count) of \(items.count) undecodable RSS items in '\(values.title)'",
          firstFailure,
          level: .warning
        )
      }
      self.episodes = episodes
    }
  }

  private let channel: Podcast
}
