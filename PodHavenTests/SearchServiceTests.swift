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

  // MARK: - Tests

  @Test("search podcasts returns filtered results")
  func testSearchPodcasts() async throws {
    let term = "technology"
    let data = PreviewBundle.loadAsset(named: "search_results", in: .iTunesResults)
    await session.respond(to: ITunesURL.searchRequest(for: term, limit: 50).url!, data: data)

    let results = try await searchService.searchPodcasts(matching: term, limit: 50)
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

    let feedURL = ITunesURL.topPodcastsRequest(limit: 5).url!
    await session.respond(to: feedURL, data: feedData)

    let lookupURL =
      ITunesURL.lookupRequest(podcastIDs: [
        ITunesPodcastID(1627920305), ITunesPodcastID(1439393088), ITunesPodcastID(1234567890),
      ])
      .url!
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
    let feedURL = ITunesURL.topPodcastsRequest(limit: 5).url!
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
      to:
        ITunesURL.searchRequest(
          for: term.trimmingCharacters(in: .whitespacesAndNewlines),
          limit: 50
        )
        .url!,
      data: data
    )

    let results = try await searchService.searchPodcasts(matching: term, limit: 50)
    #expect(results.count == 2)
    #expect(
      results.ids.contains(FeedURL(URL(string: "https://api.substack.com/feed/podcast/10845.rss")!))
    )
  }
}
