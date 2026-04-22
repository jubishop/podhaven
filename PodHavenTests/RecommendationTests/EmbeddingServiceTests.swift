// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("EmbeddingService tests", .container)
class EmbeddingServiceTests {
  @DynamicInjected(\.appDB) private var appDB
  @DynamicInjected(\.repo) private var repo

  // MARK: - Text Cleaning

  @Test("cleanText strips HTML tags")
  func cleanTextHTML() {
    let result = EmbeddingService.cleanText("<p>Hello <b>world</b></p>")
    #expect(result == "Hello world")
  }

  @Test("cleanText strips URLs")
  func cleanTextURLs() {
    let result = EmbeddingService.cleanText("Visit https://example.com for more")
    #expect(result == "Visit for more")
  }

  @Test("cleanText strips timestamps")
  func cleanTextTimestamps() {
    let result = EmbeddingService.cleanText("0:00 Intro 2:15 Main topic 1:02:15 Outro")
    #expect(result == "Intro Main topic Outro")
  }

  @Test("cleanText normalizes whitespace")
  func cleanTextWhitespace() {
    let result = EmbeddingService.cleanText("  too   many    spaces  ")
    #expect(result == "too many spaces")
  }

  @Test("cleanText decodes named HTML entities")
  func cleanTextNamedEntities() {
    let result = EmbeddingService.cleanText("Tom &amp; Jerry &ndash; reunion &hellip;")
    #expect(result == "Tom & Jerry \u{2013} reunion \u{2026}")
  }

  @Test("cleanText decodes numeric and hex HTML entities")
  func cleanTextNumericEntities() {
    let result = EmbeddingService.cleanText("smart quotes: &#8220;hi&#8221; and &#x2014; dash")
    #expect(result == "smart quotes: \u{201C}hi\u{201D} and \u{2014} dash")
  }

  @Test("cleanText strips tags revealed by entity decoding")
  func cleanTextEntityThenTag() {
    // Entities decode first, so &lt;script&gt; becomes <script> and is then stripped.
    let result = EmbeddingService.cleanText("real &lt;script&gt;bad&lt;/script&gt; content")
    #expect(result == "real bad content")
  }

  // MARK: - Input Forwarding

  @Test("upsertEpisodeEmbeddings forwards full cleaned text without length truncation")
  func fullTextForwarded() async throws {
    // Build a description that would have been truncated under the old
    // prefix(maximumSequenceLength) behavior, confirming the full string
    // reaches embeddingResult(for:).
    let longDescription = String(repeating: "word ", count: 500).trimmed()
    let longPodcastDescription = String(repeating: "pod ", count: 500).trimmed()

    let podcastEpisode = try await makePodcastEpisode(
      podcastDescription: longPodcastDescription,
      episodeTitle: "Forwarding Test",
      episodeDescription: longDescription
    )

    let recorder = RecordingEmbeddable()
    let embedding = makeContextualEmbedding(recorder)

    try await EmbeddingService.upsertEpisodeEmbeddings(
      for: [podcastEpisode.episode],
      embedding: embedding
    )

    let seen = recorder.seenInputs()
    #expect(seen.contains(longDescription))
    #expect(seen.contains(longPodcastDescription))
  }

  // MARK: - Embedding Caching

  @Test("upsertEpisodeEmbeddings caches results and skips already computed")
  func upsertEpisodeEmbeddingsCaching() async throws {
    let podcastEpisode = try await makePodcastEpisode(
      podcastDescription: "",
      episodeTitle: "Test Episode",
      episodeDescription: "Test description"
    )
    let episode = podcastEpisode.episode

    let embedding = makeContextualEmbedding()

    // First call should compute and cache
    try await EmbeddingService.upsertEpisodeEmbeddings(
      for: [episode],
      embedding: embedding
    )

    let cached = try await repo.embedding(for: episode.id)
    #expect(cached != nil)
    #expect(cached?.dimension == 3)

    // Second call should skip (already cached)
    let originalComputedAt = cached!.creationDate
    try await EmbeddingService.upsertEpisodeEmbeddings(
      for: [episode],
      embedding: embedding
    )

    let cached2 = try await repo.embedding(for: episode.id)
    #expect(cached2?.creationDate == originalComputedAt)
  }

  // MARK: - Source Hash Invalidation

  @Test("stale sourceHash triggers recomputation")
  func sourceHashInvalidation() async throws {
    let podcastEpisode = try await makePodcastEpisode(
      podcastDescription: "",
      episodeTitle: "Test Title",
      episodeDescription: "Test description"
    )
    let episode = podcastEpisode.episode
    let embedding = makeContextualEmbedding()

    // First compute normally to get the correct hash
    try await EmbeddingService.upsertEpisodeEmbeddings(
      for: [episode],
      embedding: embedding
    )
    let correctHash = try await repo.embedding(for: episode.id)!.sourceHash
    let correctVector = try await repo.embedding(for: episode.id)!.floatVector

    // Overwrite with a stale hash but different vector
    let staleVector: [Float] = [99.0, 99.0, 99.0]
    let staleEmbedding = UnsavedEpisodeEmbedding(
      episodeId: episode.id,
      vector: UnsavedEpisodeEmbedding.vectorData(from: staleVector),
      sourceHash: "stale-hash",
      embeddingRevision: 1,
      dimension: 3
    )
    try await repo.upsertEmbedding(staleEmbedding)

    // Verify stale embedding was saved
    let afterStale = try await repo.embedding(for: episode.id)!
    #expect(afterStale.sourceHash == "stale-hash")

    // Recompute — should detect stale hash and recompute
    try await EmbeddingService.upsertEpisodeEmbeddings(
      for: [episode],
      embedding: embedding
    )

    let refreshed = try await repo.embedding(for: episode.id)!
    #expect(refreshed.sourceHash == correctHash)
    #expect(refreshed.floatVector == correctVector)
  }

  @Test("embedding revision changes trigger recomputation")
  func revisionInvalidation() async throws {
    let podcastEpisode = try await makePodcastEpisode(
      podcastDescription: "",
      episodeTitle: "Revision Test",
      episodeDescription: "Episode description"
    )
    let episode = podcastEpisode.episode
    let firstEmbedding = makeContextualEmbedding(
      RevisionedEmbeddable(revision: 1)
    )
    let secondEmbedding = makeContextualEmbedding(
      RevisionedEmbeddable(revision: 2)
    )

    try await EmbeddingService.upsertEpisodeEmbeddings(
      for: [episode],
      embedding: firstEmbedding
    )

    let cached = try #require(try await repo.embedding(for: episode.id))
    #expect(cached.embeddingRevision == 1)

    try await EmbeddingService.upsertEpisodeEmbeddings(
      for: [episode],
      embedding: secondEmbedding
    )

    let refreshed = try #require(try await repo.embedding(for: episode.id))
    #expect(refreshed.embeddingRevision == 2)
    #expect(refreshed.sourceHash == cached.sourceHash)
    #expect(refreshed.floatVector == cached.floatVector)
  }

  @Test("podcast description changes invalidate cached episode and podcast embeddings")
  func podcastDescriptionInvalidation() async throws {
    let podcastEpisode = try await makePodcastEpisode(
      podcastDescription: "Original podcast summary",
      episodeTitle: "Podcast Refresh",
      episodeDescription: "Episode description"
    )
    let embedding = makeContextualEmbedding()

    try await EmbeddingService.upsertEpisodeEmbeddings(
      for: [podcastEpisode.episode],
      embedding: embedding
    )

    let initialEpisodeEmbedding = try #require(
      try await repo.embedding(for: podcastEpisode.episode.id)
    )
    let initialPodcastEmbedding = try #require(
      try await repo.podcastEmbedding(for: podcastEpisode.podcast.id)
    )

    let updatedPodcast = try makeUnsavedPodcast(
      from: podcastEpisode.podcast,
      description: "Updated podcast summary"
    )
    let refreshedPodcastEpisode = try await repo.upsertPodcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: updatedPodcast,
        unsavedEpisode: try podcastEpisode.episode.toOriginalUnsavedEpisode()
      )
    )

    try await EmbeddingService.upsertEpisodeEmbeddings(
      for: [refreshedPodcastEpisode.episode],
      embedding: embedding
    )

    let refreshedEpisodeEmbedding = try #require(
      try await repo.embedding(for: refreshedPodcastEpisode.episode.id)
    )
    let refreshedPodcastEmbedding = try #require(
      try await repo.podcastEmbedding(for: refreshedPodcastEpisode.podcast.id)
    )

    #expect(refreshedEpisodeEmbedding.sourceHash != initialEpisodeEmbedding.sourceHash)
    #expect(refreshedEpisodeEmbedding.floatVector != initialEpisodeEmbedding.floatVector)
    #expect(refreshedPodcastEmbedding.sourceHash != initialPodcastEmbedding.sourceHash)
    #expect(refreshedPodcastEmbedding.floatVector != initialPodcastEmbedding.floatVector)
  }

  @Test("stale cached podcast embeddings are refreshed before reuse")
  func stalePodcastEmbeddingRefresh() async throws {
    let podcastEpisode = try await makePodcastEpisode(
      podcastDescription: "Podcast summary",
      episodeTitle: "Podcast Cache Refresh",
      episodeDescription: "Episode description"
    )
    let embedding = makeContextualEmbedding()

    let staleVector: [Float] = [99.0, 99.0, 99.0]
    let staleEmbedding = UnsavedPodcastEmbedding(
      podcastId: podcastEpisode.podcast.id,
      vector: UnsavedPodcastEmbedding.vectorData(from: staleVector),
      sourceHash: "stale-hash",
      embeddingRevision: embedding.revision,
      dimension: staleVector.count
    )
    try await repo.upsertPodcastEmbedding(staleEmbedding)

    let cachedBeforeRefresh = try #require(
      try await repo.podcastEmbedding(for: podcastEpisode.podcast.id)
    )
    #expect(cachedBeforeRefresh.sourceHash == "stale-hash")

    try await EmbeddingService.upsertEpisodeEmbeddings(
      for: [podcastEpisode.episode],
      embedding: embedding
    )

    let refreshedPodcastEmbedding = try #require(
      try await repo.podcastEmbedding(for: podcastEpisode.podcast.id)
    )
    #expect(refreshedPodcastEmbedding.sourceHash != "stale-hash")
    #expect(refreshedPodcastEmbedding.embeddingRevision == embedding.revision)
    #expect(refreshedPodcastEmbedding.floatVector != cachedBeforeRefresh.floatVector)
  }

  @Test("embedding upserts replace existing rows instead of inserting duplicates")
  func embeddingUpsertsReplaceExistingRows() async throws {
    let podcastEpisode = try await makePodcastEpisode(
      podcastDescription: "Podcast summary",
      episodeTitle: "Upsert Coverage",
      episodeDescription: "Episode description"
    )

    let firstEpisodeEmbedding = UnsavedEpisodeEmbedding(
      episodeId: podcastEpisode.episode.id,
      vector: UnsavedEpisodeEmbedding.vectorData(from: [1.0, 0.0, 0.0]),
      sourceHash: "episode-hash-1",
      embeddingRevision: 1,
      dimension: 3
    )
    let secondEpisodeEmbedding = UnsavedEpisodeEmbedding(
      episodeId: podcastEpisode.episode.id,
      vector: UnsavedEpisodeEmbedding.vectorData(from: [0.0, 1.0, 0.0]),
      sourceHash: "episode-hash-2",
      embeddingRevision: 2,
      dimension: 3
    )
    try await repo.upsertEmbedding(firstEpisodeEmbedding)
    try await repo.upsertEmbedding(secondEpisodeEmbedding)

    let firstPodcastEmbedding = UnsavedPodcastEmbedding(
      podcastId: podcastEpisode.podcast.id,
      vector: UnsavedPodcastEmbedding.vectorData(from: [0.0, 0.0, 1.0]),
      sourceHash: "podcast-hash-1",
      embeddingRevision: 1,
      dimension: 3
    )
    let secondPodcastEmbedding = UnsavedPodcastEmbedding(
      podcastId: podcastEpisode.podcast.id,
      vector: UnsavedPodcastEmbedding.vectorData(from: [0.5, 0.5, 0.5]),
      sourceHash: "podcast-hash-2",
      embeddingRevision: 2,
      dimension: 3
    )
    try await repo.upsertPodcastEmbedding(firstPodcastEmbedding)
    try await repo.upsertPodcastEmbedding(secondPodcastEmbedding)

    let savedEpisodeEmbedding = try #require(
      try await repo.embedding(for: podcastEpisode.episode.id)
    )
    let savedPodcastEmbedding = try #require(
      try await repo.podcastEmbedding(for: podcastEpisode.podcast.id)
    )
    let episodeRowCount = try #require(
      try await appDB.db.read { db in
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM episodeEmbedding WHERE episodeId = ?",
          arguments: [podcastEpisode.episode.id]
        )
      }
    )
    let podcastRowCount = try #require(
      try await appDB.db.read { db in
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM podcastEmbedding WHERE podcastId = ?",
          arguments: [podcastEpisode.podcast.id]
        )
      }
    )

    #expect(savedEpisodeEmbedding.sourceHash == "episode-hash-2")
    #expect(savedEpisodeEmbedding.embeddingRevision == 2)
    #expect(savedPodcastEmbedding.sourceHash == "podcast-hash-2")
    #expect(savedPodcastEmbedding.embeddingRevision == 2)
    #expect(episodeRowCount == 1)
    #expect(podcastRowCount == 1)
  }

  // MARK: - Helpers

  private func makeContextualEmbedding(
    _ embeddable: some Embeddable = FakeEmbeddable()
  ) -> ContextualEmbedding {
    let embedding = ContextualEmbedding(embedding: embeddable)
    embedding.requestAndLoadAssetsIfNeeded()
    return embedding
  }

  private func makePodcastEpisode(
    podcastDescription: String,
    episodeTitle: String,
    episodeDescription: String
  ) async throws -> PodcastEpisode {
    let podcastEpisodes = try await repo.upsertPodcastEpisodes([
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(description: podcastDescription),
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

private struct RevisionedEmbeddable: Embeddable {
  var hasAvailableAssets = true
  let revision: Int

  func load() throws {}
  func requestAssets(completion: @escaping @Sendable ((any Error)?) -> Void) { completion(nil) }

  func embeddingResult(for string: String) throws -> any EmbeddableResult {
    try FakeEmbeddable().embeddingResult(for: string)
  }
}

private final class RecordingEmbeddable: Embeddable {
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
