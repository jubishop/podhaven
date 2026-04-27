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
    #expect(inputs.ratedSignals.isEmpty)
    #expect(inputs.partialSignals.isEmpty)
    #expect(inputs.signalEmbeddings.isEmpty)
    #expect(inputs.hasAnyEmbeddings == false)
    #expect(inputs.freshnessCadences.isEmpty)
  }

  @Test("manual cadence wins over inference for the same podcast")
  func manualCadenceWinsOverInference() async throws {
    let now = Date()
    let manualPodcast = try await insertPodcast(title: "News")
    _ = try await repo.updateFreshnessCadence(manualPodcast.id, freshnessCadence: .evergreen)
    // Daily-spaced episodes that would otherwise infer to .daily.
    for index in 0..<5 {
      _ = try await upsertEpisode(
        podcast: manualPodcast,
        title: "Episode \(index)",
        pubDate: now.addingTimeInterval(-Double(index) * 86400)
      )
    }

    let inputs = try await observatory.scoringContextInputs().get()
    #expect(inputs.freshnessCadences[manualPodcast.id] == .evergreen)
  }

  @Test("infers daily cadence from daily-spaced pubDates")
  func infersDailyCadence() async throws {
    let now = Date()
    let podcast = try await insertPodcast(title: "Daily News")
    for index in 0..<5 {
      _ = try await upsertEpisode(
        podcast: podcast,
        title: "Episode \(index)",
        pubDate: now.addingTimeInterval(-Double(index) * 86400)
      )
    }

    let inputs = try await observatory.scoringContextInputs().get()
    #expect(inputs.freshnessCadences[podcast.id] == .daily)
  }

  @Test("infers weekly cadence from week-spaced pubDates")
  func infersWeeklyCadence() async throws {
    let now = Date()
    let podcast = try await insertPodcast(title: "Weekly Show")
    for index in 0..<5 {
      _ = try await upsertEpisode(
        podcast: podcast,
        title: "Episode \(index)",
        pubDate: now.addingTimeInterval(-Double(index) * 7 * 86400)
      )
    }

    let inputs = try await observatory.scoringContextInputs().get()
    #expect(inputs.freshnessCadences[podcast.id] == .weekly)
  }

  @Test("infers evergreen for dormant podcasts past the threshold")
  func infersEvergreenForDormant() async throws {
    let now = Date()
    let podcast = try await insertPodcast(title: "Wrapped Serial")
    // Most recent episode is 200 days old → past the 180-day dormancy
    // threshold even though historical spacing was weekly.
    for index in 0..<5 {
      _ = try await upsertEpisode(
        podcast: podcast,
        title: "Episode \(index)",
        pubDate: now.addingTimeInterval(-Double(200 + index * 7) * 86400)
      )
    }

    let inputs = try await observatory.scoringContextInputs().get()
    #expect(inputs.freshnessCadences[podcast.id] == .evergreen)
  }

  @Test("falls back to default cadence with insufficient pubDates")
  func defaultCadenceWhenTooFewEpisodes() async throws {
    let podcast = try await insertPodcast(title: "Brand New")
    _ = try await upsertEpisode(podcast: podcast, title: "Only one")

    let inputs = try await observatory.scoringContextInputs().get()
    #expect(inputs.freshnessCadences[podcast.id] == .default)
  }

  @Test("podcasts without any episodes are absent from the cadence map")
  func absentWhenNoEpisodesAndAuto() async throws {
    let podcast = try await insertPodcast(title: "Empty")
    let inputs = try await observatory.scoringContextInputs().get()
    #expect(inputs.freshnessCadences[podcast.id] == nil)
  }

  @Test("re-emits when a freshness cadence flips between manual and auto")
  func reEmitsOnFreshnessCadenceChange() async throws {
    let now = Date()
    let podcast = try await insertPodcast(title: "Tunable")
    // Three weekly-spaced episodes so the auto branch resolves to .weekly
    // (distinct from the .daily we'll switch to manually).
    for index in 0..<3 {
      _ = try await upsertEpisode(
        podcast: podcast,
        title: "Episode \(index)",
        pubDate: now.addingTimeInterval(-Double(index) * 7 * 86400)
      )
    }

    let podcastID = podcast.id
    let cadence = ThreadSafe<FreshnessCadence?>(nil)
    Task {
      for await inputs in observatory.scoringContextInputs() {
        cadence(inputs.freshnessCadences[podcastID])
      }
    }
    try await Wait.until(
      { cadence() == .weekly },
      { "Expected initial inferred .weekly, got \(String(describing: cadence()))" }
    )

    _ = try await repo.updateFreshnessCadence(podcast.id, freshnessCadence: .daily)
    try await Wait.until(
      { cadence() == .daily },
      { "Expected manual .daily, got \(String(describing: cadence()))" }
    )

    _ = try await repo.updateFreshnessCadence(podcast.id, freshnessCadence: .evergreen)
    try await Wait.until(
      { cadence() == .evergreen },
      { "Expected manual .evergreen, got \(String(describing: cadence()))" }
    )

    _ = try await repo.updateFreshnessCadence(podcast.id, freshnessCadence: nil)
    try await Wait.until(
      { cadence() == .weekly },
      { "Expected re-inferred .weekly, got \(String(describing: cadence()))" }
    )
  }

  @Test("emits rated signals projected from rated episodes; finished alone is not a signal")
  func projectsSignalsAndEmbeddings() async throws {
    let podcast = try await insertPodcast()
    let loved = try await upsertEpisode(podcast: podcast, title: "Loved", rating: .loved)
    // Finished but unrated, no playback bitmap → not a signal anymore.
    let finished = try await upsertEpisode(
      podcast: podcast,
      title: "Finished",
      finishDate: Date()
    )
    let unrated = try await upsertEpisode(podcast: podcast, title: "Unrated")
    try await upsertEmbedding(for: loved, vector: [1, 0, 0])

    let inputs = try await observatory.scoringContextInputs().get()

    #expect(inputs.ratedSignals.count == 1)
    let lovedSignal = try #require(inputs.ratedSignals.first { $0.id == loved.id })
    #expect(lovedSignal.rating == .loved)
    #expect(lovedSignal.podcastID == loved.podcastID)
    #expect(lovedSignal.ratingDate != nil)

    #expect(inputs.partialSignals.isEmpty)
    #expect(inputs.ratedSignals.contains { $0.id == finished.id } == false)
    #expect(inputs.ratedSignals.contains { $0.id == unrated.id } == false)

    #expect(inputs.signalEmbeddings.count == 1)
    let lovedEmbedding = try #require(inputs.signalEmbeddings[id: loved.id])
    #expect(lovedEmbedding.dimension == 3)
    #expect(lovedEmbedding.floatVector == [1, 0, 0])
    #expect(inputs.signalEmbeddings[id: finished.id] == nil)
    #expect(inputs.hasAnyEmbeddings == true)
  }

  @Test("an episode with a real playback bitmap appears as a partial signal")
  func partialSignalFromBitmap() async throws {
    let podcast = try await insertPodcast()
    let episode = try await upsertEpisode(podcast: podcast, title: "Played")

    // Simulate a playback session: 0–600s of a 1800s episode listened.
    try await repo.updatePlayback(
      episode.id,
      currentTime: CMTime.seconds(600),
      playedFrom: CMTime.seconds(0),
      now: Date()
    )
    observatory.refreshScoringContext()

    let partialCount = Counter()
    Task {
      for await inputs in observatory.scoringContextInputs() {
        await partialCount(inputs.partialSignals.count)
      }
    }

    try await Wait.until(
      { await partialCount.value == 1 },
      { "Expected partial signal to materialize, got \(await partialCount.value)" }
    )
  }

  @Test("hasAnyEmbeddings is true when only non-signal episodes have embeddings")
  func hasAnyEmbeddingsCoversCandidatesToo() async throws {
    let podcast = try await insertPodcast()
    let candidate = try await upsertEpisode(podcast: podcast, title: "Candidate")
    try await upsertEmbedding(for: candidate)

    let inputs = try await observatory.scoringContextInputs().get()
    #expect(inputs.ratedSignals.isEmpty)
    #expect(inputs.partialSignals.isEmpty)
    #expect(inputs.signalEmbeddings.isEmpty)
    #expect(inputs.hasAnyEmbeddings == true)
  }

  @Test("re-emits when a new rating arrives")
  func reEmitsOnNewRating() async throws {
    let podcast = try await insertPodcast()
    let episode = try await upsertEpisode(podcast: podcast, title: "Eventually liked")

    let signalCount = Counter()
    Task {
      for await inputs in observatory.scoringContextInputs() {
        await signalCount(inputs.ratedSignals.count)
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
      for await inputs in observatory.scoringContextInputs() {
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
      for await inputs in observatory.scoringContextInputs() {
        await signalCount(inputs.ratedSignals.count)
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
      for await inputs in observatory.scoringContextInputs() {
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

  @Test("does not re-emit on playback-path or unrelated column changes")
  func skipsIrrelevantChanges() async throws {
    // Seed both tracking branches: a manual-cadence podcast with a signal
    // episode + embedding (covers the signal projection + embedding fetch)
    // AND auto-cadence podcasts with multiple episodes (covers the
    // pubDate-window SQL).
    let manualPodcast = try await insertPodcast(title: "Manual")
    _ = try await repo.updateFreshnessCadence(manualPodcast.id, freshnessCadence: .weekly)
    let signalEpisode = try await upsertEpisode(
      podcast: manualPodcast,
      title: "Loved",
      rating: .loved
    )
    try await upsertEmbedding(for: signalEpisode)

    let autoPodcastA = try await insertPodcast(title: "Auto A")
    let autoEpisodeA1 = try await upsertEpisode(podcast: autoPodcastA, title: "A1")
    let autoEpisodeA2 = try await upsertEpisode(podcast: autoPodcastA, title: "A2")
    let autoPodcastB = try await insertPodcast(title: "Auto B")
    let autoEpisodeB1 = try await upsertEpisode(podcast: autoPodcastB, title: "B1")

    let emissionCount = Counter()
    Task {
      for await _ in observatory.scoringContextInputs() {
        await emissionCount.increment()
      }
    }
    try await emissionCount.wait(for: 1)

    // Episode columns the scoring context's GRDB observation never reads
    // (currentTime, duration, cachedFilename, saveInCache). Without an
    // explicit refresh poke, none of these should fire a re-emission, even
    // for the rated signal episode.
    let allEpisodeIDs = [
      signalEpisode.id, autoEpisodeA1.id, autoEpisodeA2.id, autoEpisodeB1.id,
    ]
    for episodeID in allEpisodeIDs {
      _ = try await repo.updateCurrentTime(episodeID, currentTime: CMTime.seconds(30))
      _ = try await repo.updateDuration(
        episodeID,
        duration: CMTime(seconds: 1900, preferredTimescale: 1)
      )
      _ = try await repo.updateCachedFilename(episodeID, cachedFilename: "f-\(episodeID).mp3")
      _ = try await repo.updateSaveInCache(episodeID, saveInCache: true)
    }

    // Podcast columns the scoring context never reads.
    for podcastID in [manualPodcast.id, autoPodcastA.id, autoPodcastB.id] {
      _ = try await repo.updateDefaultPlaybackRate(podcastID, defaultPlaybackRate: 1.5)
      _ = try await repo.updateQueueAllEpisodes(podcastID, queueAllEpisodes: .onTop)
      _ = try await repo.updateCacheAllEpisodes(podcastID, cacheAllEpisodes: .save)
      _ = try await repo.updateNotifyNewEpisodes(podcastID, notifyNewEpisodes: true)
      _ = try await repo.updateLastUpdate(podcastID)
    }

    try await Wait.until(
      maxAttempts: 50,
      {
        await emissionCount.maxValue == 1
      },
      {
        "Expected exactly one emission after irrelevant updates, "
          + "got \(await emissionCount.maxValue)"
      }
    )
  }

  @Test("explicit refreshScoringContext() re-emits with up-to-date partial signals")
  func explicitRefreshTriggersRebuild() async throws {
    let podcast = try await insertPodcast()
    let episode = try await upsertEpisode(podcast: podcast, title: "Played later")

    let partialCount = Counter()
    Task {
      for await inputs in observatory.scoringContextInputs() {
        await partialCount(inputs.partialSignals.count)
      }
    }
    try await emissionCountWaitInitial(partialCount)

    // Bitmap update writes a column the GRDB observation does NOT track,
    // so the engine sees nothing change — until the explicit refresh poke.
    try await repo.updatePlayback(
      episode.id,
      currentTime: CMTime.seconds(120),
      playedFrom: CMTime.seconds(0),
      now: Date()
    )

    observatory.refreshScoringContext()

    try await Wait.until(
      { await partialCount.value == 1 },
      { "Expected partial signal after explicit refresh, got \(await partialCount.value)" }
    )
  }

  private func emissionCountWaitInitial(_ counter: Counter) async throws {
    try await Wait.until(
      { await counter.value == 0 },
      { "Expected initial empty emission" }
    )
  }
}
