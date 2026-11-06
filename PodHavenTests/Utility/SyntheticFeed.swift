// Copyright Justin Bishop, 2026

import Foundation
import Testing

@testable import PodHaven

// Distinct, minimal RSS feeds and OPML subscriptions for imports of any size.
enum SyntheticFeed {
  static func url(_ index: Int) -> URL {
    URL(string: "https://synthetic.test/feed/\(index)")!
  }

  static func movedURL(_ index: Int) -> URL {
    URL(string: "https://synthetic.test/moved/\(index)")!
  }

  static func index(of url: URL) -> Int? {
    Int(url.lastPathComponent)
  }

  static func title(_ index: Int) -> String {
    "Synthetic \(index)"
  }

  static func opml(title: String = "Synthetic Import", feedCount: Int) -> Data {
    var outlines = ""
    for index in 0..<feedCount {
      outlines +=
        """
        <outline type="rss" text="\(Self.title(index))" xmlUrl="\(url(index).absoluteString)"/>

        """
    }
    return Data(
      """
      <?xml version="1.0"?>
      <opml version="1.0">
      <head><title>\(title)</title></head>
      <body>
      \(outlines)</body>
      </opml>
      """
      .utf8
    )
  }

  static func rss(index: Int, episodes: Int, moved: Bool = false) -> Data {
    let newFeedURL =
      moved ? "<itunes:new-feed-url>\(movedURL(index).absoluteString)</itunes:new-feed-url>" : ""
    var items = ""
    for episode in 0..<episodes {
      items += """
        <item><title>Episode \(episode)</title>\
        <enclosure url="https://synthetic.test/media/\(index)/\(episode).mp3" type="audio/mpeg" \
        length="1"/><guid>\(index)-\(episode)</guid>\
        <pubDate>Fri, 3 Jan 2025 12:00:00 +0000</pubDate></item>
        """
    }
    return Data(
      """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel>\
      <title>\(title(index))</title><description>Synthetic feed \(index)</description>\
      <itunes:image href="https://synthetic.test/art/\(index).jpg"/>\
      \(newFeedURL)\(items)</channel></rss>
      """
      .utf8
    )
  }

  static func respond(
    _ feedSession: FakeDataFetchable,
    episodes: Int,
    moved: Bool = false,
    after delay: @escaping @Sendable (URL) async throws -> Void = { _ in }
  ) async {
    await feedSession.setDefaultHandler { url in
      let index = try #require(index(of: url))
      try await delay(url)
      return (rss(index: index, episodes: episodes, moved: moved), URL.response(url))
    }
  }
}
