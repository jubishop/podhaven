// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import NaturalLanguage
import Testing

@testable import PodHaven

@Suite("ContextualEmbedding recovery tests", .container)
struct ContextualEmbeddingRecoveryTests {
  @Test("present assets that fail to load recover through one asset request")
  func availableAssetsRecover() async throws {
    let fake = RecoveringEmbeddable(loadFailures: 1, automaticResult: .available)
    let embedding = register(fake)
    let captured = try await LogCapture.withSink { sink in
      await embedding.requestAndLoadAssetsIfNeeded()
      try await Wait.until({ embedding.assetsLoaded.isOpen }) {
        "Failed model did not recover after requesting its available assets"
      }
      return sink.captured()
    }
    #expect(fake.loadCount == 2)
    #expect(fake.requestCount == 1)
    let failure = try #require(captured.first { $0.message.contains("requires compilation") })
    #expect(failure.level == .error)
    #expect(failure.message.contains("revision=17"))
    let recovery = try #require(
      captured.first { $0.message.contains("event=contextualEmbeddingRecovered") }
    )
    #expect(recovery.level == .warning)
    #expect(recovery.message.contains("loadAttempts=2"))
    #expect(recovery.message.contains("requestAttempts=1"))
    #expect(recovery.message.contains("wallSeconds="))
    let sessions = Set(
      captured.compactMap { entry in
        entry.message.split(separator: " ").first { $0.hasPrefix("modelSession=") }
      }
    )
    #expect(sessions.count == 1)
    #expect(captured.count { $0.message.contains("event=contextualEmbeddingRecovered") } == 1)
  }

  @Test("a failed load after download can request recovery without a stuck request state")
  func postDownloadLoadRecovers() async throws {
    let fake = RecoveringEmbeddable(assetsAvailable: false, loadFailures: 1)
    let embedding = register(fake)
    await embedding.requestAndLoadAssetsIfNeeded()
    #expect(fake.requestCount == 1)
    fake.completeNextRequest(.available)
    try await Wait.until({ fake.requestCount == 2 }) {
      "Post-download load failure left recovery suppressed"
    }
    #expect(!embedding.assetsLoaded.isOpen)
    fake.completeNextRequest(.available)
    try await Wait.until({ embedding.assetsLoaded.isOpen }) { "Recovery did not open readiness" }
    #expect(fake.loadCount == 2)
    #expect(fake.requestCount == 2)
  }

  @Test(
    "non-available request results never load the model",
    arguments: [
      NLContextualEmbedding.AssetsResult.notAvailable, .error,
    ]
  )
  func unavailableResultsDoNotLoad(_ result: NLContextualEmbedding.AssetsResult) async throws {
    let fake = RecoveringEmbeddable(assetsAvailable: false, automaticResult: result)
    let embedding = register(fake)
    let captured = try await LogCapture.withSink { sink in
      await embedding.requestAndLoadAssetsIfNeeded()
      try await waitForRequestCompletion(sink)
      await embedding.loadAssetsIfAvailable()
      return sink.captured()
    }
    #expect(fake.loadCount == 0)
    #expect(!embedding.assetsLoaded.isOpen)
    #expect(captured.contains { $0.level == (result == .error ? .error : .warning) })
  }

  @Test("download timeout is a targeted warning and repeated callers cannot request again")
  func timeoutIsWarningAndBounded() async throws {
    let timeout = NSError(
      domain: "NLNaturalLanguageErrorDomain",
      code: 7,
      userInfo: [NSLocalizedDescriptionKey: "Asset download request timed out"]
    )
    let fake = RecoveringEmbeddable(
      assetsAvailable: false,
      automaticResult: .error,
      requestError: timeout
    )
    let embedding = register(fake)
    let captured = try await LogCapture.withSink { sink in
      await embedding.requestAndLoadAssetsIfNeeded()
      try await Wait.until({ sink.captured().contains { $0.message.contains("timed out") } }) {
        "Missing timeout diagnostic"
      }
      for _ in 0..<20 { await embedding.requestAndLoadAssetsIfNeeded() }
      return sink.captured()
    }
    #expect(fake.requestCount == 1)
    #expect(fake.loadCount == 0)
    #expect(captured.first { $0.message.contains("timed out") }?.level == .warning)
  }

  @Test("an error accompanying available assets is still failure")
  func availableResultWithErrorIsFailure() async throws {
    let fake = RecoveringEmbeddable(
      assetsAvailable: false,
      automaticResult: .available,
      requestError: RecoveringEmbeddable.compilationError
    )
    let embedding = register(fake)
    let captured = try await LogCapture.withSink { sink in
      await embedding.requestAndLoadAssetsIfNeeded()
      try await Wait.until({
        sink.captured().contains { $0.message.contains("requires compilation") }
      }) {
        "Missing request error"
      }
      return sink.captured()
    }
    #expect(!embedding.assetsLoaded.isOpen)
    #expect(fake.loadCount == 0)
    #expect(captured.first { $0.message.contains("requires compilation") }?.level == .error)
    #expect(
      captured.contains { $0.message.contains("result=") && $0.message.contains("revision=17") }
    )
  }

  @Test("persistent failure cannot be retried by scoring or repeated foreground calls")
  func persistentFailureIsBounded() async throws {
    let fake = RecoveringEmbeddable(loadFailures: 100, automaticResult: .available)
    let embedding = register(fake)
    await embedding.requestAndLoadAssetsIfNeeded()
    try await Wait.until({ fake.loadCount == 2 }) {
      "Expected one initial load and one recovery load"
    }
    for _ in 0..<20 {
      await embedding.requestAndLoadAssetsIfNeeded()
      await embedding.loadAssetsIfAvailable()
    }
    #expect(fake.loadCount == 2)
    #expect(fake.requestCount == 1)
    #expect(!embedding.assetsLoaded.isOpen)
  }

  @Test("unsaved scoring stays non-cacheable until failed model recovery succeeds")
  @MainActor func scoringResumesAfterRecovery() async throws {
    let fake = RecoveringEmbeddable(loadFailures: 1)
    let embedding = register(fake)
    await embedding.requestAndLoadAssetsIfNeeded()
    let scorer = UnsavedEpisodeEmbeddingScorer()
    let episode = UnsavedPodcastEpisode(
      unsavedPodcast: try Create.unsavedPodcast(),
      unsavedEpisode: try Create.unsavedEpisode()
    )
    let unavailable = try await scorer.similarityScore(for: episode)
    #expect(!unavailable.cacheable)
    #expect(unavailable.score == nil)
    #expect(fake.vectorCount == 0)
    fake.completeNextRequest(.available)
    try await Wait.until({ embedding.assetsLoaded.isOpen }) { "Recovery never became ready" }
    let recovered = try await scorer.similarityScore(for: episode)
    #expect(recovered.cacheable)
    #expect(fake.vectorCount > 0)
  }

  @Test(
    "background or thermal suspension defers request completion and preserves demand",
    arguments: [false, true]
  )
  func suspendedCompletionResumes(thermal: Bool) async throws {
    let fake = RecoveringEmbeddable(assetsAvailable: false)
    let embedding = register(fake)
    let processor = EmbeddingProcessor()
    defer { processor.handleScenePhaseChange(to: .background) }
    let demand = Container.shared.embeddingWorkDemand()
    try await LogCapture.withSink { sink in
      processor.handleScenePhaseChange(to: .active)
      try await Wait.until({ fake.requestCount == 1 }) { "Foreground did not request assets" }
      _ = try await RecommendationHelpers.createPodcastWithEpisodes(count: 1)
      try await Wait.until({ demand.hasWork }) { "Pending request blocked demand observation" }
      if thermal {
        processor.handleThermalPressureChange(to: .serious)
      } else {
        processor.handleScenePhaseChange(to: .background)
      }
      fake.completeNextRequest(.available)
      try await waitForRequestCompletion(sink)
      await embedding.loadAssetsIfAvailable()
      #expect(!embedding.assetsLoaded.isOpen)
      #expect(fake.loadCount == 0)
      #expect(demand.hasWork)
      if thermal {
        processor.handleThermalPressureChange(to: .nominal)
      } else {
        processor.handleScenePhaseChange(to: .active)
      }
      try await RecommendationHelpers.untilAdvancing({ !demand.hasWork }) {
        "Resumed preparation did not drain pending work"
      }
      #expect(embedding.assetsLoaded.isOpen)
      #expect(fake.loadCount == 1)
      #expect(fake.requestCount == 1)
    }
  }

  @Test("exhausted recovery requires a new activation and the cooldown")
  func foregroundActivationAndCooldown() async throws {
    let fake = RecoveringEmbeddable(loadFailures: 100, automaticResult: .available)
    let embedding = register(fake)
    let clock = Container.shared.fakeContinuousClock()
    clock.freeze()
    let firstActivation = UUID()
    await embedding.requestAndLoadAssetsIfNeeded(activation: firstActivation)
    try await Wait.until({ fake.loadCount == 2 }) { "First sequence did not finish" }
    let earlyActivation = UUID()
    clock.advance(by: .seconds(59))
    await embedding.requestAndLoadAssetsIfNeeded(activation: earlyActivation)
    #expect(fake.requestCount == 1)
    clock.advance(by: .seconds(1))
    await embedding.requestAndLoadAssetsIfNeeded(activation: earlyActivation)
    await embedding.loadAssetsIfAvailable()
    #expect(fake.requestCount == 1)
    #expect(fake.loadCount == 2)
    await embedding.requestAndLoadAssetsIfNeeded(activation: UUID())
    try await Wait.until({ fake.loadCount == 4 }) { "Eligible activation did not finish its retry" }
    #expect(fake.requestCount == 2)
    #expect(!embedding.assetsLoaded.isOpen)
  }

  @Test("concurrent callers share the request and duplicate callbacks are ignored")
  func concurrentCallersAndDuplicateCompletion() async throws {
    let fake = RecoveringEmbeddable(loadFailures: 1)
    let embedding = register(fake)
    let activation = UUID()
    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<30 {
        group.addTask { await embedding.requestAndLoadAssetsIfNeeded(activation: activation) }
      }
    }
    #expect(fake.loadCount == 1)
    #expect(fake.requestCount == 1)
    let completion = try #require(fake.completeNextRequest(.available))
    try await Wait.until({ embedding.assetsLoaded.isOpen }) { "Shared recovery did not finish" }
    completion(.error, RecoveringEmbeddable.compilationError)
    completion(.available, nil)
    await embedding.requestAndLoadAssetsIfNeeded(activation: activation)
    #expect(fake.loadCount == 2)
    #expect(fake.requestCount == 1)
  }

  @Test("request completion loads its originating actor after factory replacement")
  func completionBelongsToOriginatingActor() async throws {
    let fake = RecoveringEmbeddable(assetsAvailable: false)
    let original = register(fake)
    await original.requestAndLoadAssetsIfNeeded()
    let replacementFake = RecoveringEmbeddable()
    let replacement = register(replacementFake)
    fake.completeNextRequest(.available)
    try await Wait.until({ original.assetsLoaded.isOpen }) { "Original model was not loaded" }
    #expect(!replacement.assetsLoaded.isOpen)
    #expect(replacementFake.loadCount == 0)
  }

  @Test("normal loading produces no recovery warning")
  func normalLoadIsQuiet() async {
    let embedding = register(RecoveringEmbeddable())
    let captured = await LogCapture.withSink { sink in
      await embedding.requestAndLoadAssetsIfNeeded()
      return sink.captured()
    }
    #expect(embedding.assetsLoaded.isOpen)
    #expect(!captured.contains { $0.level >= .warning })
  }

  @Test("cold background load failure waits for foreground recovery")
  func backgroundFailureWaitsForForeground() async throws {
    let fake = RecoveringEmbeddable(loadFailures: 1, automaticResult: .available)
    let embedding = register(fake)
    for _ in 0..<10 { await embedding.loadAssetsIfAvailable() }
    #expect(fake.loadCount == 1)
    #expect(fake.requestCount == 0)
    await embedding.requestAndLoadAssetsIfNeeded()
    try await Wait.until({ embedding.assetsLoaded.isOpen }) { "Foreground did not recover" }
    #expect(fake.loadCount == 2)
    #expect(fake.requestCount == 1)
  }

  private func register(_ fake: RecoveringEmbeddable) -> ContextualEmbedding {
    let embedding = ContextualEmbedding(embedding: fake)
    Container.shared.contextualEmbedding.reset().register { embedding }.scope(.cached)
    return embedding
  }

  private func waitForRequestCompletion(_ sink: LogCapture.Sink) async throws {
    try await Wait.until({
      sink.captured()
        .contains {
          $0.message.contains("event=contextualEmbeddingAssetRequestCompleted")
        }
    }) { "Asset request completion was not handled" }
  }
}
