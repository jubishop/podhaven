// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import XMLCoder

struct PodcastOPML: Codable, Sendable {
  // MARK: - Import Methods

  static func parse(_ url: URL) async throws -> PodcastOPML {
    let data = try await URLSession.shared.validatedData(from: url)
    return try await parse(data)
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

  static func exportSubscribedPodcasts() async throws -> Data {
    let subscribedPodcasts = try await Container.shared.repo().allPodcasts(Podcast.subscribed)
    return try await generateOPML(from: subscribedPodcasts)
  }

  static func generateOPML(from podcasts: [Podcast]) async throws -> Data {
    let outlines = podcasts.map { podcast in
      Body.Outline(text: podcast.title, xmlUrl: podcast.feedURL)
    }

    let opml = PodcastOPML(
      head: Head(title: "PodHaven Subscriptions"),
      body: Body(outlines: outlines)
    )

    return try await withCheckedThrowingContinuation { continuation in
      do {
        let encoder = XMLEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(opml)
        continuation.resume(returning: data)
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }

  // MARK: - Models

  struct Body: Codable, Sendable {
    struct Outline: Codable, Sendable, DynamicNodeEncoding {
      let text: String
      let xmlUrl: FeedURL
      let type: String

      init(text: String, xmlUrl: FeedURL, type: String = "rss") {
        self.text = text
        self.xmlUrl = xmlUrl
        self.type = type
      }

      enum CodingKeys: String, CodingKey {
        case text
        case xmlUrl
        case type
      }

      static func nodeEncoding(for key: CodingKey) -> XMLEncoder.NodeEncoding { .attribute }
    }
    let outlines: [Outline]

    enum CodingKeys: String, CodingKey {
      case outlines = "outline"
    }
  }

  struct Head: Codable, Sendable {
    let title: String?
  }

  let head: Head
  let body: Body
  let version: String?

  init(head: Head, body: Body, version: String? = "2.0") {
    self.head = head
    self.body = body
    self.version = version
  }
}
