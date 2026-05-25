// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("UnsavedEpisodeEmbeddingScorer tests", .container)
@MainActor final class UnsavedEpisodeEmbeddingScorerTests {

  @Test("reuses cached vector on repeat score for the same (mediaGUID, source)")
  func reusesCachedVectorOnRepeatCall() async throws {
    let counter = ThreadSafe(0)
    registerEmbeddable(revision: 1, counter: counter)

    let episode = try unsavedPodcastEpisode()
    let scorer = UnsavedEpisodeEmbeddingScorer()

    _ = try await scorer.similarityScore(for: episode)
    let firstCallCount = counter()
    #expect(firstCallCount > 0, "First score must hit the embeddable to build the vector")

    _ = try await scorer.similarityScore(for: episode)
    #expect(
      counter() == firstCallCount,
      "Repeat score for the same (mediaGUID, source) must reuse the cached vector"
    )
  }

  @Test("re-embeds when searchableString changes for the same mediaGUID")
  func reEmbedsOnSourceChange() async throws {
    let counter = ThreadSafe(0)
    registerEmbeddable(revision: 1, counter: counter)

    let podcast = try Create.unsavedPodcast()
    let guid: GUID = GUID(String.random())
    let mediaURL: MediaURL = MediaURL(URL.valid())
    let first = UnsavedPodcastEpisode(
      unsavedPodcast: podcast,
      unsavedEpisode: try Create.unsavedEpisode(
        guid: guid,
        mediaURL: mediaURL,
        title: "First title",
        description: "First body"
      )
    )
    let second = UnsavedPodcastEpisode(
      unsavedPodcast: podcast,
      unsavedEpisode: try Create.unsavedEpisode(
        guid: guid,
        mediaURL: mediaURL,
        title: "Second title",
        description: "Second body"
      )
    )
    #expect(first.mediaGUID == second.mediaGUID)
    #expect(first.searchableString != second.searchableString)

    let scorer = UnsavedEpisodeEmbeddingScorer()

    _ = try await scorer.similarityScore(for: first)
    let firstCallCount = counter()
    #expect(firstCallCount > 0)

    _ = try await scorer.similarityScore(for: second)
    #expect(
      counter() > firstCallCount,
      "A searchableString change must invalidate the cached vector and re-embed"
    )
  }

  @Test("returns (nil, false) and (empty, false) when embedding assets aren't loaded")
  func cacheableFalseWhenAssetsNotLoaded() async throws {
    let counter = ThreadSafe(0)
    registerEmbeddable(assetsAvailable: false, revision: 1, counter: counter)

    let episode = try unsavedPodcastEpisode()
    let scorer = UnsavedEpisodeEmbeddingScorer()

    let single = try await scorer.similarityScore(for: episode)
    #expect(single.score == nil)
    #expect(single.cacheable == false)

    let batch = try await scorer.similarityScores(for: [episode])
    #expect(batch.scores.isEmpty)
    #expect(batch.cacheable == false)

    #expect(
      counter() == 0,
      "Embeddable must not be invoked while assets are unloaded — the scorer short-circuits before vector compute"
    )
  }

  @Test("similarityScores embeds each unique episode in a batch and caches the whole batch")
  func batchScoresEmbedsEachEpisodeAndCaches() async throws {
    let counter = ThreadSafe(0)
    registerEmbeddable(revision: 1, counter: counter)

    let podcast = try Create.unsavedPodcast()
    let first = UnsavedPodcastEpisode(
      unsavedPodcast: podcast,
      unsavedEpisode: try Create.unsavedEpisode(title: "First Episode")
    )
    let second = UnsavedPodcastEpisode(
      unsavedPodcast: podcast,
      unsavedEpisode: try Create.unsavedEpisode(title: "Second Episode")
    )
    #expect(first.mediaGUID != second.mediaGUID)

    let scorer = UnsavedEpisodeEmbeddingScorer()

    _ = try await scorer.similarityScores(for: [first])
    let singleCount = counter()
    #expect(singleCount > 0, "Scoring one episode must hit the embeddable")

    let batch = try await scorer.similarityScores(for: [first, second])
    let batchCount = counter()
    #expect(batch.cacheable)
    #expect(
      batchCount > singleCount,
      "Batch must embed the new (second) episode while reusing the cached first"
    )

    _ = try await scorer.similarityScores(for: [first, second])
    #expect(
      counter() == batchCount,
      "Re-scoring the same (mediaGUID, source) batch must reuse cached vectors for both episodes"
    )
  }

  @Test("drops cached vectors when the embedding revision changes")
  func dropsCacheOnRevisionChange() async throws {
    let counter1 = ThreadSafe(0)
    registerEmbeddable(revision: 1, counter: counter1)

    let episode = try unsavedPodcastEpisode()
    let scorer = UnsavedEpisodeEmbeddingScorer()

    _ = try await scorer.similarityScore(for: episode)
    let firstCallCount = counter1()
    #expect(firstCallCount > 0)

    _ = try await scorer.similarityScore(for: episode)
    #expect(counter1() == firstCallCount, "Sanity: second call hits cache before revision bump")

    let counter2 = ThreadSafe(0)
    registerEmbeddable(revision: 2, counter: counter2)

    _ = try await scorer.similarityScore(for: episode)
    #expect(
      counter2() > 0,
      "A revision change must drop the cache and force a re-embed against the new model"
    )
  }

  // MARK: - Helpers

  private func registerEmbeddable(
    assetsAvailable: Bool = true,
    revision: Int,
    counter: ThreadSafe<Int>
  ) {
    let embeddable = MutableEmbeddable(
      assetsAvailable: assetsAvailable,
      revision: revision,
      vectorFor: { _ in
        counter { $0 += 1 }
        return [1, 0, 0]
      }
    )
    Container.shared.contextualEmbedding.reset()
      .register { ContextualEmbedding(embedding: embeddable) }
      .scope(.cached)
  }

  private func unsavedPodcastEpisode() throws -> UnsavedPodcastEpisode {
    UnsavedPodcastEpisode(
      unsavedPodcast: try Create.unsavedPodcast(),
      unsavedEpisode: try Create.unsavedEpisode()
    )
  }
}
