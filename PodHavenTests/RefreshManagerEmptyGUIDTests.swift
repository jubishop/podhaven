// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("of RefreshManager empty GUID tests", .container)
actor RefreshManagerEmptyGUIDTests {
  @DynamicInjected(\.podcastFeedSession) private var podcastFeedSession
  @DynamicInjected(\.refreshManager) private var refreshManager
  @DynamicInjected(\.repo) private var repo

  private var session: FakeDataFetchable {
    podcastFeedSession as! FakeDataFetchable
  }

  private static let feedURL = FeedURL(URL(string: "https://example.com/empty-guid.rss")!)

  @Test("refreshSeries gives a new episode with an empty guid its own row")
  func newEpisodeWithEmptyGUIDGetsItsOwnRow() async throws {
    let podcastFeed = try await PodcastFeed.parse(Self.feed(episodes: 1...2), from: Self.feedURL)
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try podcastFeed.toUnsavedPodcast(),
        unsavedEpisodes: podcastFeed.toUnsavedEpisodes()
      )
    )
    #expect(Set(series.episodes.map(\.mediaURL)) == Set((1...2).map(Self.mediaURL)))
    let playedEpisode = try #require(series.episodes.first { $0.mediaURL == Self.mediaURL(2) })
    try await repo.markFinished(playedEpisode.id)

    await session.respond(to: Self.feedURL.rawValue, data: Self.feed(episodes: 1...3))
    try await refreshManager.refreshSeries(podcast: series.podcast)

    let updatedSeries = try #require(try await repo.podcastSeries(series.podcast.id))
    #expect(Set(updatedSeries.episodes.map(\.mediaURL)) == Set((1...3).map(Self.mediaURL)))
    let newEpisode = try #require(
      updatedSeries.episodes.first { $0.mediaURL == Self.mediaURL(3) }
    )
    #expect(newEpisode.id != playedEpisode.id)
    #expect(newEpisode.finishDate == nil)
    let refreshedPlayedEpisode = try #require(try await repo.episode(playedEpisode.id))
    #expect(refreshedPlayedEpisode.mediaURL == Self.mediaURL(2))
    #expect(refreshedPlayedEpisode.finishDate != nil)
  }

  @Test("refreshSeries repairs an episode stored with an empty guid")
  func storedEpisodeWithEmptyGUIDIsRepaired() async throws {
    let podcastFeed = try await PodcastFeed.parse(Self.feed(episodes: 1...3), from: Self.feedURL)
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try podcastFeed.toUnsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(
            guid: GUID(""),
            mediaURL: Self.mediaURL(2),
            title: "Episode 2",
            finishDate: Date()
          )
        ]
      )
    )
    let storedEpisode = try #require(series.episodes.first)

    await session.respond(to: Self.feedURL.rawValue, data: Self.feed(episodes: 1...3))
    try await refreshManager.refreshSeries(podcast: series.podcast)

    let updatedSeries = try #require(try await repo.podcastSeries(series.podcast.id))
    #expect(
      Set(updatedSeries.episodes.map(\.guid))
        == Set((1...3).map { GUID(Self.mediaURL($0).rawValue.absoluteString) })
    )
    #expect(
      updatedSeries.episodes.filter { $0.finishDate != nil }.map(\.id) == [storedEpisode.id]
    )
    let repairedEpisode = try #require(try await repo.episode(storedEpisode.id))
    #expect(repairedEpisode.guid == GUID(Self.mediaURL(2).rawValue.absoluteString))
    #expect(repairedEpisode.mediaURL == Self.mediaURL(2))
  }

  private static func mediaURL(_ episode: Int) -> MediaURL {
    MediaURL(URL(string: "https://example.com/episode-\(episode).mp3")!)
  }

  private static func feed(episodes: ClosedRange<Int>) -> Data {
    let items = episodes.map { episode in
      """
      <item>
        <title>Episode \(episode)</title>
        <guid isPermaLink="false"/>
        <pubDate>2024-01-0\(episode)T10:00:00Z</pubDate>
        <enclosure url="\(mediaURL(episode).rawValue.absoluteString)" type="audio/mpeg"/>
      </item>
      """
    }
    return Data(
      """
      <?xml version="1.0"?>
      <rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" version="2.0">
        <channel>
          <title>Empty GUIDs</title>
          <description>Feed whose items have empty guids</description>
          <itunes:image href="https://example.com/art.jpg"/>
          \(items.joined(separator: "\n"))
        </channel>
      </rss>
      """
      .utf8
    )
  }
}
