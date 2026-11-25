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

enum PodcastOPMLError: Error, LocalizedError, Sendable {
  case tooDeeplyNested

  var errorDescription: String? {
    switch self {
    case .tooDeeplyNested:
      return "This OPML file has too many nested folders to import."
    }
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
    let depthLimiter = NestingDepthLimiter(maximumDepth: maximumNestingDepth)
    let parser = XMLParser(data: data)
    unsafe parser.delegate = depthLimiter
    parser.parse()
    guard depthLimiter.deepestDepth <= maximumNestingDepth
    else { throw PodcastOPMLError.tooDeeplyNested }

    let decoder = XMLDecoder()
    return try decoder.decode(PodcastOPML.self, from: data)
  }

  @concurrent static func isOPML(_ data: Data) async -> Bool {
    let detector = RootElementDetector()
    let parser = XMLParser(data: data)
    unsafe parser.delegate = detector
    parser.parse()
    return detector.rootElementName?.lowercased() == "opml"
  }

  private final class RootElementDetector: NSObject, XMLParserDelegate {
    private(set) var rootElementName: String?

    func parser(
      _ parser: XMLParser,
      didStartElement elementName: String,
      namespaceURI: String?,
      qualifiedName qName: String?,
      attributes attributeDict: [String: String] = [:]
    ) {
      rootElementName = elementName
      parser.abortParsing()
    }
  }

  // MARK: - Nesting Limit

  // XMLCoder decodes the recursive Outline model recursively, so deep nesting overflows the stack.
  private static let maximumNestingDepth = 16

  private final class NestingDepthLimiter: NSObject, XMLParserDelegate {
    private let maximumDepth: Int
    private var depth = 0
    private(set) var deepestDepth = 0

    init(maximumDepth: Int) {
      self.maximumDepth = maximumDepth
    }

    func parser(
      _ parser: XMLParser,
      didStartElement elementName: String,
      namespaceURI: String?,
      qualifiedName qName: String?,
      attributes attributeDict: [String: String] = [:]
    ) {
      depth += 1
      deepestDepth = max(deepestDepth, depth)
      if depth > maximumDepth { parser.abortParsing() }
    }

    func parser(
      _ parser: XMLParser,
      didEndElement elementName: String,
      namespaceURI: String?,
      qualifiedName qName: String?
    ) {
      depth -= 1
    }
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
