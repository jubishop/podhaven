// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation

@testable import PodHaven

enum SearchViewModelTestHelpers {
  static var session: FakeDataFetchable {
    Container.shared.iTunesServiceSession() as! FakeDataFetchable
  }

  static func configureITunesResponses(emptyForSearchTerm: String? = nil) async {
    let topFeed = PreviewBundle.loadAsset(named: "top_feed", in: .iTunesResults)
    let topLookup = PreviewBundle.loadAsset(named: "top_lookup", in: .iTunesResults)
    let searchResults = PreviewBundle.loadAsset(named: "search_results", in: .iTunesResults)
    let emptyResults = Data(#"{"resultCount":0,"results":[]}"#.utf8)

    await session.setDefaultHandler { url in
      if url.path.contains("/rss/toppodcasts") {
        return (topFeed, URL.response(url))
      }

      if url.path.contains("/lookup") {
        return (topLookup, URL.response(url))
      }

      if url.path.contains("/search") {
        if let emptyForSearchTerm,
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let term = components.queryItems?.first(where: { $0.name == "term" })?.value,
          term.contains(emptyForSearchTerm)
        {
          return (emptyResults, URL.response(url))
        }
        return (searchResults, URL.response(url))
      }

      return (url.dataRepresentation, URL.response(url))
    }
  }
}
