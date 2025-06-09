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
    let podcast = try Create.unsavedPodcast()
    let newestUnfinishedEpisode = try Create.unsavedEpisode(
      pubDate: 10.minutesAgo,
      currentTime: CMTime.inSeconds(60),
      queueOrder: 0
    )
    let newestUnstartedEpisode = try Create.unsavedEpisode(
      pubDate: 20.minutesAgo,
      queueOrder: 1
    )
    let newestUnqueuedEpisode = try Create.unsavedEpisode(pubDate: 30.minutesAgo)
    let newerPlayedEpisode = try Create.unsavedEpisode(
      pubDate: 1.minutesAgo,
      completionDate: 1.minutesAgo
    )
    let olderUnplayedEpisode = try Create.unsavedEpisode(pubDate: 100.minutesAgo)
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

    let podcastAllPlayed = try Create.unsavedPodcast()
    let playedEpisode = try Create.unsavedEpisode(completionDate: 1.minutesAgo)
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
    let unsavedPodcast = try Create.unsavedPodcast()
    try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [
        Create.unsavedEpisode(guid: "top", queueOrder: 0),
        Create.unsavedEpisode(guid: "bottom", queueOrder: 4),
        Create.unsavedEpisode(guid: "midtop", queueOrder: 1),
        Create.unsavedEpisode(guid: "middle", queueOrder: 2),
        Create.unsavedEpisode(guid: "midbottom", queueOrder: 3),
        Create.unsavedEpisode(guid: "unqbottom"),
        Create.unsavedEpisode(guid: "unqmiddle"),
        Create.unsavedEpisode(guid: "unqtop"),
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
    let unsavedPodcast = try Create.unsavedPodcast()
    try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [
        Create.unsavedEpisode(
          guid: "top",
          pubDate: 15.minutesAgo,
          completionDate: 5.minutesAgo
        ),
        Create.unsavedEpisode(guid: "topUncompleted"),
        Create.unsavedEpisode(
          guid: "bottom",
          pubDate: 1.minutesAgo,
          completionDate: 15.minutesAgo
        ),
        Create.unsavedEpisode(guid: "bottomUncompleted"),
        Create.unsavedEpisode(
          guid: "middle",
          pubDate: 25.minutesAgo,
          completionDate: 10.minutesAgo
        ),
        Create.unsavedEpisode(guid: "middleUncompleted"),
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
