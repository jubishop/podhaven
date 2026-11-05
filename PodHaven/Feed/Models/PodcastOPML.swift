// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging
import SwiftUI
import Tagged
import UniformTypeIdentifiers
import XMLCoder

extension Container {
  var podcastOPMLSession: Factory<any DataFetchable> {
    Factory(self) { URLSession.shared }
  }
}

struct PodcastOPML: Codable, Sendable {
  private static let log = Log.as(LogSubsystem.Feed.opml)

  static let contentType = UTType(importedAs: "public.opml", conformingTo: .xml)

  // MARK: - Import Methods

  static func parse(_ url: URL) async throws -> PodcastOPML {
    log.debug("Parsing url: \(url)")
    let data = try await Container.shared.podcastOPMLSession().validatedData(from: url)
    do {
      return try await parse(data)
    } catch {
      Container.shared.opmlImportDiagnostics()
        .parseFailed(error, data: data, fileName: url.lastPathComponent)
      throw error
    }
  }

  @concurrent static func parse(_ data: Data) async throws -> PodcastOPML {
    log.debug("Parsing data of size: \(data.count)")
    let decoder = XMLDecoder()
    return try decoder.decode(PodcastOPML.self, from: data)
  }

  // MARK: - Export Methods

  struct ExportItem: Transferable {
    static var transferRepresentation: some TransferRepresentation {
      DataRepresentation(
        exportedContentType: PodcastOPML.contentType
      ) { item in
        try await exportSubscribedPodcasts()
      }
    }
  }

  static func exportSubscribedPodcasts() async throws -> Data {
    let subscribedPodcasts = try await Container.shared.repo().allPodcasts(Podcast.subscribed)
    return try await generateOPML(from: subscribedPodcasts)
  }

  @concurrent private static func generateOPML(from podcasts: [Podcast]) async throws -> Data {
    let opml = PodcastOPML(
      head: Head(title: "PodHaven Subscriptions"),
      body: Body(
        outlines: podcasts.map { podcast in
          Body.Outline(text: podcast.title, xmlUrl: podcast.feedURL.absoluteString)
        }
      )
    )

    let encoder = XMLEncoder()
    encoder.outputFormatting = .prettyPrinted
    return try encoder.encode(
      opml,
      withRootKey: "opml",
      rootAttributes: ["version": "2.0"],
      header: XMLHeader(version: 1.0, encoding: "UTF-8")
    )
  }

  // MARK: - Models

  fileprivate struct Body: Codable, Sendable {
    fileprivate struct Outline: Codable, Sendable, DynamicNodeEncoding {
      let text: String
      let title: String?
      let xmlUrl: String?
      let type: String?
      let outlines: [Outline]?

      init(text: String, xmlUrl: String, type: String = "rss") {
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

      static func nodeEncoding(for key: any CodingKey) -> XMLEncoder.NodeEncoding { .attribute }

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

  struct RSSFeeds: Sendable {
    let feeds: [(feedURL: FeedURL, title: String)]
    let skippedCount: Int
  }

  var rssFeeds: RSSFeeds {
    var feeds: [(feedURL: FeedURL, title: String)] = []
    var skippedCount = 0
    for outline in body.outlines.flatMap(\.flattenedOutlines) {
      guard let xmlUrl = outline.xmlUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
      else {
        if outline.type?.lowercased() == "rss" { skippedCount += 1 }
        continue
      }

      guard !xmlUrl.isEmpty
      else {
        skippedCount += 1
        continue
      }

      guard let url = URL(string: xmlUrl)
      else {
        Self.log.info("Unparseable feed URL '\(xmlUrl)' for outline '\(outline.text)'")
        skippedCount += 1
        continue
      }

      let feedURL: FeedURL
      do {
        feedURL = try FeedURL(url).convertToHTTPSURL()
      } catch {
        Self.log.caughtError(
          "Invalid feed URL '\(xmlUrl)' for outline '\(outline.text)'",
          error,
          level: .info
        )
        skippedCount += 1
        continue
      }
      feeds.append((feedURL: feedURL, title: outline.text))
    }
    return RSSFeeds(feeds: feeds, skippedCount: skippedCount)
  }

  var title: String? { head.title }
}
