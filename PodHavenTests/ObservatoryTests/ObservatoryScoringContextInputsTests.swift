// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of Observatory scoringContextInputs tests", .container)
actor ObservatoryScoringContextInputsTests {
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.appDB) private var appDB

  // MARK: - Helpers

  private func upsertEpisode(
    podcast: Podcast,
    title: String,
    rating: EpisodeRating? = nil,
    finishDate: Date? = nil,
    pubDate: Date = Date()
  ) async throws -> Episode {
    let unsavedPodcast = try Create.unsavedPodcast(
      feedURL: podcast.feedURL,
      title: podcast.title,
      image: podcast.image,
      description: podcast.description
    )
    let unsavedEpisode = try Create.unsavedEpisode(
      title: title,
      pubDate: pubDate,
      duration: CMTime(seconds: 1800, preferredTimescale: 1),
      finishDate: finishDate,
      rating: rating,
      ratingDate: rating != nil ? Date() : nil
    )
    let podcastEpisodes = try await repo.upsertPodcastEpisodes([
      UnsavedPodcastEpisode(unsavedPodcast: unsavedPodcast, unsavedEpisode: unsavedEpisode)
    ])
    return try #require(podcastEpisodes.first?.episode)
  }

  private func insertPodcast(
    title: String = String.random()
  ) async throws -> Podcast {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(title: title),
        unsavedEpisodes: []
      )
    )
    return series.podcast
  }

  private func upsertEmbedding(
    for episode: Episode,
    vector: [Float] = [1, 0, 0]
  ) async throws {
    let data = UnsavedEpisodeEmbedding.vectorData(from: vector)
    try await repo.upsertEmbedding(
      UnsavedEpisodeEmbedding(
        episodeId: episode.id,
        vector: data,
        sourceHash: "hash-\(episode.id)",
        embeddingRevision: 1,
        dimension: vector.count
      )
    )
  }

  // MARK: - Tests

  @Test("emits empty inputs when DB has no signal episodes")
  func emptyState() async throws {
    let inputs = try await observatory.scoringContextInputs().get()
    #expect(inputs.signals.isEmpty)
    #expect(inputs.signalEmbeddings.isEmpty)
    #expect(inputs.hasAnyEmbeddings == false)
    #expect(inputs.manualFreshnessCadences.isEmpty)
    #expect(inputs.inferenceFreshnessPubDates.isEmpty)
  }

  @Test("projects manual cadences only and pubDates for nil-cadence podcasts only")
  func freshnessProjectionsSplit() async throws {
    let now = Date()
    let dailyPodcast = try await insertPodcast(title: "News")
    let evergreenPodcast = try await insertPodcast(title: "Serial")
    let autoPodcast = try await insertPodcast(title: "Auto")
    _ = try await repo.updateFreshnessCadence(dailyPodcast.id, freshnessCadence: .daily)
    _ = try await repo.updateFreshnessCadence(evergreenPodcast.id, freshnessCadence: .evergreen)
    // Give the auto podcast some episodes so its pubDates are projected;
    // give the manual ones an episode each to confirm those don't leak in.
    _ = try await upsertEpisode(podcast: dailyPodcast, title: "Daily 1", pubDate: now)
    _ = try await upsertEpisode(podcast: evergreenPodcast, title: "Ever 1", pubDate: now)
    _ = try await upsertEpisode(podcast: autoPodcast, title: "Auto 1", pubDate: now)
    _ = try await upsertEpisode(
      podcast: autoPodcast,
      title: "Auto 2",
      pubDate: now.addingTimeInterval(-7 * 86400)
    )

    let inputs = try await observatory.scoringContextInputs().get()
    #expect(inputs.manualFreshnessCadences[dailyPodcast.id] == .daily)
    #expect(inputs.manualFreshnessCadences[evergreenPodcast.id] == .evergreen)
    #expect(inputs.manualFreshnessCadences[autoPodcast.id] == nil)

    #expect(inputs.inferenceFreshnessPubDates[dailyPodcast.id] == nil)
    #expect(inputs.inferenceFreshnessPubDates[evergreenPodcast.id] == nil)
    let autoPubDates = try #require(inputs.inferenceFreshnessPubDates[autoPodcast.id])
    #expect(autoPubDates.count == 2)
  }

  @Test("re-emits when a freshness cadence flips between manual and auto")
  func reEmitsOnFreshnessCadenceChange() async throws {
    let podcast = try await insertPodcast(title: "Tunable")

    let cadenceCount = Counter()
    Task {
      for try await inputs in observatory.scoringContextInputs() {
        await cadenceCount(inputs.manualFreshnessCadences.count)
      }
    }
    try await Wait.until(
      { await cadenceCount.value == 0 },
      { "Expected initial emission with no manual cadences" }
    )

    _ = try await repo.updateFreshnessCadence(podcast.id, freshnessCadence: .daily)
    try await Wait.until(
      { await cadenceCount.value == 1 },
      { "Expected re-emission with one manual cadence, got \(await cadenceCount.value)" }
    )

    _ = try await repo.updateFreshnessCadence(podcast.id, freshnessCadence: .evergreen)
    try await Wait.until(
      { await cadenceCount.value == 1 },
      { "Expected one manual cadence after switching to evergreen" }
    )

    _ = try await repo.updateFreshnessCadence(podcast.id, freshnessCadence: nil)
    try await Wait.until(
      { await cadenceCount.value == 0 },
      { "Expected zero manual cadences after switching back to auto" }
    )
  }

  @Test("emits signals projected from rated and finished episodes")
  func projectsSignalsAndEmbeddings() async throws {
    let podcast = try await insertPodcast()
    let loved = try await upsertEpisode(podcast: podcast, title: "Loved", rating: .loved)
    let finished = try await upsertEpisode(
      podcast: podcast,
      title: "Finished",
      finishDate: Date()
    )
    let unrated = try await upsertEpisode(podcast: podcast, title: "Unrated")
    try await upsertEmbedding(for: loved, vector: [1, 0, 0])

    let inputs = try await observatory.scoringContextInputs().get()

    #expect(inputs.signals.count == 2)
    let lovedSignal = try #require(inputs.signals.first { $0.id == loved.id })
    #expect(lovedSignal.kind == .rating(.loved))
    #expect(lovedSignal.podcastID == loved.podcastID)
    #expect(lovedSignal.ratingDate != nil)

    let finishedSignal = try #require(inputs.signals.first { $0.id == finished.id })
    #expect(finishedSignal.kind == .finished)
    #expect(finishedSignal.finishDate != nil)

    #expect(inputs.signals.contains { $0.id == unrated.id } == false)

    #expect(inputs.signalEmbeddings.count == 1)
    let lovedEmbedding = try #require(inputs.signalEmbeddings[id: loved.id])
    #expect(lovedEmbedding.dimension == 3)
    #expect(lovedEmbedding.floatVector == [1, 0, 0])
    #expect(inputs.signalEmbeddings[id: finished.id] == nil)
    #expect(inputs.hasAnyEmbeddings == true)
  }

  @Test("hasAnyEmbeddings is true when only non-signal episodes have embeddings")
  func hasAnyEmbeddingsCoversCandidatesToo() async throws {
    let podcast = try await insertPodcast()
    let candidate = try await upsertEpisode(podcast: podcast, title: "Candidate")
    try await upsertEmbedding(for: candidate)

    let inputs = try await observatory.scoringContextInputs().get()
    #expect(inputs.signals.isEmpty)
    #expect(inputs.signalEmbeddings.isEmpty)
    #expect(inputs.hasAnyEmbeddings == true)
  }

  @Test("re-emits when a new rating arrives")
  func reEmitsOnNewRating() async throws {
    let podcast = try await insertPodcast()
    let episode = try await upsertEpisode(podcast: podcast, title: "Eventually liked")

    let signalCount = Counter()
    Task {
      for try await inputs in observatory.scoringContextInputs() {
        await signalCount(inputs.signals.count)
      }
    }
    try await Wait.until(
      { await signalCount.value == 0 },
      { "Expected initial empty emission" }
    )

    _ = try await repo.updateRating(episode.id, rating: .liked)

    try await Wait.until(
      { await signalCount.value == 1 },
      { "Expected re-emission with one signal, got \(await signalCount.value)" }
    )
  }

  @Test("re-emits when a signal embedding is upserted")
  func reEmitsOnEmbedding() async throws {
    let podcast = try await insertPodcast()
    let episode = try await upsertEpisode(podcast: podcast, title: "Loved", rating: .loved)

    let embeddingCount = Counter()
    Task {
      for try await inputs in observatory.scoringContextInputs() {
        await embeddingCount(inputs.signalEmbeddings.count)
      }
    }
    try await Wait.until(
      { await embeddingCount.value == 0 },
      { "Expected initial emission with no embeddings" }
    )

    try await upsertEmbedding(for: episode)

    try await Wait.until(
      { await embeddingCount.value == 1 },
      { "Expected re-emission with one embedding, got \(await embeddingCount.value)" }
    )
  }

  @Test("re-emits with signal removed when a rating is cleared")
  func reEmitsOnRatingCleared() async throws {
    let podcast = try await insertPodcast()
    let episode = try await upsertEpisode(podcast: podcast, title: "Loved", rating: .loved)

    let signalCount = Counter()
    Task {
      for try await inputs in observatory.scoringContextInputs() {
        await signalCount(inputs.signals.count)
      }
    }
    try await Wait.until(
      { await signalCount.value == 1 },
      { "Expected initial emission with one signal" }
    )

    _ = try await repo.updateRating(episode.id, rating: nil)

    try await Wait.until(
      { await signalCount.value == 0 },
      { "Expected re-emission with zero signals, got \(await signalCount.value)" }
    )
  }

  @Test("re-emits when a signal embedding is deleted")
  func reEmitsOnEmbeddingDeleted() async throws {
    let podcast = try await insertPodcast()
    let episode = try await upsertEpisode(podcast: podcast, title: "Loved", rating: .loved)
    try await upsertEmbedding(for: episode)

    let embeddingCount = Counter()
    Task {
      for try await inputs in observatory.scoringContextInputs() {
        await embeddingCount(inputs.signalEmbeddings.count)
      }
    }
    try await Wait.until(
      { await embeddingCount.value == 1 },
      { "Expected initial emission with one embedding" }
    )

    try await appDB.db.write { db in
      try db.execute(
        sql: "DELETE FROM episodeEmbedding WHERE episodeId = ?",
        arguments: [episode.id]
      )
    }

    try await Wait.until(
      { await embeddingCount.value == 0 },
      { "Expected re-emission with zero embeddings, got \(await embeddingCount.value)" }
    )
  }

  @Test("does not re-emit on irrelevant column changes")
  func skipsIrrelevantChanges() async throws {
    let podcast = try await insertPodcast()
    let episode = try await upsertEpisode(podcast: podcast, title: "Loved", rating: .loved)
    try await upsertEmbedding(for: episode)

    let emissionCount = Counter()
    Task {
      for try await _ in observatory.scoringContextInputs() {
        await emissionCount.increment()
      }
    }
    try await emissionCount.wait(for: 1)

    // currentTime is not a signal column and no embedding/rating row changes —
    // the projection should drop this update before it surfaces.
    _ = try await repo.updateCurrentTime(episode.id, currentTime: CMTime.seconds(30))
    _ = try await repo.updateCurrentTime(episode.id, currentTime: CMTime.seconds(60))

    try await Wait.until(
      maxAttempts: 50,
      { await emissionCount.maxValue == 1 },
      { "Expected exactly one emission, got \(await emissionCount.maxValue)" }
    )
  }
}
