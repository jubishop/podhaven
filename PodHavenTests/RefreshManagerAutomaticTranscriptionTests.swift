// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Semaphore
import Testing

@testable import PodHaven

@Suite("of RefreshManager automatic transcription tests", .container)
actor RefreshManagerAutomaticTranscriptionTests {
  @DynamicInjected(\.podcastFeedSession) private var podcastFeedSession
  @DynamicInjected(\.refreshManager) private var refreshManager
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.transcriptionQueue) private var transcriptionQueue

  private var session: FakeDataFetchable {
    podcastFeedSession as! FakeDataFetchable
  }

  @Test("refreshSeries queues newly fetched episodes for automatic transcription")
  func refreshSeriesQueuesAutomaticTranscription() async throws {
    await transcriptionQueue.waitUntilLoaded()
    let podcastSeries = try await NewEpisodeFeed.insertSeries(
      feedURL: URL(string: "https://example.com/automatic-transcription.rss")!,
      alwaysTranscribeNewEpisodes: true
    )
    let existingEpisodeIDs = Set(podcastSeries.episodes.map(\.id))
    await session.respond(to: podcastSeries.podcast.feedURL.rawValue, data: NewEpisodeFeed.data)

    try await refreshManager.refreshSeries(podcast: podcastSeries.podcast)

    let updatedSeries = try #require(try await repo.podcastSeries(podcastSeries.id))
    let newEpisode = try #require(
      updatedSeries.episodes.first { !existingEpisodeIDs.contains($0.id) }
    )
    #expect(transcriptionQueue.episodeIDs == [newEpisode.id])
  }

  @Test("refreshSeries finishes automatic queue admission after caller cancellation")
  func refreshSeriesFinishesAutomaticTranscriptionAdmissionAfterCancellation() async throws {
    let enqueueStarted = AsyncSemaphore(value: 0)
    let enqueueRelease = AsyncSemaphore(value: 0)
    let store = FakeTranscriptionQueueStore(
      beforeEnqueue: { _ in
        enqueueStarted.signal()
        await enqueueRelease.wait()
        try Task.checkCancellation()
      }
    )
    Container.shared.transcriptionQueueStore.register { store }
    Container.shared.transcriptionQueue.reset(.scope)
    Container.shared.transcriptionProcessor.reset(.scope)
    Container.shared.refreshManager.reset(.scope)
    let transcriptionQueue = Container.shared.transcriptionQueue()
    let refreshManager = Container.shared.refreshManager()
    await transcriptionQueue.waitUntilLoaded()

    let podcastSeries = try await NewEpisodeFeed.insertSeries(
      feedURL: URL(string: "https://example.com/cancelled-automatic-transcription.rss")!,
      alwaysTranscribeNewEpisodes: true
    )
    let existingEpisodeIDs = Set(podcastSeries.episodes.map(\.id))
    await session.respond(to: podcastSeries.podcast.feedURL.rawValue, data: NewEpisodeFeed.data)

    let refreshTask = Task {
      try await refreshManager.refreshSeries(podcast: podcastSeries.podcast)
    }
    defer {
      refreshTask.cancel()
      enqueueRelease.signal()
    }
    await enqueueStarted.wait()
    refreshTask.cancel()
    enqueueRelease.signal()
    try await refreshTask.value

    let updatedSeries = try #require(try await repo.podcastSeries(podcastSeries.id))
    let newEpisode = try #require(
      updatedSeries.episodes.first { !existingEpisodeIDs.contains($0.id) }
    )
    #expect(transcriptionQueue.episodeIDs == [newEpisode.id])
  }

  @Test("refreshSeries drops automatic transcription when the queue is full")
  func refreshSeriesDropsAutomaticTranscriptionAtCapacity() async throws {
    Container.shared.userSettings().$maxTranscriptionQueueLength.new(10)
    await transcriptionQueue.waitUntilLoaded()
    let fillerSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: try (0..<10)
          .map {
            try Create.unsavedEpisode(
              guid: GUID("automatic-transcription-filler-\($0)"),
              mediaURL: MediaURL(
                URL(string: "https://example.com/automatic-transcription-filler-\($0).mp3")!
              )
            )
          }
      )
    )
    let fillerEpisodeIDs = fillerSeries.episodes.map(\.id)
    try await transcriptionQueue.enqueue(fillerEpisodeIDs)

    let podcastSeries = try await NewEpisodeFeed.insertSeries(
      feedURL: URL(string: "https://example.com/full-automatic-transcription.rss")!,
      alwaysTranscribeNewEpisodes: true
    )
    await session.respond(to: podcastSeries.podcast.feedURL.rawValue, data: NewEpisodeFeed.data)

    try await refreshManager.refreshSeries(podcast: podcastSeries.podcast)

    let updatedSeries = try #require(try await repo.podcastSeries(podcastSeries.id))
    #expect(updatedSeries.episodes.count == 3)
    #expect(transcriptionQueue.episodeIDs == fillerEpisodeIDs)
  }
}
