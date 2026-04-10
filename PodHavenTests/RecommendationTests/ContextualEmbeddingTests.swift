// Copyright Justin Bishop, 2026

import Foundation
import Testing

@testable import PodHaven

@Suite("ContextualEmbedding tests")
struct ContextualEmbeddingTests {

  // MARK: - requestAndLoadAssetsIfNeeded

  @Test("loads immediately when assets are available")
  func loadsWhenAssetsAvailable() {
    let fake = ControllableEmbeddable(hasAvailableAssets: true)
    let embedding = ContextualEmbedding(embedding: fake)

    #expect(!embedding.isAvailable)
    embedding.requestAndLoadAssetsIfNeeded()
    #expect(embedding.isAvailable)
    #expect(fake.loadCount == 1)
    #expect(fake.requestAssetsCount == 0)
  }

  @Test("requests download when assets are not available")
  func requestsDownloadWhenAssetsUnavailable() {
    let fake = ControllableEmbeddable(hasAvailableAssets: false)
    let embedding = ContextualEmbedding(embedding: fake)

    embedding.requestAndLoadAssetsIfNeeded()
    #expect(!embedding.isAvailable)
    #expect(fake.loadCount == 0)
    #expect(fake.requestAssetsCount == 1)
  }

  @Test("is idempotent once loaded")
  func idempotentOnceLoaded() {
    let fake = ControllableEmbeddable(hasAvailableAssets: true)
    let embedding = ContextualEmbedding(embedding: fake)

    embedding.requestAndLoadAssetsIfNeeded()
    embedding.requestAndLoadAssetsIfNeeded()
    embedding.requestAndLoadAssetsIfNeeded()
    #expect(fake.loadCount == 1)
  }

  @Test("does not request assets again if already requested")
  func doesNotReRequestAssets() {
    let fake = ControllableEmbeddable(hasAvailableAssets: false)
    let embedding = ContextualEmbedding(embedding: fake)

    embedding.requestAndLoadAssetsIfNeeded()
    embedding.requestAndLoadAssetsIfNeeded()
    #expect(fake.requestAssetsCount == 1)

    // Simulate assets arriving
    fake.hasAvailableAssets = true
    embedding.requestAndLoadAssetsIfNeeded()
    #expect(embedding.isAvailable)
    #expect(fake.loadCount == 1)
    #expect(fake.requestAssetsCount == 1)
  }

  // MARK: - vector(for:)

  @Test("throws when not available")
  func vectorThrowsWhenUnavailable() {
    let fake = ControllableEmbeddable(hasAvailableAssets: false)
    let embedding = ContextualEmbedding(embedding: fake)

    #expect(throws: EmbeddingError.modelUnavailable) {
      _ = try embedding.vector(for: "test")
    }
  }

  @Test("pools single token vector correctly")
  func poolsSingleToken() throws {
    let fake = ControllableEmbeddable(
      hasAvailableAssets: true,
      vectors: [[1.0, 2.0, 3.0]]
    )
    let embedding = ContextualEmbedding(embedding: fake)
    embedding.requestAndLoadAssetsIfNeeded()

    let result = try embedding.vector(for: "test")
    #expect(result == [1.0, 2.0, 3.0])
  }

  @Test("averages multiple token vectors")
  func averagesMultipleTokens() throws {
    let fake = ControllableEmbeddable(
      hasAvailableAssets: true,
      vectors: [
        [2.0, 4.0],
        [6.0, 8.0],
      ]
    )
    let embedding = ContextualEmbedding(embedding: fake)
    embedding.requestAndLoadAssetsIfNeeded()

    let result = try embedding.vector(for: "two tokens")
    #expect(result == [4.0, 6.0])
  }

  @Test("throws noResult for empty token vectors")
  func throwsNoResultForEmptyTokens() {
    let fake = ControllableEmbeddable(
      hasAvailableAssets: true,
      vectors: []
    )
    let embedding = ContextualEmbedding(embedding: fake)
    embedding.requestAndLoadAssetsIfNeeded()

    #expect(throws: EmbeddingError.noResult) {
      _ = try embedding.vector(for: "empty")
    }
  }

  // MARK: - Property delegation

  @Test("revision delegates to underlying embeddable")
  func revisionDelegates() {
    let fake = ControllableEmbeddable(hasAvailableAssets: true, revision: 42)
    let embedding = ContextualEmbedding(embedding: fake)
    #expect(embedding.revision == 42)
  }

  @Test("maximumSequenceLength delegates to underlying embeddable")
  func maximumSequenceLengthDelegates() {
    let fake = ControllableEmbeddable(
      hasAvailableAssets: true,
      maximumSequenceLength: 512
    )
    let embedding = ContextualEmbedding(embedding: fake)
    #expect(embedding.maximumSequenceLength == 512)
  }
}

// MARK: - Controllable Fake

private class ControllableEmbeddable: Embeddable {
  var hasAvailableAssets: Bool
  let revision: Int
  let maximumSequenceLength: Int
  let vectors: [[Double]]

  private(set) var loadCount = 0
  private(set) var requestAssetsCount = 0

  init(
    hasAvailableAssets: Bool,
    vectors: [[Double]] = [[0.5, 0.5, 0.5]],
    revision: Int = 1,
    maximumSequenceLength: Int = 1000
  ) {
    self.hasAvailableAssets = hasAvailableAssets
    self.vectors = vectors
    self.revision = revision
    self.maximumSequenceLength = maximumSequenceLength
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
