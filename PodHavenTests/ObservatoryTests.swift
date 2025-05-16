// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import IdentifiedCollections
import Testing

@testable import PodHaven

@Suite("of Observatory tests", .container)
class ObservatoryTests {
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.repo) private var repo

  @Test("allPodcastsWithLatestEpisodeDates()")
  func testAllPodcastsWithLatestEpisodeDates() async throws {
    let podcast = try TestHelpers.unsavedPodcast()
    let newestUnfinishedEpisode = try TestHelpers.unsavedEpisode(
      pubDate: 10.minutesAgo,
      currentTime: CMTime.inSeconds(60),
      queueOrder: 0
    )
    let newestUnstartedEpisode = try TestHelpers.unsavedEpisode(
      pubDate: 20.minutesAgo,
      queueOrder: 1
    )
    let newestUnqueuedEpisode = try TestHelpers.unsavedEpisode(pubDate: 30.minutesAgo)
    let newerPlayedEpisode = try TestHelpers.unsavedEpisode(
      pubDate: 1.minutesAgo,
      completionDate: 1.minutesAgo
    )
    let olderUnplayedEpisode = try TestHelpers.unsavedEpisode(pubDate: 100.minutesAgo)
    try await repo.insertSeries(
      podcast,
      unsavedEpisodes: [
        newestUnfinishedEpisode,
        newestUnstartedEpisode,
        newestUnqueuedEpisode,
        newerPlayedEpisode,
        olderUnplayedEpisode,
      ]
    )

    let podcastAllPlayed = try TestHelpers.unsavedPodcast()
    let playedEpisode = try TestHelpers.unsavedEpisode(completionDate: 1.minutesAgo)
    try await repo.insertSeries(podcastAllPlayed, unsavedEpisodes: [playedEpisode])

    let allPodcastsWithLatestEpisodeDates =
      IdentifiedArray(
        uniqueElements: try await observatory.allPodcastsWithLatestEpisodeDates().get(),
        id: \.podcast.feedURL
      )
    #expect(allPodcastsWithLatestEpisodeDates.count == 2)

    let podcastWithLatestEpisodes = allPodcastsWithLatestEpisodeDates[id: podcast.feedURL]!
    #expect(
      podcastWithLatestEpisodes.maxUnfinishedEpisodePubDate!
        .approximatelyEquals(newestUnfinishedEpisode.pubDate)
    )
    #expect(
      podcastWithLatestEpisodes.maxUnstartedEpisodePubDate!
        .approximatelyEquals(newestUnstartedEpisode.pubDate)
    )
    #expect(
      podcastWithLatestEpisodes.maxUnqueuedEpisodePubDate!
        .approximatelyEquals(newestUnqueuedEpisode.pubDate)
    )

    let fetchedPodcastAllPlayed = allPodcastsWithLatestEpisodeDates[id: podcastAllPlayed.feedURL]!
    #expect(fetchedPodcastAllPlayed.maxUnfinishedEpisodePubDate == nil)
    #expect(fetchedPodcastAllPlayed.maxUnstartedEpisodePubDate == nil)
    #expect(fetchedPodcastAllPlayed.maxUnqueuedEpisodePubDate == nil)
  }

  @Test("queuedPodcastEpisodes()")
  func testQueuedPodcastEpisodes() async throws {
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

    let queuedEpisodes = try await observatory.queuedPodcastEpisodes().get()
    #expect(queuedEpisodes.count == 5)
    #expect(
      queuedEpisodes.map(\.episode.guid) == [
        "top", "midtop", "middle", "midbottom", "bottom",
      ]
    )
  }

  @Test("podcastEpisodes(Episode.completed, Episode.Columns.completionDate.desc)")
  func testCompletedPodcastEpisodes() async throws {
    let unsavedPodcast = try TestHelpers.unsavedPodcast()
    try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [
        TestHelpers.unsavedEpisode(
          guid: "top",
          pubDate: 15.minutesAgo,
          completionDate: 5.minutesAgo
        ),
        TestHelpers.unsavedEpisode(guid: "topUncompleted"),
        TestHelpers.unsavedEpisode(
          guid: "bottom",
          pubDate: 1.minutesAgo,
          completionDate: 15.minutesAgo
        ),
        TestHelpers.unsavedEpisode(guid: "bottomUncompleted"),
        TestHelpers.unsavedEpisode(
          guid: "middle",
          pubDate: 25.minutesAgo,
          completionDate: 10.minutesAgo
        ),
        TestHelpers.unsavedEpisode(guid: "middleUncompleted"),
      ]
    )

    let completedEpisodes =
      try await observatory.podcastEpisodes(
        filter: Episode.completed,
        order: Episode.Columns.completionDate.desc
      )
      .get()
    #expect(completedEpisodes.count == 3)
    #expect(completedEpisodes.map(\.episode.guid) == ["top", "middle", "bottom"])
  }
}
