// Copyright Justin Bishop, 2025

import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of Observatory queue tests", .container)
actor ObservatoryQueueTests {
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

}
