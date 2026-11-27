// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("of RefreshManager crossed GUID and media URL tests", .container)
actor RefreshManagerCrossedIdentityTests {
  @DynamicInjected(\.podcastFeedSession) private var podcastFeedSession
  @DynamicInjected(\.refreshManager) private var refreshManager
  @DynamicInjected(\.repo) private var repo

  private var session: FakeDataFetchable {
    podcastFeedSession as! FakeDataFetchable
  }

  private static let feedURL = FeedURL(URL(string: "https://example.com/crossed.rss")!)

  private struct Item {
    let guid: String
    let episode: Int
    var description: String? = nil
  }

  @Test("refreshSeries keeps each row when stored episodes swap GUIDs")
  func swappedGUIDsKeepEachRow() async throws {
    let series = try await insertSeries([Item(guid: "a", episode: 1), Item(guid: "b", episode: 2)])
    let first = try #require(series.episodes.first { $0.mediaURL == Self.mediaURL(1) })
    let second = try #require(series.episodes.first { $0.mediaURL == Self.mediaURL(2) })
    try await repo.markFinished(first.id)

    try await refresh(
      series.podcast,
      with: [
        Item(guid: "b", episode: 1), Item(guid: "a", episode: 2), Item(guid: "c", episode: 3),
      ]
    )

    let swappedFirst = try #require(try await repo.episode(first.id))
    #expect(swappedFirst.guid == GUID("b"))
    #expect(swappedFirst.mediaURL == Self.mediaURL(1))
    #expect(swappedFirst.finishDate != nil)
    let swappedSecond = try #require(try await repo.episode(second.id))
    #expect(swappedSecond.guid == GUID("a"))
    #expect(swappedSecond.mediaURL == Self.mediaURL(2))
    #expect(swappedSecond.finishDate == nil)
    let episodes = try #require(try await repo.podcastSeries(series.podcast.id)).episodes
    #expect(episodes.count == 3)
    #expect(episodes.contains { $0.guid == GUID("c") && $0.mediaURL == Self.mediaURL(3) })
  }

  @Test("refreshSeries keeps a departed episode whose GUID another item takes")
  func departedEpisodeKeepsItsRowUnderItsMediaURL() async throws {
    let series = try await insertSeries([Item(guid: "a", episode: 1), Item(guid: "b", episode: 2)])
    let departed = try #require(series.episodes.first { $0.mediaURL == Self.mediaURL(1) })
    let remaining = try #require(series.episodes.first { $0.mediaURL == Self.mediaURL(2) })
    try await repo.markFinished(departed.id)

    try await refresh(series.podcast, with: [Item(guid: "a", episode: 2)])

    let claimed = try #require(try await repo.episode(remaining.id))
    #expect(claimed.guid == GUID("a"))
    #expect(claimed.mediaURL == Self.mediaURL(2))
    let kept = try #require(try await repo.episode(departed.id))
    #expect(kept.guid == GUID(Self.mediaURL(1).rawValue.absoluteString))
    #expect(kept.mediaURL == Self.mediaURL(1))
    #expect(kept.finishDate != nil)
  }

  @Test("refreshSeries stores both items when one matches a row by media URL, another by GUID")
  func mediaURLMatchWinsTheRow() async throws {
    let series = try await insertSeries([Item(guid: "a", episode: 1, description: "Stored notes")])
    let stored = try #require(series.episodes.first)

    try await refresh(
      series.podcast,
      with: [Item(guid: "x", episode: 1), Item(guid: "a", episode: 2)]
    )

    let episodes = try #require(try await repo.podcastSeries(series.podcast.id)).episodes
    #expect(episodes.count == 2)
    let mediaURLMatch = try #require(try await repo.episode(stored.id))
    #expect(mediaURLMatch.guid == GUID("x"))
    #expect(mediaURLMatch.mediaURL == Self.mediaURL(1))
    #expect(mediaURLMatch.description == "Stored notes")
    let newEpisode = try #require(episodes.first { $0.id != stored.id })
    #expect(newEpisode.guid == GUID("a"))
    #expect(newEpisode.mediaURL == Self.mediaURL(2))
    #expect(newEpisode.description == nil)
  }

  private func insertSeries(_ items: [Item]) async throws -> PodcastSeries {
    let podcastFeed = try await PodcastFeed.parse(Self.feed(items), from: Self.feedURL)
    return try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try podcastFeed.toUnsavedPodcast(),
        unsavedEpisodes: podcastFeed.toUnsavedEpisodes()
      )
    )
  }

  private func refresh(_ podcast: Podcast, with items: [Item]) async throws {
    await session.respond(to: Self.feedURL.rawValue, data: Self.feed(items))
    try await refreshManager.refreshSeries(podcast: podcast)
  }

  private static func mediaURL(_ episode: Int) -> MediaURL {
    MediaURL(URL(string: "https://example.com/episode-\(episode).mp3")!)
  }

  private static func feed(_ items: [Item]) -> Data {
    let items = items.map { item in
      let description =
        if let description = item.description {
          "<description>\(description)</description>"
        } else {
          ""
        }
      return """
        <item>
          <title>Episode \(item.episode)</title>
          <guid isPermaLink="false">\(item.guid)</guid>
          <pubDate>2024-01-0\(item.episode)T10:00:00Z</pubDate>
          \(description)
          <enclosure url="\(mediaURL(item.episode).rawValue.absoluteString)" type="audio/mpeg"/>
        </item>
        """
    }
    return Data(
      """
      <?xml version="1.0"?>
      <rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" version="2.0">
        <channel>
          <title>Crossed Identities</title>
          <description>Feed whose items trade GUIDs and media URLs</description>
          <itunes:image href="https://example.com/art.jpg"/>
          \(items.joined(separator: "\n"))
        </channel>
      </rss>
      """
      .utf8
    )
  }
}
