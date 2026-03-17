// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of Observatory queue tests", .container)
actor QueueTests {
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.repo) private var repo

  @Test("queuedPodcastEpisodes()")
  func testQueuedPodcastEpisodes() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
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
    )

    let queuedEpisodes = try await observatory.queuedPodcastEpisodes().get()
    #expect(queuedEpisodes.count == 5)
    #expect(
      queuedEpisodes.map(\.episode.guid) == [
        "top", "midtop", "middle", "midbottom", "bottom",
      ]
    )
  }

  @Test("podcastEpisodes(Episode.finished, Episode.Columns.finishDate.desc)")
  func testFinishedPodcastEpisodes() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: [
          Create.unsavedEpisode(
            guid: "top",
            pubDate: 15.minutesAgo,
            finishDate: 5.minutesAgo
          ),
          Create.unsavedEpisode(guid: "topUnfinished"),
          Create.unsavedEpisode(
            guid: "bottom",
            pubDate: 1.minutesAgo,
            finishDate: 15.minutesAgo
          ),
          Create.unsavedEpisode(guid: "bottomUnfinished"),
          Create.unsavedEpisode(
            guid: "middle",
            pubDate: 25.minutesAgo,
            finishDate: 10.minutesAgo
          ),
          Create.unsavedEpisode(guid: "middleUnfinished"),
        ]
      )
    )

    let finishedEpisodes =
      try await observatory.podcastEpisodes(
        filter: Episode.finished,
        order: Episode.Columns.finishDate.desc
      )
      .get()
    #expect(finishedEpisodes.count == 3)
    #expect(finishedEpisodes.map(\.episode.guid) == ["top", "middle", "bottom"])
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

  // MARK: - queueWidgetEpisodes()

  @Test("queueWidgetEpisodes() returns only queued episodes ordered by queueOrder")
  func testQueueWidgetEpisodes() async throws {
    let podcastImage = URL.valid()
    let unsavedPodcast = try Create.unsavedPodcast(image: podcastImage)
    let episodeImage = URL.valid()
    let pubDate = 10.minutesAgo
    let duration = CMTime.seconds(300)
    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: [
          Create.unsavedEpisode(
            title: "First",
            pubDate: pubDate,
            duration: duration,
            image: episodeImage,
            queueOrder: 0
          ),
          Create.unsavedEpisode(title: "Fifth", queueOrder: 4),
          Create.unsavedEpisode(title: "Second", queueOrder: 1),
          Create.unsavedEpisode(title: "Third", queueOrder: 2),
          Create.unsavedEpisode(title: "Fourth", queueOrder: 3),
          Create.unsavedEpisode(title: "Unqueued A"),
          Create.unsavedEpisode(title: "Unqueued B"),
          Create.unsavedEpisode(title: "Unqueued C"),
        ]
      )
    )

    let episodes = try await observatory.queueWidgetEpisodes().get()
    #expect(episodes.count == 5)
    #expect(episodes.map(\.title) == ["First", "Second", "Third", "Fourth", "Fifth"])

    let first = episodes[0]
    #expect(first.title == "First")
    #expect(first.pubDate.approximatelyEquals(pubDate))
    #expect(first.duration == duration)
    #expect(first.episodeImage == episodeImage)
    #expect(first.podcastImage == podcastImage)
    #expect(first.image == episodeImage)

    let second = episodes[1]
    #expect(second.podcastImage == podcastImage)
    #expect(second.image == podcastImage)
  }

  @Test("queueWidgetEpisodes() deduplicates irrelevant column changes")
  func testQueueWidgetEpisodesDeduplication() async throws {
    let (episode1, episode2, _) = try await Create.threePodcastEpisodes()

    let updateCount = Counter()

    Task {
      for try await queuedEpisodes in observatory.queueWidgetEpisodes() {
        await updateCount(queuedEpisodes.count)
      }
    }

    try await queue.unshift(episode1.id)
    try await updateCount.wait(for: 1)

    try await queue.unshift(episode2.id)
    try await updateCount.wait(for: 2)

    // Irrelevant column changes should not cause emissions
    _ = try await repo.updateCurrentTime(episode1.id, currentTime: CMTime.seconds(60))
    _ = try await repo.updateCachedFilename(episode1.id, cachedFilename: "test.mp3")
    _ = try await repo.markFinished(episode1.id)

    // Counter should still be at 2 after irrelevant changes
    try await Wait.until(
      maxAttempts: 50,
      { await updateCount.maxValue == 2 },
      { "Expected maxValue to remain 2, got \(await updateCount.maxValue)" }
    )

    // Real change should still propagate
    try await queue.dequeue(episode2.id)
    try await updateCount.wait(for: 1)
  }
}
