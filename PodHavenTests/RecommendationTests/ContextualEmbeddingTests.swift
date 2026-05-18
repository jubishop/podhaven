// Copyright Justin Bishop, 2026

import Foundation
import Testing

@testable import PodHaven

@Suite("ContextualEmbedding tests")
struct ContextualEmbeddingTests {

  // MARK: - requestAndLoadAssetsIfNeeded

  @Test("loads immediately when assets are available")
  func loadsWhenAssetsAvailable() async {
    let fake = ControllableEmbeddable(hasAvailableAssets: true)
    let embedding = ContextualEmbedding(embedding: fake)

    #expect(!embedding.assetsLoaded.isFinished)
    await embedding.requestAndLoadAssetsIfNeeded()
    #expect(embedding.assetsLoaded.isFinished)
    #expect(fake.loadCount == 1)
    #expect(fake.requestAssetsCount == 0)
  }

  @Test("requests download when assets are not available")
  func requestsDownloadWhenAssetsUnavailable() async {
    let fake = ControllableEmbeddable(hasAvailableAssets: false)
    let embedding = ContextualEmbedding(embedding: fake)

    await embedding.requestAndLoadAssetsIfNeeded()
    #expect(!embedding.assetsLoaded.isFinished)
    #expect(fake.loadCount == 0)
    #expect(fake.requestAssetsCount == 1)
  }

  @Test("is idempotent once loaded")
  func idempotentOnceLoaded() async {
    let fake = ControllableEmbeddable(hasAvailableAssets: true)
    let embedding = ContextualEmbedding(embedding: fake)

    await embedding.requestAndLoadAssetsIfNeeded()
    await embedding.requestAndLoadAssetsIfNeeded()
    await embedding.requestAndLoadAssetsIfNeeded()
    #expect(fake.loadCount == 1)
  }

  @Test("does not request assets again if already requested")
  func doesNotReRequestAssets() async {
    let fake = ControllableEmbeddable(hasAvailableAssets: false)
    let embedding = ContextualEmbedding(embedding: fake)

    await embedding.requestAndLoadAssetsIfNeeded()
    await embedding.requestAndLoadAssetsIfNeeded()
    #expect(fake.requestAssetsCount == 1)

    // Simulate assets arriving
    fake.hasAvailableAssets = true
    await embedding.requestAndLoadAssetsIfNeeded()
    #expect(embedding.assetsLoaded.isFinished)
    #expect(fake.loadCount == 1)
    #expect(fake.requestAssetsCount == 1)
  }

  // MARK: - loadAssetsIfAvailable

  @Test("loadAssetsIfAvailable loads when assets are on disk")
  func loadIfAvailableLoadsWhenOnDisk() async {
    let fake = ControllableEmbeddable(hasAvailableAssets: true)
    let embedding = ContextualEmbedding(embedding: fake)

    await embedding.loadAssetsIfAvailable()
    #expect(embedding.assetsLoaded.isFinished)
    #expect(fake.loadCount == 1)
    #expect(fake.requestAssetsCount == 0)
  }

  @Test("loadAssetsIfAvailable does not trigger a download")
  func loadIfAvailableDoesNotDownload() async {
    let fake = ControllableEmbeddable(hasAvailableAssets: false)
    let embedding = ContextualEmbedding(embedding: fake)

    await embedding.loadAssetsIfAvailable()
    #expect(!embedding.assetsLoaded.isFinished)
    #expect(fake.loadCount == 0)
    #expect(fake.requestAssetsCount == 0)
  }

  @Test("loadAssetsIfAvailable is a no-op when already loaded")
  func loadIfAvailableIdempotent() async {
    let fake = ControllableEmbeddable(hasAvailableAssets: true)
    let embedding = ContextualEmbedding(embedding: fake)

    await embedding.loadAssetsIfAvailable()
    await embedding.loadAssetsIfAvailable()
    #expect(fake.loadCount == 1)
  }

  // MARK: - vector(for:)

  @Test("throws when not available")
  func vectorThrowsWhenUnavailable() async {
    let fake = ControllableEmbeddable(hasAvailableAssets: false)
    let embedding = ContextualEmbedding(embedding: fake)

    await #expect(throws: EmbeddingError.modelUnavailable) {
      _ = try await embedding.vector(for: "test")
    }
  }

  @Test("pools single token vector correctly")
  func poolsSingleToken() async throws {
    let fake = ControllableEmbeddable(
      hasAvailableAssets: true,
      vectors: [[1.0, 2.0, 3.0]]
    )
    let embedding = ContextualEmbedding(embedding: fake)
    await embedding.requestAndLoadAssetsIfNeeded()

    let result = try await embedding.vector(for: "test")
    #expect(result == [1.0, 2.0, 3.0])
  }

  @Test("averages multiple token vectors")
  func averagesMultipleTokens() async throws {
    let fake = ControllableEmbeddable(
      hasAvailableAssets: true,
      vectors: [
        [2.0, 4.0],
        [6.0, 8.0],
      ]
    )
    let embedding = ContextualEmbedding(embedding: fake)
    await embedding.requestAndLoadAssetsIfNeeded()

    let result = try await embedding.vector(for: "two tokens")
    #expect(result == [4.0, 6.0])
  }

  @Test("throws noResult for empty token vectors")
  func throwsNoResultForEmptyTokens() async {
    let fake = ControllableEmbeddable(
      hasAvailableAssets: true,
      vectors: []
    )
    let embedding = ContextualEmbedding(embedding: fake)
    await embedding.requestAndLoadAssetsIfNeeded()

    await #expect(throws: EmbeddingError.noResult) {
      _ = try await embedding.vector(for: "empty")
    }
  }

  // MARK: - Property delegation

  @Test("revision delegates to underlying embeddable")
  func revisionDelegates() {
    let fake = ControllableEmbeddable(hasAvailableAssets: true, revision: 42)
    let embedding = ContextualEmbedding(embedding: fake)
    #expect(embedding.revision == 42)
  }

  // MARK: - assetsLoaded latch

  @Test("assetsLoaded.wait resumes when loadAssetsIfAvailable succeeds")
  func assetsLoadedLatchResumesOnLoad() async throws {
    let fake = ControllableEmbeddable(hasAvailableAssets: false)
    let embedding = ContextualEmbedding(embedding: fake)
    let resumed = ThreadSafe(false)
    let latch = embedding.assetsLoaded

    let waiter = Task {
      try await latch.wait()
      resumed(true)
    }

    for _ in 0..<10 { await Task.yield() }
    #expect(!resumed())

    fake.hasAvailableAssets = true
    await embedding.loadAssetsIfAvailable()
    try await waiter.value
    #expect(resumed())
  }
}

// MARK: - Controllable Fake

// Mutable test fake — `hasAvailableAssets` is flipped by tests to simulate
// asset arrival after construction. `@unchecked Sendable` is acceptable in
// test code (per CLAUDE.md) since tests serialize access via awaits on the
// actor.
private final class ControllableEmbeddable: Embeddable, @unchecked Sendable {
  var hasAvailableAssets: Bool
  let revision: Int
  let vectors: [[Double]]

  private(set) var loadCount = 0
  private(set) var requestAssetsCount = 0

  init(
    hasAvailableAssets: Bool,
    vectors: [[Double]] = [[0.5, 0.5, 0.5]],
    revision: Int = 1
  ) {
    self.hasAvailableAssets = hasAvailableAssets
    self.vectors = vectors
    self.revision = revision
  }

  func load() throws {
    loadCount += 1
  }

  func requestAssets(completion: @escaping @Sendable ((any Error)?) -> Void) {
    requestAssetsCount += 1
    completion(nil)
  }

  func embeddingResult(for string: String) throws -> any EmbeddableResult {
    FakeEmbeddingResult(vectors: vectors)
  }
}
