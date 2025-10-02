// Copyright Justin Bishop, 2025

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("SearchService", .container)
final class SearchServiceTests {
  @DynamicInjected(\.searchServiceSession) private var searchServiceSession
  @DynamicInjected(\.searchService) private var searchService

  private var session: FakeDataFetchable { searchServiceSession as! FakeDataFetchable }

  // MARK: - Helpers

  private func searchURL(term: String) -> URL {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "itunes.apple.com"
    components.path = "/search"
    components.queryItems = [
      URLQueryItem(name: "term", value: term),
      URLQueryItem(name: "media", value: "podcast"),
      URLQueryItem(name: "entity", value: "podcast"),
      URLQueryItem(name: "limit", value: "100"),
    ]
    return components.url!
  }

  private func topFeedURL(country: String = "us", limit: Int, genreID: Int? = nil) -> URL {
    var pathComponents = ["", country, "rss", "toppodcasts", "limit=\(limit)"]
    if let genreID { pathComponents.append("genre=\(genreID)") }
    pathComponents.append("json")

    var components = URLComponents()
    components.scheme = "https"
    components.host = "itunes.apple.com"
    components.path = pathComponents.joined(separator: "/")
    return components.url!
  }

  private func lookupURL(ids: [String], country: String = "us") -> URL {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "itunes.apple.com"
    components.path = "/lookup"
    components.queryItems = [
      URLQueryItem(name: "id", value: ids.joined(separator: ",")),
      URLQueryItem(name: "entity", value: "podcast"),
      URLQueryItem(name: "country", value: country),
    ]
    return components.url!
  }

  // MARK: - Tests

  @Test("search podcasts returns filtered results")
  func testSearchPodcasts() async throws {
    let term = "technology"
    let data = PreviewBundle.loadAsset(named: "search_results", in: .iTunesResults)
    await session.respond(to: searchURL(term: term), data: data)

    let results = try await searchService.searchPodcasts(matching: term)
    #expect(results.count == 2)

    let podcasts = Array(results)
    #expect(podcasts.first?.title == "Lenny's Podcast: Product | Growth | Career")
    #expect(
      podcasts.first?.feedURL
        == FeedURL(URL(string: "https://api.substack.com/feed/podcast/10845.rss")!)
    )
    #expect(podcasts.last?.title == "The Daily")
  }

  @Test("top podcasts uses lookup to produce ordered results")
  func testTopPodcastsLookup() async throws {
    let feedData = PreviewBundle.loadAsset(named: "top_feed", in: .iTunesResults)
    let lookupData = PreviewBundle.loadAsset(named: "top_lookup", in: .iTunesResults)

    let feedURL = topFeedURL(limit: 5)
    await session.respond(to: feedURL, data: feedData)

    let lookupURL = lookupURL(ids: ["1627920305", "1439393088", "1234567890"])
    await session.respond(to: lookupURL, data: lookupData)

    let results = try await searchService.topPodcasts(limit: 5)
    #expect(results.count == 3)

    let podcasts = Array(results)
    #expect(podcasts[0].title == "Lenny's Podcast: Product | Growth | Career")
    #expect(podcasts[1].title == "The Daily")
    #expect(podcasts[2].title == "Science Friday")
  }

  @Test("top podcasts propagates failures")
  func testTopPodcastsFailure() async throws {
    let feedURL = topFeedURL(limit: 5)
    await session.respond(to: feedURL, error: URLError(.badServerResponse))

    await #expect(throws: SearchError.self) {
      _ = try await self.searchService.topPodcasts(limit: 5)
    }
  }

  @Test("search trims whitespace before querying")
  func testSearchTrimming() async throws {
    let term = " growth "
    let data = PreviewBundle.loadAsset(named: "search_results", in: .iTunesResults)
    await session.respond(
      to: searchURL(term: term.trimmingCharacters(in: .whitespacesAndNewlines)),
      data: data
    )

    let results = try await searchService.searchPodcasts(matching: term)
    #expect(results.count == 2)
    #expect(
      results.ids.contains(FeedURL(URL(string: "https://api.substack.com/feed/podcast/10845.rss")!))
    )
  }
}
