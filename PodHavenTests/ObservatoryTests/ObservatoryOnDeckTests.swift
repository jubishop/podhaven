// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of Observatory onDeck tests", .container)
actor ObservatoryOnDeckTests {
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.repo) private var repo

  @Test("onDeck() returns correct OnDeck for an existing episode")
  func testOnDeckBasicFetch() async throws {
    let podcastImage = URL.valid()
    let episodeImage = URL.valid()
    let pubDate = 10.minutesAgo
    let duration = CMTime.seconds(300)
    let unsavedPodcast = try Create.unsavedPodcast(image: podcastImage)
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: [
          Create.unsavedEpisode(
            title: "Test Episode",
            pubDate: pubDate,
            duration: duration,
            image: episodeImage
          )
        ]
      )
    )

    let episode = series.episodes[0]
    let onDeck = try await observatory.onDeck(episode.id).get()

    let unwrapped = try #require(onDeck)
    #expect(unwrapped.id == episode.id)
    #expect(unwrapped.title == "Test Episode")
    #expect(unwrapped.pubDate.approximatelyEquals(pubDate))
    #expect(unwrapped.duration == duration)
    #expect(unwrapped.image == episodeImage)
    #expect(unwrapped.podcastImage == podcastImage)
    #expect(unwrapped.podcastTitle == unsavedPodcast.title)
    #expect(unwrapped.feedURL == unsavedPodcast.feedURL)
    #expect(unwrapped.currentTime == .zero)
    #expect(unwrapped.artwork == nil)
  }

  @Test("onDeck() returns nil for a non-existing episode")
  func testOnDeckNonExisting() async throws {
    let onDeck = try await observatory.onDeck(Episode.ID(rawValue: 999)).get()
    #expect(onDeck == nil)
  }

  @Test("onDeck() does not trigger on currentTime-only changes")
  func testOnDeckCurrentTimeDeduplication() async throws {
    let (episode, _, _) = try await Create.threePodcastEpisodes()

    let updateCount = Counter()

    Task {
      for try await _ in observatory.onDeck(episode.id) {
        await updateCount.increment()
      }
    }

    // Wait for initial emission
    try await updateCount.wait(for: 1)

    // currentTime changes should NOT cause new emissions
    _ = try await repo.updateCurrentTime(episode.id, currentTime: CMTime.seconds(30))
    _ = try await repo.updateCurrentTime(episode.id, currentTime: CMTime.seconds(60))
    _ = try await repo.updateCurrentTime(episode.id, currentTime: CMTime.seconds(90))

    // Counter should still be at 1 after currentTime-only changes
    try await Wait.until(
      maxAttempts: 50,
      { await updateCount.maxValue == 1 },
      { "Expected maxValue to remain 1, got \(await updateCount.maxValue)" }
    )
  }

  @Test("onDeck() triggers on relevant column changes")
  func testOnDeckRelevantChanges() async throws {
    let (episode, _, _) = try await Create.threePodcastEpisodes()

    let updateCount = Counter()

    Task {
      for try await _ in observatory.onDeck(episode.id) {
        await updateCount.increment()
      }
    }

    // Wait for initial emission
    try await updateCount.wait(for: 1)

    // markFinished changes finishDate, which IS a tracked column
    _ = try await repo.markFinished(episode.id)
    try await updateCount.wait(for: 2)
  }

  @Test("onDeck() emits nil when episode is deleted")
  func testOnDeckEpisodeDeletion() async throws {
    let (episode, _, _) = try await Create.threePodcastEpisodes()

    let observedOnDeck = ActorContainer<OnDeck?>()

    Task {
      for try await onDeck in observatory.onDeck(episode.id) {
        await observedOnDeck.set(onDeck)
      }
    }

    // Wait for initial non-nil emission
    try await Wait.until(
      { await observedOnDeck.value != nil },
      { "Expected non-nil OnDeck" }
    )

    // Delete the episode's podcast (cascades to episode)
    try await repo.deletePodcast(episode.episode.podcastID)

    // Should emit nil
    try await Wait.until(
      { await observedOnDeck.value == nil },
      { "Expected nil OnDeck after deletion" }
    )
  }
}
