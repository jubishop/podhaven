// Copyright Justin Bishop, 2025

import FactoryKit
import FactoryTesting
import Foundation
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
          Create.unsavedEpisode(guid: "top", title: "top", queueOrder: 0),
          Create.unsavedEpisode(guid: "bottom", title: "bottom", queueOrder: 4),
          Create.unsavedEpisode(guid: "midtop", title: "midtop", queueOrder: 1),
          Create.unsavedEpisode(guid: "middle", title: "middle", queueOrder: 2),
          Create.unsavedEpisode(guid: "midbottom", title: "midbottom", queueOrder: 3),
          Create.unsavedEpisode(guid: "unqbottom", title: "unqbottom"),
          Create.unsavedEpisode(guid: "unqmiddle", title: "unqmiddle"),
          Create.unsavedEpisode(guid: "unqtop", title: "unqtop"),
        ]
      )
    )

    let queuedEpisodes = try await observatory.queuedPodcastEpisodes().get()
    #expect(queuedEpisodes.count == 5)
    #expect(
      queuedEpisodes.map(\.title) == [
        "top", "midtop", "middle", "midbottom", "bottom",
      ]
    )
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
