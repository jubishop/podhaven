// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("EmbeddingService tests", .container)
class EmbeddingServiceTests {
  @DynamicInjected(\.appDB) private var appDB
  @DynamicInjected(\.recommendationRepo) private var recommendationRepo
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
    let embedding = await makeContextualEmbedding(recorder)

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

    let embedding = await makeContextualEmbedding()

    // First call should compute and cache
    try await EmbeddingService.upsertEpisodeEmbeddings(
      for: [episode],
      embedding: embedding
    )

    let cached = try await recommendationRepo.embedding(for: episode.id)
    #expect(cached != nil)
    #expect(cached?.dimension == 3)

    // Second call should skip (already cached)
    let originalComputedAt = cached!.creationDate
    try await EmbeddingService.upsertEpisodeEmbeddings(
      for: [episode],
      embedding: embedding
    )

    let cached2 = try await recommendationRepo.embedding(for: episode.id)
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
    let embedding = await makeContextualEmbedding()

    // First compute normally to get the correct hash
    try await EmbeddingService.upsertEpisodeEmbeddings(
      for: [episode],
      embedding: embedding
    )
    let correctHash = try await recommendationRepo.embedding(for: episode.id)!.sourceHash
    let correctVector = try await recommendationRepo.embedding(for: episode.id)!.floatVector

    // Overwrite with a stale hash but different vector
    let staleVector: [Float] = [99.0, 99.0, 99.0]
    let staleEmbedding = UnsavedEpisodeEmbedding(
      episodeId: episode.id,
      vector: UnsavedEpisodeEmbedding.vectorData(from: staleVector),
      sourceHash: "stale-hash",
      embeddingRevision: 1,
      dimension: 3,
      verificationDate: Date()
    )
    try await recommendationRepo.upsertEmbeddings([staleEmbedding])

    // Verify stale embedding was saved
    let afterStale = try await recommendationRepo.embedding(for: episode.id)!
    #expect(afterStale.sourceHash == "stale-hash")

    // Recompute — should detect stale hash and recompute
    try await EmbeddingService.upsertEpisodeEmbeddings(
      for: [episode],
      embedding: embedding
    )

    let refreshed = try await recommendationRepo.embedding(for: episode.id)!
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
    let firstEmbedding = await makeContextualEmbedding(
      RevisionedEmbeddable(revision: 1)
    )
    let secondEmbedding = await makeContextualEmbedding(
      RevisionedEmbeddable(revision: 2)
    )

    try await EmbeddingService.upsertEpisodeEmbeddings(
      for: [episode],
      embedding: firstEmbedding
    )

    let cached = try #require(try await recommendationRepo.embedding(for: episode.id))
    #expect(cached.embeddingRevision == 1)

    try await EmbeddingService.upsertEpisodeEmbeddings(
      for: [episode],
      embedding: secondEmbedding
    )

    let refreshed = try #require(try await recommendationRepo.embedding(for: episode.id))
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
    let embedding = await makeContextualEmbedding()

    try await EmbeddingService.upsertEpisodeEmbeddings(
      for: [podcastEpisode.episode],
      embedding: embedding
    )

    let initialEpisodeEmbedding = try #require(
      try await recommendationRepo.embedding(for: podcastEpisode.episode.id)
    )
    let initialPodcastEmbedding = try #require(
      try await recommendationRepo.podcastEmbedding(for: podcastEpisode.podcast.id)
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
      try await recommendationRepo.embedding(for: refreshedPodcastEpisode.episode.id)
    )
    let refreshedPodcastEmbedding = try #require(
      try await recommendationRepo.podcastEmbedding(for: refreshedPodcastEpisode.podcast.id)
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
    let embedding = await makeContextualEmbedding()

    let staleVector: [Float] = [99.0, 99.0, 99.0]
    let staleEmbedding = UnsavedPodcastEmbedding(
      podcastId: podcastEpisode.podcast.id,
      vector: UnsavedPodcastEmbedding.vectorData(from: staleVector),
      sourceHash: "stale-hash",
      embeddingRevision: embedding.revision,
      dimension: staleVector.count
    )
    try await recommendationRepo.upsertPodcastEmbeddings([staleEmbedding])

    let cachedBeforeRefresh = try #require(
      try await recommendationRepo.podcastEmbedding(for: podcastEpisode.podcast.id)
    )
    #expect(cachedBeforeRefresh.sourceHash == "stale-hash")

    try await EmbeddingService.upsertEpisodeEmbeddings(
      for: [podcastEpisode.episode],
      embedding: embedding
    )

    let refreshedPodcastEmbedding = try #require(
      try await recommendationRepo.podcastEmbedding(for: podcastEpisode.podcast.id)
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
      dimension: 3,
      verificationDate: Date()
    )
    let secondEpisodeEmbedding = UnsavedEpisodeEmbedding(
      episodeId: podcastEpisode.episode.id,
      vector: UnsavedEpisodeEmbedding.vectorData(from: [0.0, 1.0, 0.0]),
      sourceHash: "episode-hash-2",
      embeddingRevision: 2,
      dimension: 3,
      verificationDate: Date()
    )
    try await recommendationRepo.upsertEmbeddings([firstEpisodeEmbedding, secondEpisodeEmbedding])

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
    try await recommendationRepo.upsertPodcastEmbeddings([
      firstPodcastEmbedding, secondPodcastEmbedding,
    ])

    let savedEpisodeEmbedding = try #require(
      try await recommendationRepo.embedding(for: podcastEpisode.episode.id)
    )
    let savedPodcastEmbedding = try #require(
      try await recommendationRepo.podcastEmbedding(for: podcastEpisode.podcast.id)
    )
    let episodeRowCount = try #require(
      try await appDB.unsafeTestDB.read { db in
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM episodeEmbedding WHERE episodeId = ?",
          arguments: [podcastEpisode.episode.id]
        )
      }
    )
    let podcastRowCount = try #require(
      try await appDB.unsafeTestDB.read { db in
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

  // MARK: - Verification Touch

  // Regression: episodesNeedingEmbeddings used to compare contentUpdatedAt
  // against creationDate, but the EmbeddingService loop short-circuits when
  // the source hash matches — so for any contentUpdatedAt bump that didn't
  // change cleaned title/description (e.g. a feed refresh that touched a
  // non-content field), the same episode came back forever. The fix splits
  // a mutable verificationDate out of creationDate and touches it on the
  // hash-match skip path.
  @Test("hash-stable contentUpdatedAt bump no longer requeues the episode forever")
  func verificationDateTouchDrainsQueue() async throws {
    let pe = try await makePodcastEpisode(
      podcastTitle: "Stable Pod",
      podcastDescription: "Stable pod desc",
      episodeTitle: "Stable Title",
      episodeDescription: "Stable desc"
    )
    let embedding = await makeContextualEmbedding()

    try await EmbeddingService.upsertEpisodeEmbeddings(
      for: [pe.episode],
      embedding: embedding
    )

    // Force verificationDate < contentUpdatedAt without going through the
    // title/description trigger, so the cleaned-text hash stays identical
    // and the service's needsRecompute guard skips the vector recompute.
    // Use fixed past dates so the assertion doesn't depend on test-runner
    // clock skew between the initial upsert and the touch.
    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          UPDATE episodeEmbedding SET verificationDate = '2020-01-01 00:00:00'
          WHERE episodeId = ?
          """,
        arguments: [pe.episode.id]
      )
      try db.execute(
        sql: """
          UPDATE episode SET contentUpdatedAt = '2020-06-01 00:00:00'
          WHERE id = ?
          """,
        arguments: [pe.episode.id]
      )
    }

    let staleQueue = try await recommendationRepo.episodesNeedingEmbeddings(
      revision: embedding.revision
    )
    #expect(staleQueue.contains(pe.episode.id))

    let refreshed = try await recommendationRepo.episodes(for: [pe.episode.id])
    try await EmbeddingService.upsertEpisodeEmbeddings(
      for: refreshed,
      embedding: embedding
    )

    let drainedQueue = try await recommendationRepo.episodesNeedingEmbeddings(
      revision: embedding.revision
    )
    #expect(!drainedQueue.contains(pe.episode.id))
  }

  // MARK: - Recipe Stability

  // Golden-value lock on the full recipe: recipeVersion prefix, 0x1F
  // component separator, component ordering, and cleanText behavior for
  // already-clean inputs. Any drift here (knob tweak without recipeVersion
  // bump, accidental cleanText change, component reordering) fails this test
  // and forces an explicit decision.
  @Test("source hash is stable for known input (golden value)")
  func sourceHashGolden() async throws {
    let pe = try await makePodcastEpisode(
      podcastTitle: "Known pod title",
      podcastDescription: "Known pod desc",
      episodeTitle: "Known title",
      episodeDescription: "Known ep desc"
    )
    let embedding = await makeContextualEmbedding()

    try await EmbeddingService.upsertEpisodeEmbeddings(
      for: [pe.episode],
      embedding: embedding
    )

    let saved = try #require(try await recommendationRepo.embedding(for: pe.episode.id))
    #expect(
      saved.sourceHash
        == "eeb76b9a3fd52168f833cb5a502110d190f699ae005da759c3497b93b4423702"
    )
  }

  // MARK: - Podcast Vector Edge Cases

  @Test("empty podcast description still produces podcastEmbedding via title")
  func emptyPodcastDescriptionUsesTitle() async throws {
    let pe = try await makePodcastEpisode(
      podcastDescription: "",
      episodeTitle: "Title",
      episodeDescription: "Description"
    )
    let embedding = await makeContextualEmbedding()

    try await EmbeddingService.upsertEpisodeEmbeddings(
      for: [pe.episode],
      embedding: embedding
    )

    #expect(try await recommendationRepo.podcastEmbedding(for: pe.podcast.id) != nil)
    #expect(try await recommendationRepo.embedding(for: pe.episode.id) != nil)
  }

  // MARK: - Batch Robustness

  @Test("one throwing episode does not abort the rest of the batch")
  func failingEpisodeDoesNotAbortBatch() async throws {
    let unsavedPodcast = try Create.unsavedPodcast(description: "POD")
    let pes = try await repo.upsertPodcastEpisodes([
      UnsavedPodcastEpisode(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisode: try Create.unsavedEpisode(
          title: "BadEpisode",
          description: "BadContent"
        )
      ),
      UnsavedPodcastEpisode(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisode: try Create.unsavedEpisode(
          title: "GoodEpisode",
          description: "GoodContent"
        )
      ),
    ])
    let bad = try #require(pes.first).episode
    let good = try #require(pes.last).episode

    // FailOnMarkerEmbeddable throws .noResult for any input containing "Bad",
    // simulating an episode whose cleaned text tokenizes to something the
    // model can't handle.
    let embedding = await makeContextualEmbedding(
      FailOnMarkerEmbeddable(failIfInputContains: "Bad")
    )

    try await EmbeddingService.upsertEpisodeEmbeddings(
      for: [bad, good],
      embedding: embedding
    )

    #expect(try await recommendationRepo.embedding(for: bad.id) == nil)
    #expect(try await recommendationRepo.embedding(for: good.id) != nil)
  }

  @Test("cancellation during batch preserves completed episodes")
  func cancellationPreservesPartial() async throws {
    let unsavedPodcast = try Create.unsavedPodcast(description: "POD")
    let pes = try await repo.upsertPodcastEpisodes([
      UnsavedPodcastEpisode(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisode: try Create.unsavedEpisode(
          title: "FirstTitle",
          description: "FirstDesc"
        )
      ),
      UnsavedPodcastEpisode(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisode: try Create.unsavedEpisode(
          title: "CancelMe",
          description: "SecondDesc"
        )
      ),
    ])
    let first = try #require(pes.first).episode
    let second = try #require(pes.last).episode

    // Throws CancellationError on the first vector(for:) call made inside
    // episode 2's compute. Episode 1 finishes fully (podcast + title + desc
    // all pre-"CancelMe"), its embedding is written, and the for-loop's
    // do/catch rethrows CancellationError out of upsertEpisodeEmbeddings.
    let embedding = await makeContextualEmbedding(
      CancelOnMarkerEmbeddable(cancelIfInputContains: "CancelMe")
    )

    await #expect(throws: CancellationError.self) {
      try await EmbeddingService.upsertEpisodeEmbeddings(
        for: [first, second],
        embedding: embedding
      )
    }

    #expect(try await recommendationRepo.embedding(for: first.id) != nil)
    #expect(try await recommendationRepo.embedding(for: second.id) == nil)
  }

  // MARK: - Blend Discrimination

  @Test("within-show episodes remain distinct after podcast blending")
  func withinShowEpisodeSeparation() async throws {
    // Vectors are chosen so the podcast points along x, episode A along y,
    // episode B along z. At the current 0.75/0.25 blend the stored vectors
    // land at ~[0.316, 0.949, 0] and ~[0.316, 0, 0.949], giving cosine ~0.10.
    // If someone cranks podcast weight to >=0.5 the episodes collapse toward
    // the podcast axis and cosine climbs past 0.3.
    let mapping: [String: [Double]] = [
      "POD": [1, 0, 0],
      "EP_A_TITLE": [0, 1, 0],
      "EP_A_DESC": [0, 1, 0],
      "EP_B_TITLE": [0, 0, 1],
      "EP_B_DESC": [0, 0, 1],
    ]
    let embedding = await makeContextualEmbedding(
      DeterministicEmbeddable(mapping: mapping)
    )

    let unsavedPodcast = try Create.unsavedPodcast(title: "POD", description: "POD")
    let pes = try await repo.upsertPodcastEpisodes([
      UnsavedPodcastEpisode(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisode: try Create.unsavedEpisode(
          title: "EP_A_TITLE",
          description: "EP_A_DESC"
        )
      ),
      UnsavedPodcastEpisode(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisode: try Create.unsavedEpisode(
          title: "EP_B_TITLE",
          description: "EP_B_DESC"
        )
      ),
    ])
    let epA = try #require(pes.first).episode
    let epB = try #require(pes.last).episode

    try await EmbeddingService.upsertEpisodeEmbeddings(
      for: [epA, epB],
      embedding: embedding
    )

    let vA = try #require(try await recommendationRepo.embedding(for: epA.id)).floatVector
    let vB = try #require(try await recommendationRepo.embedding(for: epB.id)).floatVector
    let cosine = VectorMath.dotProduct(vA, vB)
    #expect(cosine < 0.3)
  }

  @Test("episode title and description blend at 0.6 / 0.4")
  func episodeUses60_40TitleDescriptionBlend() async throws {
    // Title/description sit on orthogonal axes so their ratio in the stored
    // vector reflects the blend weights directly; podcast title/description
    // sit on different axes so the 0.75/0.25 episode/podcast blend cannot
    // leak into stored[0] or stored[1].
    let mapping: [String: [Double]] = [
      "EP_TITLE": [1, 0, 0, 0],
      "EP_DESC": [0, 1, 0, 0],
      "POD_TITLE": [0, 0, 1, 0],
      "POD_DESC": [0, 0, 0, 1],
    ]
    let embedding = await makeContextualEmbedding(
      DeterministicEmbeddable(mapping: mapping)
    )

    let pe = try await makePodcastEpisode(
      podcastTitle: "POD_TITLE",
      podcastDescription: "POD_DESC",
      episodeTitle: "EP_TITLE",
      episodeDescription: "EP_DESC"
    )

    try await EmbeddingService.upsertEpisodeEmbeddings(
      for: [pe.episode],
      embedding: embedding
    )

    let stored = try #require(try await recommendationRepo.embedding(for: pe.episode.id))
      .floatVector
    let ratio = stored[0] / stored[1]
    #expect(abs(ratio - 1.5) < 0.001)
  }

  @Test("podcast title and description blend at 0.6 / 0.4")
  func podcastUses60_40TitleDescriptionBlend() async throws {
    let mapping: [String: [Double]] = [
      "POD_TITLE": [1, 0, 0],
      "POD_DESC": [0, 1, 0],
      "EP_TITLE": [0, 0, 1],
      "EP_DESC": [0, 0, 1],
    ]
    let embedding = await makeContextualEmbedding(
      DeterministicEmbeddable(mapping: mapping)
    )

    let pe = try await makePodcastEpisode(
      podcastTitle: "POD_TITLE",
      podcastDescription: "POD_DESC",
      episodeTitle: "EP_TITLE",
      episodeDescription: "EP_DESC"
    )

    try await EmbeddingService.upsertEpisodeEmbeddings(
      for: [pe.episode],
      embedding: embedding
    )

    let stored = try #require(try await recommendationRepo.podcastEmbedding(for: pe.podcast.id))
      .floatVector
    let ratio = stored[0] / stored[1]
    #expect(abs(ratio - 1.5) < 0.001)
    #expect(abs(stored[2]) < 0.001)
  }

  // MARK: - Helpers

  private func makeContextualEmbedding(
    _ embeddable: some Embeddable & Sendable = FakeEmbeddable()
  ) async -> ContextualEmbedding {
    let embedding = ContextualEmbedding(embedding: embeddable)
    await embedding.requestAndLoadAssetsIfNeeded()
    return embedding
  }

  private func makePodcastEpisode(
    podcastTitle: String = String.random(),
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

private struct RevisionedEmbeddable: Embeddable {
  var hasAvailableAssets = true
  let revision: Int

  func load() throws {}
  func requestAssets(completion: @escaping @Sendable ((any Error)?) -> Void) { completion(nil) }

  func embeddingResult(for string: String) throws -> any EmbeddableResult {
    try FakeEmbeddable().embeddingResult(for: string)
  }
}

private final class RecordingEmbeddable: Embeddable, Sendable {
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

private struct FailOnMarkerEmbeddable: Embeddable {
  let hasAvailableAssets = true
  let revision: Int = 1
  let failIfInputContains: String

  func load() throws {}
  func requestAssets(completion: @escaping @Sendable ((any Error)?) -> Void) { completion(nil) }

  func embeddingResult(for string: String) throws -> any EmbeddableResult {
    if string.contains(failIfInputContains) { throw EmbeddingError.noResult }
    return try FakeEmbeddable().embeddingResult(for: string)
  }
}

private struct CancelOnMarkerEmbeddable: Embeddable {
  let hasAvailableAssets = true
  let revision: Int = 1
  let cancelIfInputContains: String

  func load() throws {}
  func requestAssets(completion: @escaping @Sendable ((any Error)?) -> Void) { completion(nil) }

  func embeddingResult(for string: String) throws -> any EmbeddableResult {
    if string.contains(cancelIfInputContains) { throw CancellationError() }
    return try FakeEmbeddable().embeddingResult(for: string)
  }
}

private struct DeterministicEmbeddable: Embeddable {
  let hasAvailableAssets = true
  let revision: Int = 1
  let mapping: [String: [Double]]

  func load() throws {}
  func requestAssets(completion: @escaping @Sendable ((any Error)?) -> Void) { completion(nil) }

  func embeddingResult(for string: String) throws -> any EmbeddableResult {
    guard let vector = mapping[string] else {
      Assert.fatal("DeterministicEmbeddable received unmapped input: '\(string)'")
    }
    return FakeEmbeddingResult(vectors: [vector])
  }
}
