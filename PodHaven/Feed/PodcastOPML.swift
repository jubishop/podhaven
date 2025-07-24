// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import XMLCoder

struct PodcastOPML: Codable, Sendable {
  // MARK: - Import Methods

  static func parse(_ url: URL) async throws(ParseError) -> PodcastOPML {
    try await ParseError.catch {
      try await parse(try await URLSession.shared.validatedData(from: url))
    }
  }

  static func parse(_ data: Data) async throws(ParseError) -> PodcastOPML {
    do {
      return try await withCheckedThrowingContinuation { continuation in
        do {
          let decoder = XMLDecoder()
          let podcastOPML = try decoder.decode(PodcastOPML.self, from: data)
          continuation.resume(returning: podcastOPML)
        } catch let error {
          continuation.resume(throwing: error)
        }
      }
    } catch {
      throw ParseError.invalidData(data: data, caught: error)
    }
  }

  // MARK: - Export Methods

  static func exportSubscribedPodcasts() async throws(ParseError) -> Data {
    do {
      let subscribedPodcasts = try await Container.shared.repo().allPodcasts(Podcast.subscribed)
      return try await generateOPML(from: subscribedPodcasts)
    } catch {
      throw ParseError.exportFailure(error)
    }
  }

  private static func generateOPML(from podcasts: [Podcast]) async throws -> Data {
    let opml = PodcastOPML(
      head: Head(title: "PodHaven Subscriptions"),
      body: Body(
        outlines: podcasts.map { podcast in
          Body.Outline(text: podcast.title, xmlUrl: podcast.feedURL)
        }
      )
    )

    return try await withCheckedThrowingContinuation { continuation in
      do {
        let encoder = XMLEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(
          opml,
          withRootKey: "opml",
          rootAttributes: ["version": "2.0"],
          header: XMLHeader(version: 1.0, encoding: "UTF-8")
        )
        continuation.resume(returning: data)
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }

  // MARK: - Models

  fileprivate struct Body: Codable, Sendable {
    fileprivate struct Outline: Codable, Sendable, DynamicNodeEncoding {
      let text: String
      let title: String?
      let xmlUrl: FeedURL?
      let type: String?
      let outlines: [Outline]?

      init(text: String, xmlUrl: FeedURL, type: String = "rss") {
        self.text = text
        self.title = text
        self.xmlUrl = xmlUrl
        self.type = type
        self.outlines = nil
      }

      var flattenedOutlines: [Outline] {
        guard let outlines
        else { return [self] }

        return [self] + outlines.flatMap { $0.flattenedOutlines }
      }

      static func nodeEncoding(for key: CodingKey) -> XMLEncoder.NodeEncoding { .attribute }

      enum CodingKeys: String, CodingKey {
        case text, title, xmlUrl, type
        case outlines = "outline"
      }
    }
    fileprivate let outlines: [Outline]

    enum CodingKeys: String, CodingKey {
      case outlines = "outline"
    }
  }

  private struct Head: Codable, Sendable {
    let title: String?
  }

  private let head: Head
  private let body: Body

  // MARK: - Data Accessors

  var rssFeeds: [(feedURL: FeedURL, title: String)] {
    body.outlines
      .flatMap { $0.flattenedOutlines }
      .compactMap { outline in
        guard let xmlUrl = outline.xmlUrl,
          let feedURL = try? FeedURL(xmlUrl.rawValue.convertToValidURL())
        else { return nil }

        return (feedURL: feedURL, title: outline.text)
      }
  }

  var title: String? { head.title }
}
