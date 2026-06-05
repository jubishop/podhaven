#if DEBUG
// Copyright Justin Bishop, 2026

import Foundation

// Synthesizes a minimal, parseable podcast RSS feed for a given URL so a fake
// session can answer arbitrary feed downloads in previews. Episode identifiers
// are derived from the URL, so distinct feeds yield distinct episodes.
enum PreviewFeed {
  static func rss(for url: URL, episodeCount: Int = 3) -> Data {
    let token = stableToken(url.absoluteString)
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "GMT")
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"

    let items =
      (0..<episodeCount)
      .map { index -> String in
        let guid = "preview-\(token)-\(index)"
        let pubDate = Date(timeIntervalSince1970: 1_700_000_000 - Double(index) * 86_400)
        return """
          <item>
            <guid isPermaLink="false">\(guid)</guid>
            <title>Preview Episode \(index)</title>
            <pubDate>\(formatter.string(from: pubDate))</pubDate>
            <enclosure url="https://example.com/audio/\(guid).mp3" type="audio/mpeg" length="0" />
            <description>A preview episode for layout testing.</description>
          </item>
          """
      }
      .joined(separator: "\n")

    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
        <channel>
          <title>Preview Podcast</title>
          <link>\(url.absoluteString)</link>
          <description>Preview podcast for layout testing.</description>
          <itunes:image href="https://example.com/image.png" />
          \(items)
        </channel>
      </rss>
      """
    return Data(xml.utf8)
  }

  // FNV-1a so the token is stable across runs (String.hashValue is seeded
  // per-process) and clean enough to embed in a guid / media URL.
  private static func stableToken(_ string: String) -> String {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in string.utf8 {
      hash ^= UInt64(byte)
      hash = hash &* 1_099_511_628_211
    }
    return String(hash, radix: 36)
  }
}
#endif
