// Copyright Justin Bishop, 2025

import Foundation
import GRDB
import IdentifiedCollections
import Testing

@testable import PodHaven

@Suite("of Observatory tests")
actor ObservatoryTests {
  private let repo: Repo
  private let observatory: Observatory

  init() {
    self.repo = .inMemory()
    self.observatory = .initForTest(repo)
  }

  @Test("allPodcastsWithLatestEpisode()")
  func testAllWithLatestEpisode() async throws {
    let podcast = try TestHelpers.unsavedPodcast()
    let newestUnplayedEpisode = try TestHelpers.unsavedEpisode(
      pubDate: 10.minutesAgo,
      completed: false
    )
    let newerPlayedEpisode = try TestHelpers.unsavedEpisode(
      pubDate: 5.minutesAgo,
      completed: true
    )
    let olderUnplayedEpisode = try TestHelpers.unsavedEpisode(
      pubDate: 15.minutesAgo,
      completed: false
    )
    try await repo.insertSeries(
      podcast,
      unsavedEpisodes: [
        newestUnplayedEpisode,
        newerPlayedEpisode,
        olderUnplayedEpisode,
      ]
    )

    let podcastAllPlayed = try TestHelpers.unsavedPodcast()
    let playedEpisode = try TestHelpers.unsavedEpisode(completed: true)
    try await repo.insertSeries(podcastAllPlayed, unsavedEpisodes: [playedEpisode])

    let allPodcastsWithLatestEpisodeDate =
      IdentifiedArray(
        uniqueElements: try await observatory.allPodcastsWithLatestEpisodeDate().first(),
        id: \.podcast.feedURL
      )

    #expect(allPodcastsWithLatestEpisodeDate.count == 2)
    let podcastWithLatestEpisode = allPodcastsWithLatestEpisodeDate[id: podcast.feedURL]!
    #expect(
      podcastWithLatestEpisode.latestEpisodeDate!.approximatelyEquals(newestUnplayedEpisode.pubDate)
    )

    let fetchedPodcastAllPlayed = allPodcastsWithLatestEpisodeDate[id: podcastAllPlayed.feedURL]!
    #expect(fetchedPodcastAllPlayed.latestEpisodeDate == nil)
  }

  @Test("queuedEpisodes()")
  func testQueuedEpisodes() async throws {
    let unsavedPodcast = try TestHelpers.unsavedPodcast()
    try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [
        TestHelpers.unsavedEpisode(guid: "top", queueOrder: 0),
        TestHelpers.unsavedEpisode(guid: "bottom", queueOrder: 4),
        TestHelpers.unsavedEpisode(guid: "midtop", queueOrder: 1),
        TestHelpers.unsavedEpisode(guid: "middle", queueOrder: 2),
        TestHelpers.unsavedEpisode(guid: "midbottom", queueOrder: 3),
        TestHelpers.unsavedEpisode(guid: "unqbottom"),
        TestHelpers.unsavedEpisode(guid: "unqmiddle"),
        TestHelpers.unsavedEpisode(guid: "unqtop"),
      ]
    )

    let queuedEpisodes = try await observatory.queuedEpisodes().first()
    #expect(queuedEpisodes.count == 5)
    #expect(
      queuedEpisodes.map(\.episode.guid) == [
        "top", "midtop", "middle", "midbottom", "bottom",
      ]
    )
  }
}
