// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("EmbeddingService telemetry tests", .container)
struct EmbeddingServiceTelemetryTests {
  @DynamicInjected(\.recommendationRepo) private var recommendationRepo
  @DynamicInjected(\.repo) private var repo

  @Test("embedding batch telemetry reports deduplicated text preparation")
  func batchTelemetryReportsDeduplicatedTextPreparation() async throws {
    let unsavedPodcast = try Create.unsavedPodcast(
      title: "Shared Podcast",
      description: "Shared podcast description"
    )
    let podcastEpisodes = try await repo.upsertPodcastEpisodes([
      UnsavedPodcastEpisode(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisode: try Create.unsavedEpisode(
          title: "Episode One",
          description: "First description"
        )
      ),
      UnsavedPodcastEpisode(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisode: try Create.unsavedEpisode(
          title: "Episode Two",
          description: "Second description"
        )
      ),
    ])
    let embedding = await makeContextualEmbedding()
    Container.shared.fakeContinuousClock().freeze()

    let captured = try await LogCapture.withSink { sink in
      try await EmbeddingService.upsertEpisodeEmbeddings(
        for: podcastEpisodes.map(\.episode),
        embedding: embedding
      )
      return sink.captured()
    }

    let completionEvents = captured.filter {
      $0.message.contains("embeddingTelemetry event=batchCompleted")
    }
    let telemetry = try #require(completionEvents.first)
    #expect(completionEvents.count == 1)
    #expect(telemetry.level == .info)
    #expect(telemetry.message.contains("outcome=completed"))
    #expect(telemetry.message.contains("episodes=2"))
    #expect(telemetry.message.contains("uniquePodcasts=1"))
    #expect(telemetry.message.contains("cleanInputs=6"))
    #expect(telemetry.message.contains("inputBytes="))
    #expect(telemetry.message.contains("cleaningSeconds="))
    #expect(telemetry.message.contains("embeddingSeconds="))
    #expect(telemetry.message.contains("databaseSeconds="))
    #expect(telemetry.message.contains("wallSeconds="))
  }

  @Test("embedding text preparation stays deduplicated across hydration chunks")
  func textPreparationDeduplicatesAcrossHydrationChunks() async throws {
    let (_, episodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 65,
      podcastTitle: "Chunked Podcast",
      podcastDescription: "Shared chunked description"
    )
    let embedding = await makeContextualEmbedding()

    let captured = try await LogCapture.withSink { sink in
      try await EmbeddingService.upsertEpisodeEmbeddings(
        forIDs: episodes.map(\.id),
        embedding: embedding
      )
      return sink.captured()
    }

    let completionEvents = captured.filter {
      $0.message.contains("embeddingTelemetry event=batchCompleted")
    }
    let telemetry = try #require(completionEvents.first)
    #expect(completionEvents.count == 1)
    #expect(telemetry.message.contains("episodes=65"))
    #expect(telemetry.message.contains("uniquePodcasts=1"))
    #expect(telemetry.message.contains("cleanInputs=132"))
  }

  @Test("podcast preparation refreshes when content changes between hydration chunks")
  func podcastPreparationRefreshesAcrossHydrationChunks() async throws {
    let (podcast, episodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 65,
      podcastTitle: "Changing Podcast",
      podcastDescription: "Original podcast description"
    )
    let recorder = TelemetryRecordingEmbeddable()
    let embedding = await makeContextualEmbedding(recorder)
    let fakeRecommendationRepo = try #require(recommendationRepo as? FakeRecommendationRepo)
    fakeRecommendationRepo.armEmbeddingUpsertGate()
    let embeddingTask = Task {
      try await EmbeddingService.upsertEpisodeEmbeddings(
        forIDs: episodes.map(\.id),
        embedding: embedding
      )
    }
    defer { fakeRecommendationRepo.releaseEmbeddingUpsertGate() }

    try await Wait.until(
      { fakeRecommendationRepo.isEmbeddingUpsertGateSuspended },
      { "The first hydration chunk did not reach its embedding write" }
    )
    let updatedDescription = "Updated podcast description"
    try await repo.upsertPodcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try makeUnsavedPodcast(
          from: podcast,
          description: updatedDescription
        ),
        unsavedEpisode: try #require(episodes.first).toOriginalUnsavedEpisode()
      )
    )
    fakeRecommendationRepo.releaseEmbeddingUpsertGate()
    let result = try await embeddingTask.value

    #expect(result.failedEpisodeCount == 0)
    #expect(recorder.seenInputs().contains(updatedDescription))
  }

  @Test("slow embedding batches emit warning telemetry")
  func slowBatchEmitsWarningTelemetry() async throws {
    let podcastEpisode = try await makePodcastEpisode(
      podcastTitle: "Slow Podcast",
      podcastDescription: "Slow podcast description",
      episodeTitle: "Slow Episode",
      episodeDescription: "Slow episode description"
    )
    let fakeClock = Container.shared.fakeContinuousClock()
    fakeClock.freeze()
    let embedding = await makeContextualEmbedding(
      ClockAdvancingEmbeddable(clock: fakeClock, durationPerInput: .seconds(3))
    )

    let captured = try await LogCapture.withSink { sink in
      try await EmbeddingService.upsertEpisodeEmbeddings(
        for: [podcastEpisode.episode],
        embedding: embedding
      )
      return sink.captured()
    }

    let telemetry = try #require(
      captured.first { $0.message.contains("embeddingTelemetry event=batchCompleted") }
    )
    #expect(telemetry.level == .warning)
    #expect(telemetry.message.contains("wallSeconds=12.0"))
  }

  @Test("failed embedding batches retain completed telemetry metrics")
  func failedBatchRetainsCompletedTelemetryMetrics() async throws {
    let podcastEpisode = try await makePodcastEpisode(
      podcastTitle: "Failed Podcast",
      podcastDescription: "Failed podcast description",
      episodeTitle: "Failed Episode",
      episodeDescription: "Failed episode description"
    )
    let embedding = await makeContextualEmbedding()
    let fakeRecommendationRepo = try #require(recommendationRepo as? FakeRecommendationRepo)
    fakeRecommendationRepo.embeddingUpsertError { $0 = TestError.simulatedFailure }

    let captured = await LogCapture.withSink { sink in
      await #expect(throws: TestError.self) {
        try await EmbeddingService.upsertEpisodeEmbeddings(
          for: [podcastEpisode.episode],
          embedding: embedding
        )
      }
      return sink.captured()
    }

    let telemetry = try #require(
      captured.first { $0.message.contains("embeddingTelemetry event=batchFailed") }
    )
    #expect(telemetry.message.contains("episodes=1"))
    #expect(telemetry.message.contains("uniquePodcasts=1"))
    #expect(telemetry.message.contains("cleanInputs=4"))
  }

  @Test("failed episode hydration retains its database duration")
  func failedEpisodeHydrationRetainsDatabaseDuration() async throws {
    let (_, episodes) = try await RecommendationHelpers.createPodcastWithEpisodes(count: 1)
    let embedding = await makeContextualEmbedding()
    let fakeClock = Container.shared.fakeContinuousClock()
    fakeClock.freeze()
    let fakeRecommendationRepo = try #require(recommendationRepo as? FakeRecommendationRepo)
    fakeRecommendationRepo.episodeHydrationError { pending in
      pending = {
        fakeClock.advance(by: .seconds(2))
        return TestError.simulatedFailure
      }
    }

    let captured = await LogCapture.withSink { sink in
      await #expect(throws: TestError.self) {
        try await EmbeddingService.upsertEpisodeEmbeddings(
          forIDs: episodes.map(\.id),
          embedding: embedding
        )
      }
      return sink.captured()
    }

    let telemetry = try #require(
      captured.first { $0.message.contains("embeddingTelemetry event=batchFailed") }
    )
    #expect(telemetry.message.contains("databaseSeconds=2.0"))
    #expect(telemetry.message.contains("wallSeconds=2.0"))
  }

  private func makeContextualEmbedding(
    _ embeddable: some Embeddable & Sendable = FakeEmbeddable()
  ) async -> ContextualEmbedding {
    let embedding = ContextualEmbedding(embedding: embeddable)
    await embedding.requestAndLoadAssetsIfNeeded()
    return embedding
  }

  private func makePodcastEpisode(
    podcastTitle: String,
    podcastDescription: String,
    episodeTitle: String,
    episodeDescription: String
  ) async throws -> PodcastEpisode {
    let podcastEpisodes = try await repo.upsertPodcastEpisodes([
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(
          title: podcastTitle,
          description: podcastDescription
        ),
        unsavedEpisode: try Create.unsavedEpisode(
          title: episodeTitle,
          description: episodeDescription
        )
      )
    ])
    return try #require(podcastEpisodes.first)
  }

  private func makeUnsavedPodcast(
    from podcast: Podcast,
    description: String
  ) throws -> UnsavedPodcast {
    try Create.unsavedPodcast(
      feedURL: podcast.feedURL,
      iTunesID: podcast.iTunesID,
      title: podcast.title,
      image: podcast.image,
      description: description,
      link: podcast.link,
      lastUpdate: podcast.lastUpdate,
      subscriptionDate: podcast.subscriptionDate,
      defaultPlaybackRate: podcast.defaultPlaybackRate,
      queueAllEpisodes: podcast.queueAllEpisodes,
      cacheAllEpisodes: podcast.cacheAllEpisodes,
      notifyNewEpisodes: podcast.notifyNewEpisodes
    )
  }
}

private final class TelemetryRecordingEmbeddable: Embeddable, Sendable {
  let hasAvailableAssets = true
  let revision: Int = 1

  private let inputs = ThreadSafe<[String]>([])

  func load() throws {}
  func requestAssets(completion: @escaping @Sendable ((any Error)?) -> Void) { completion(nil) }

  func embeddingResult(for string: String) throws -> any EmbeddableResult {
    inputs { $0.append(string) }
    return try FakeEmbeddable().embeddingResult(for: string)
  }

  func seenInputs() -> [String] { inputs() }
}

private struct ClockAdvancingEmbeddable: Embeddable, Sendable {
  let hasAvailableAssets = true
  let revision: Int = 1
  let clock: FakeContinuousClock
  let durationPerInput: Duration

  func load() throws {}
  func requestAssets(completion: @escaping @Sendable ((any Error)?) -> Void) { completion(nil) }

  func embeddingResult(for string: String) throws -> any EmbeddableResult {
    clock.advance(by: durationPerInput)
    return try FakeEmbeddable().embeddingResult(for: string)
  }
}
