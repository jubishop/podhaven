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
actor ObservatoryTests {
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.repo) private var repo

  @Test("allPodcastsWithLatestEpisodeDates()")
  func testAllPodcastsWithLatestEpisodeDates() async throws {
    let podcast = try Create.unsavedPodcast()
    let newestUnfinishedEpisode = try Create.unsavedEpisode(
      pubDate: 10.minutesAgo,
      currentTime: CMTime.seconds(60),
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

  @Test("podcastSeries(FeedURL)")
  func testPodcastSeries() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    try await repo.insertSeries(unsavedPodcast)

    let series = try await observatory.podcastSeries(unsavedPodcast.feedURL).get()
    #expect(series?.podcast.feedURL == unsavedPodcast.feedURL)
  }

  @Test("queuedPodcastEpisodes AsyncSequence receives all updates")
  func testQueuedPodcastEpisodesAsyncSequence() async throws {
    let (episode1, episode2, episode3) = try await Create.threePodcastEpisodes()

    let updateCount = Counter()

    Task {
      for try await queuedEpisodes in observatory.queuedPodcastEpisodes() {
        await updateCount(queuedEpisodes.count)
      }
    }

    try await queue.unshift(episode1.id)
    try await updateCount.wait(for: 1)

    try await queue.unshift(episode2.id)
    try await updateCount.wait(for: 2)

    try await queue.unshift(episode3.id)
    try await updateCount.wait(for: 3)

    try await queue.dequeue(episode2.id)
    try await updateCount.wait(for: 2)

    try await queue.dequeue(episode3.id)
    try await updateCount.wait(for: 1)

    try await queue.dequeue(episode1.id)
    try await updateCount.wait(for: 0)
  }

  @Test("maxQueuePosition()")
  func testMaxQueuePosition() async throws {
    // Test when no episodes are queued
    var maxPosition = try await observatory.maxQueuePosition().get()
    #expect(maxPosition == nil)

    let (episode1, episode2, episode3) = try await Create.threePodcastEpisodes()

    // Add episodes to queue using queue methods
    try await queue.unshift(episode1.id)  // Position 0
    maxPosition = try await observatory.maxQueuePosition().get()
    #expect(maxPosition == 0)

    try await queue.append(episode2.id)  // Position 1
    maxPosition = try await observatory.maxQueuePosition().get()
    #expect(maxPosition == 1)

    try await queue.append(episode3.id)  // Position 2
    maxPosition = try await observatory.maxQueuePosition().get()
    #expect(maxPosition == 2)
  }
}
