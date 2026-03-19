// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing
import UIKit

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
          try Create.unsavedEpisode(
            title: "Test Episode",
            pubDate: pubDate,
            duration: duration,
            image: episodeImage
          )
        ]
      )
    )

    let episode = series.episodes[0]
    let onDeck: OnDeck? = try await observatory.episode(episode.id).get()

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
    let onDeck: OnDeck? = try await observatory.episode(Episode.ID(rawValue: 999)).get()
    #expect(onDeck == nil)
  }

  @Test("init(row:) populates all fields from database")
  func testRowInitAllFields() async throws {
    let podcastImage = URL.valid()
    let episodeImage = URL.valid()
    let feedURL = FeedURL(URL.valid())
    let pubDate = 10.minutesAgo
    let finishDate = 5.minutesAgo
    let duration = CMTime.seconds(3600)
    let description = "0:00 Intro\n5:00 Chapter One\n30:00 Chapter Two"

    let unsavedPodcast = try Create.unsavedPodcast(
      feedURL: feedURL,
      image: podcastImage,
      defaultPlaybackRate: 1.5
    )
    let unsavedEpisode = try Create.unsavedEpisode(
      title: "Row Init Episode",
      pubDate: pubDate,
      duration: duration,
      description: description,
      image: episodeImage,
      finishDate: finishDate,
      currentTime: CMTime.seconds(120),
      queueOrder: 3,
      queueDate: Date(),
      cachedFilename: "test.mp3",
      saveInCache: true
    )
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: [unsavedEpisode]
      )
    )

    let episode = series.episodes[0]
    let onDeck: OnDeck = try #require(try await observatory.episode(episode.id).get())

    // Episode fields
    #expect(onDeck.id == episode.id)
    #expect(onDeck.mediaURL == unsavedEpisode.mediaURL)
    #expect(onDeck.title == "Row Init Episode")
    #expect(onDeck.pubDate.approximatelyEquals(pubDate))
    #expect(onDeck.duration == duration)
    let unwrappedFinish = try #require(onDeck.finishDate)
    #expect(unwrappedFinish.approximatelyEquals(finishDate))
    #expect(onDeck.queueOrder == 3)
    #expect(onDeck.cacheStatus == .cached)
    #expect(onDeck.saveInCache == true)

    // Podcast fields
    #expect(onDeck.podcastImage == podcastImage)
    #expect(onDeck.podcastTitle == unsavedPodcast.title)
    #expect(onDeck.feedURL == feedURL)
    #expect(onDeck.defaultPlaybackRate == 1.5)

    // Computed fields
    #expect(onDeck.image == episodeImage)
    #expect(onDeck.mediaGUID.guid == unsavedEpisode.guid)
    #expect(onDeck.mediaGUID.mediaURL == unsavedEpisode.mediaURL)
    #expect(onDeck.chapters?.count == 2)

    // In-memory fields are not read from the DB row
    #expect(onDeck.artwork == nil)
    #expect(onDeck.currentTime == .zero)
  }

  @Test("init(from:) populates all fields from PodcastEpisode")
  func testConvenienceInitAllFields() async throws {
    let podcastImage = URL.valid()
    let episodeImage = URL.valid()
    let feedURL = FeedURL(URL.valid())
    let pubDate = 10.minutesAgo
    let finishDate = 5.minutesAgo
    let duration = CMTime.seconds(3600)
    let description = "0:00 Intro\n5:00 Chapter One\n30:00 Chapter Two"

    let unsavedPodcast = try Create.unsavedPodcast(
      feedURL: feedURL,
      image: podcastImage,
      defaultPlaybackRate: 1.5
    )
    let unsavedEpisode = try Create.unsavedEpisode(
      title: "Convenience Init Episode",
      pubDate: pubDate,
      duration: duration,
      description: description,
      image: episodeImage,
      finishDate: finishDate,
      currentTime: CMTime.seconds(45),
      queueOrder: 2,
      queueDate: Date(),
      cachedFilename: "cached.mp3",
      saveInCache: true
    )
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: [unsavedEpisode]
      )
    )

    let episode = series.episodes[0]
    let optionalEpisode: PodcastEpisode? = try await observatory.episode(episode.id).get()
    let podcastEpisode = try #require(optionalEpisode)
    let onDeck = OnDeck(from: podcastEpisode)

    // Episode fields
    #expect(onDeck.id == podcastEpisode.id)
    #expect(onDeck.mediaURL == podcastEpisode.episode.unsaved.mediaURL)
    #expect(onDeck.title == podcastEpisode.title)
    #expect(onDeck.pubDate == podcastEpisode.pubDate)
    #expect(onDeck.duration == podcastEpisode.duration)
    #expect(onDeck.finishDate == podcastEpisode.finishDate)
    #expect(onDeck.queueOrder == podcastEpisode.queueOrder)
    #expect(onDeck.cacheStatus == podcastEpisode.cacheStatus)
    #expect(onDeck.saveInCache == podcastEpisode.saveInCache)

    // Podcast fields
    #expect(onDeck.podcastImage == podcastEpisode.podcastImage)
    #expect(onDeck.podcastTitle == podcastEpisode.podcastTitle)
    #expect(onDeck.feedURL == podcastEpisode.feedURL)
    #expect(onDeck.defaultPlaybackRate == podcastEpisode.podcast.defaultPlaybackRate)

    // Computed fields
    #expect(onDeck.image == podcastEpisode.image)
    #expect(onDeck.mediaGUID == podcastEpisode.mediaGUID)
    #expect(onDeck.chapters == podcastEpisode.chapters)

    // currentTime should come from PodcastEpisode, artwork always starts nil
    #expect(onDeck.currentTime == podcastEpisode.currentTime)
    #expect(onDeck.currentTime == CMTime.seconds(45))
    #expect(onDeck.artwork == nil)
  }

  @Test("equality and hash ignore artwork and currentTime")
  func testEqualityAndHashIgnoreInMemoryFields() async throws {
    let (episode, _, _) = try await Create.threePodcastEpisodes()
    let optionalEpisode: PodcastEpisode? = try await observatory.episode(episode.id).get()
    let podcastEpisode = try #require(optionalEpisode)

    let a = OnDeck(from: podcastEpisode)
    var b = OnDeck(from: podcastEpisode)
    b.artwork = UIImage()
    b.currentTime = CMTime.seconds(99)

    #expect(a == b)
    #expect(a.hashValue == b.hashValue)
  }

  @Test("onDeck() does not trigger on currentTime-only changes")
  func testOnDeckCurrentTimeDeduplication() async throws {
    let (episode, _, _) = try await Create.threePodcastEpisodes()

    let updateCount = Counter()

    Task {
      for try await _: OnDeck? in observatory.episode(episode.id) {
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
      for try await _: OnDeck? in observatory.episode(episode.id) {
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

    let receivedNonNil = ActorContainer<Bool>()
    let receivedNil = ActorContainer<Bool>()

    Task {
      for try await onDeck: OnDeck? in observatory.episode(episode.id) {
        if onDeck != nil {
          await receivedNonNil.set(true)
        } else {
          await receivedNil.set(true)
        }
      }
    }

    // Wait for initial non-nil emission
    try await receivedNonNil.waitForItem()

    // Delete the episode's podcast (cascades to episode)
    try await repo.deletePodcast(episode.episode.podcastID)

    // Should emit nil
    try await receivedNil.waitForItem()
  }
}
