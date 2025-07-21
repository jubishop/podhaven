// Copyright Justin Bishop, 2025

import Foundation

enum ShareHelpers {
  static func shareURL(with url: URL) -> URL {
    URL(string: "podhaven://share?url=\(url.absoluteString)")!
  }

  static func itunesLookupURL(for itunesID: String) -> URL {
    URL(string: "https://itunes.apple.com/lookup?id=\(itunesID)&entity=podcast")!
  }

  static func itunesURL(for itunesID: String, withTitle title: String) -> URL {
    URL(string: "https://podcasts.apple.com/us/podcast/\(title)/id\(itunesID)")!
  }
}
