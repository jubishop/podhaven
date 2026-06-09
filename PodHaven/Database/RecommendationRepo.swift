// Copyright Justin Bishop, 2026

import Accelerate
import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging
import Tagged

extension Container {
  var recommendationRepo: Factory<any Recommending> {
    Factory(self) { self.makeRecommendationRepo() }.scope(.cached)
  }
}

struct RecommendationRepo: Recommending {
  private static let log = Log.as(LogSubsystem.Database.recommendationRepo)

  // MARK: - Initialization

  var db: AppDB.Reader { reader }
  private let reader: AppDB.Reader
  private let writer: AppDB.Writer
  init(reader: AppDB.Reader, writer: AppDB.Writer) {
    self.reader = reader
    self.writer = writer
  }

  // MARK: - Recommendation Readers

  func allRatedEpisodes() async throws -> [SignalEpisode] {
    try await reader.read { db in
      try SignalEpisode.filter(Episode.hasRatingSignal).fetchAll(db)
    }
  }

  func allUnratedListenedEpisodes() async throws -> [PartialSignal] {
    try await reader.read { db in
      try PartialSignal
        .filter(Episode.hasCoverage && !Episode.rated)
        .fetchAll(db)
        .filter(\.meetsSignalThreshold)
    }
  }

  func allScoringContextInputs() async throws -> ScoringContextInputs {
    try await reader.read { db in
      try Self.scoringContextInputs(db) { db in
        try PartialSignal
          .filter(Episode.hasCoverage && !Episode.rated)
          .fetchAll(db)
          .filter(\.meetsSignalThreshold)
      }
    }
  }

  // Shared builder for both the engine's debounced rebuild (above) and the
  // GRDB observation in `Observatory.scoringContextInputsWithoutPartialSignals()`.
  // The observation passes the default `{ _ in [] }` so `playbackCoverage` and
  // `lastPlayedDate` stay out of the tracked region — otherwise every 3-second
  // `updatePlayback` write would wake the observation. The rebuild path passes
  // a real fetcher, so partial listens land in the engine through that loop.
  static func scoringContextInputs(
    _ db: Database,
    partialSignals fetchPartialSignals: (Database) throws -> [PartialSignal] = { _ in [] }
  ) throws -> ScoringContextInputs {
    let ratedSignals = try SignalEpisode.filter(Episode.hasRatingSignal).fetchAll(db)
    let partialSignals = try fetchPartialSignals(db)
    let signalIDs = ratedSignals.map(\.id) + partialSignals.map(\.id)
    let signalEmbeddings: IdentifiedArray<Episode.ID, EpisodeEmbedding> =
      signalIDs.isEmpty
      ? IdentifiedArray(id: \.episodeId)
      : try EpisodeEmbedding
        .filter(signalIDs.contains(EpisodeEmbedding.Columns.episodeId))
        .fetchIdentifiedArray(db, id: \.episodeId)
    return ScoringContextInputs(
      ratedSignals: ratedSignals,
      partialSignals: partialSignals,
      signalEmbeddings: signalEmbeddings,
      embeddingCount: try EpisodeEmbedding.fetchCount(db),
      freshnessCadences: try Self.resolveFreshnessCadences(db)
    )
  }

  // Plain column reads: the manual override wins, else the cached per-podcast
  // inference (`updateInferredFreshnessCadence` keeps it current at write time),
  // else the call site's `.default` for podcasts absent from the map. The
  // windowed pubDate scan + medians that used to run here on every observation
  // fire are gone, so `episode(pubDate)` no longer sits in the scoring
  // observation's tracked region.
  static func resolveFreshnessCadences(
    _ db: Database
  ) throws -> [Podcast.ID: FreshnessCadence] {
    let rows = try Row.fetchAll(
      db,
      Podcast
        .filter(
          Podcast.Columns.freshnessCadence != nil
            || Podcast.Columns.inferredFreshnessCadence != nil
        )
        .select(
          Podcast.Columns.id,
          Podcast.Columns.freshnessCadence,
          Podcast.Columns.inferredFreshnessCadence
        )
    )
    var resolved = [Podcast.ID: FreshnessCadence](capacity: rows.count)
    for row in rows {
      let id: Podcast.ID = row[Podcast.Columns.id]
      let manual: FreshnessCadence? = row[Podcast.Columns.freshnessCadence]
      let inferred: FreshnessCadence? = row[Podcast.Columns.inferredFreshnessCadence]
      if let cadence = manual ?? inferred {
        resolved[id] = cadence
      }
    }
    return resolved
  }

  // Recompute one podcast's cached inference from its most-recent pubDates and
  // write `inferredFreshnessCadence` only when it changes, so a stable cadence
  // produces no write (and doesn't wake the scoring observation). No episodes
  // clears the column to nil, dropping the podcast from the resolved map. Called
  // from the repo's feed-insert / refresh transactions so the windowed scan runs
  // once per changed podcast at write time, never fleet-wide in the scoring path.
  static func updateInferredFreshnessCadence(
    _ db: Database,
    podcastID: Podcast.ID
  ) throws {
    let pubDates =
      try Episode
      .filter(Episode.Columns.podcastId == podcastID)
      .select(Episode.Columns.pubDate, as: Date.self)
      .order(Episode.Columns.pubDate.desc)
      .limit(FreshnessCadence.inferenceMaxSamples)
      .fetchAll(db)
    let newValue: FreshnessCadence? =
      pubDates.isEmpty ? nil : FreshnessCadence.infer(from: pubDates)

    var currentValue: FreshnessCadence? = nil
    if let row = try Row.fetchOne(
      db,
      Podcast.withID(podcastID).select(Podcast.Columns.inferredFreshnessCadence)
    ) {
      currentValue = row[Podcast.Columns.inferredFreshnessCadence]
    }
    guard newValue != currentValue else { return }

    try Podcast
      .withID(podcastID)
      .updateAll(db, Podcast.Columns.inferredFreshnessCadence.set(to: newValue))
  }

  func allCandidateEpisodes() async throws -> [CandidateEpisode] {
    try await reader.read { db in
      try CandidateEpisode
        .filter(Episode.candidate && Episode.hasEmbedding)
        .fetchAll(db)
    }
  }

  // Single-pass corpus scan: accumulates `sum` (for the mean) and
  // `outerSum = Σ xᵀx` simultaneously, then recovers the covariance via the
  // identity `Cov = outerSum/N - μμᵀ`. Skips the outer-product accumulation
  // when `principalComponentCount` is 0. Peak memory is O(d²) regardless of
  // corpus size. Top-k eigenvectors come from power iteration with deflation.
  func whiteningTransform(
    principalComponentCount: Int
  ) async throws -> WhiteningTransform? {
    try await reader.read { db in
      var sum: [Float] = []
      var outerSum: [Float] = []
      var outerScratch: [Float] = []
      var count = 0
      let cursor = try EpisodeEmbedding.fetchCursor(db)
      while let embedding = try cursor.next() {
        unsafe embedding.withFloatBuffer { vec in
          let dim = vec.count
          if sum.isEmpty {
            sum = [Float](repeating: 0, count: dim)
            if principalComponentCount > 0 {
              outerSum = [Float](repeating: 0, count: dim * dim)
              outerScratch = [Float](repeating: 0, count: dim * dim)
            }
          }
          unsafe sum.withUnsafeMutableBufferPointer { sumPtr in
            unsafe VectorMath.addInPlace(vec, into: sumPtr)
          }
          guard principalComponentCount > 0 else { return }
          unsafe outerSum.withUnsafeMutableBufferPointer { outerPtr in
            unsafe outerScratch.withUnsafeMutableBufferPointer { scratchPtr in
              unsafe VectorMath.accumulateScaledOuterProduct(
                of: vec,
                scalar: 1.0,
                into: outerPtr,
                scratch: scratchPtr,
                dim: dim
              )
            }
          }
        }
        count += 1
      }
      guard count > 0 else { return nil }
      let mean = vDSP.divide(sum, Float(count))
      let dim = mean.count

      guard principalComponentCount > 0 else {
        return WhiteningTransform(mean: mean, principalComponents: [])
      }

      // covariance = outerSum/N - μ⊗μᵀ, accumulated in `outerSum` in place.
      unsafe outerSum.withUnsafeMutableBufferPointer { outerPtr in
        unsafe VectorMath.divideInPlace(outerPtr, by: Float(count))
        unsafe outerScratch.withUnsafeMutableBufferPointer { scratchPtr in
          unsafe mean.withUnsafeBufferPointer { meanPtr in
            unsafe VectorMath.accumulateScaledOuterProduct(
              of: meanPtr,
              scalar: -1.0,
              into: outerPtr,
              scratch: scratchPtr,
              dim: dim
            )
          }
        }
      }

      let principalComponents = Self.topKEigenvectors(
        ofSymmetric: &outerSum,
        scratch: &outerScratch,
        dim: dim,
        k: principalComponentCount
      )
      return WhiteningTransform(mean: mean, principalComponents: principalComponents)
    }
  }

  // Power iteration with rank-1 deflation. Reuses `scratch` (a d² buffer)
  // across calls to avoid per-component allocation.
  private static func topKEigenvectors(
    ofSymmetric covariance: inout [Float],
    scratch: inout [Float],
    dim: Int,
    k: Int
  ) -> [[Float]] {
    var v = [Float](repeating: 0, count: dim)
    var cv = [Float](repeating: 0, count: dim)
    var components = [[Float]](capacity: k)
    for _ in 0..<k {
      unsafe v.withUnsafeMutableBufferPointer { vBuf in
        unsafe vBuf.update(repeating: 0)
        unsafe vBuf[0] = 1
      }
      // Bail out of the PC loop when `Cov · v` is zero on the first step —
      // that means the residual covariance has rank below the requested k
      // and any "eigenvector" we'd record now would just be the seed.
      let converged = unsafe covariance.withUnsafeBufferPointer { covPtr -> Bool in
        unsafe cv.withUnsafeMutableBufferPointer { cvPtr in
          unsafe v.withUnsafeMutableBufferPointer { vPtr in
            var madeProgress = false
            for _ in 0..<50 {
              unsafe VectorMath.matrixVectorMultiply(
                covPtr,
                UnsafeBufferPointer(vPtr),
                into: cvPtr,
                dim: dim
              )
              let cvBuf = UnsafeBufferPointer(cvPtr)
              let norm = sqrt(unsafe VectorMath.dotProduct(cvBuf, cvBuf))
              guard norm > 1e-12 else { break }
              guard let cvBaseAddress = cvPtr.baseAddress,
                let vBaseAddress = vPtr.baseAddress
              else {
                Assert.fatal("RecommendationRepo whitening buffers are missing storage")
              }
              var divisor = norm
              unsafe vDSP_vsdiv(
                cvBaseAddress,
                1,
                &divisor,
                vBaseAddress,
                1,
                vDSP_Length(dim)
              )
              madeProgress = true
            }
            return madeProgress
          }
        }
      }
      guard converged else { break }
      let eigenvalue = unsafe covariance.withUnsafeBufferPointer { covPtr -> Float in
        unsafe v.withUnsafeMutableBufferPointer { vPtr -> Float in
          unsafe cv.withUnsafeMutableBufferPointer { cvPtr -> Float in
            unsafe VectorMath.matrixVectorMultiply(
              covPtr,
              UnsafeBufferPointer(vPtr),
              into: cvPtr,
              dim: dim
            )
            return unsafe VectorMath.dotProduct(
              UnsafeBufferPointer(vPtr),
              UnsafeBufferPointer(cvPtr)
            )
          }
        }
      }
      unsafe covariance.withUnsafeMutableBufferPointer { covPtr in
        unsafe scratch.withUnsafeMutableBufferPointer { scratchPtr in
          unsafe v.withUnsafeBufferPointer { vPtr in
            unsafe VectorMath.accumulateScaledOuterProduct(
              of: vPtr,
              scalar: -eigenvalue,
              into: covPtr,
              scratch: scratchPtr,
              dim: dim
            )
          }
        }
      }
      components.append(v)
    }
    return components
  }

  // MARK: - Embedding Writers

  // Batch upsert: one transaction per chunk instead of one per episode.
  func upsertEmbeddings(_ unsaved: [UnsavedEpisodeEmbedding]) async throws {
    guard !unsaved.isEmpty else { return }
    try await writer.write { db in
      var skipped = 0
      for entry in unsaved {
        do {
          try entry.upsert(db)
        } catch DatabaseError.SQLITE_CONSTRAINT_FOREIGNKEY {
          skipped += 1
        }
      }
      Self.log.debug(
        "upsertEmbeddings: wrote \(unsaved.count - skipped) of \(unsaved.count) episodes"
      )
    }
  }

  func upsertPodcastEmbeddings(_ unsaved: [UnsavedPodcastEmbedding]) async throws {
    guard !unsaved.isEmpty else { return }
    try await writer.write { db in
      var skipped = 0
      for entry in unsaved {
        do {
          try entry.upsert(db)
        } catch DatabaseError.SQLITE_CONSTRAINT_FOREIGNKEY {
          skipped += 1
        }
      }
      Self.log.debug(
        "upsertPodcastEmbeddings: wrote \(unsaved.count - skipped) of \(unsaved.count) podcasts"
      )
    }
  }

  // MARK: - Embedding Readers

  func hasEmbeddings() async throws -> Bool {
    try await reader.read { db in
      try EpisodeEmbedding.fetchCount(db) > 0
    }
  }

  func embedding(for episodeID: Episode.ID) async throws -> EpisodeEmbedding? {
    try await reader.read { db in
      try EpisodeEmbedding
        .filter(EpisodeEmbedding.Columns.episodeId == episodeID)
        .fetchOne(db)
    }
  }

  func embeddings(for episodeIDs: [Episode.ID]) async throws
    -> IdentifiedArray<Episode.ID, EpisodeEmbedding>
  {
    guard !episodeIDs.isEmpty else { return IdentifiedArray(id: \.episodeId) }
    return try await reader.read { db in
      try EpisodeEmbedding
        .filter(episodeIDs.contains(EpisodeEmbedding.Columns.episodeId))
        .fetchIdentifiedArray(db, id: \.episodeId)
    }
  }

  func podcastEmbedding(for podcastID: Podcast.ID) async throws -> PodcastEmbedding? {
    try await reader.read { db in
      try PodcastEmbedding
        .filter(PodcastEmbedding.Columns.podcastId == podcastID)
        .fetchOne(db)
    }
  }

  func podcastEmbeddings(for podcastIDs: [Podcast.ID]) async throws
    -> IdentifiedArray<Podcast.ID, PodcastEmbedding>
  {
    guard !podcastIDs.isEmpty else { return IdentifiedArray(id: \.podcastId) }
    return try await reader.read { db in
      try PodcastEmbedding
        .filter(podcastIDs.contains(PodcastEmbedding.Columns.podcastId))
        .fetchIdentifiedArray(db, id: \.podcastId)
    }
  }

  func podcasts(for podcastIDs: [Podcast.ID]) async throws -> IdentifiedArrayOf<Podcast> {
    guard !podcastIDs.isEmpty else { return [] }
    return try await reader.read { db in
      try Podcast
        .filter(podcastIDs.contains(Podcast.Columns.id))
        .fetchIdentifiedArray(db)
    }
  }

  func episodes(for episodeIDs: [Episode.ID]) async throws -> [Episode] {
    guard !episodeIDs.isEmpty else { return [] }
    return try await reader.read { db in
      try Episode
        .filter(episodeIDs.contains(Episode.Columns.id))
        .fetchAll(db)
    }
  }

  func episodesNeedingEmbeddings(revision: Int) async throws -> [Episode.ID] {
    try await reader.read { db in
      try Self.episodesNeedingEmbeddings(db, revision: revision)
    }
  }

  // Query builder behind the async `episodesNeedingEmbeddings(revision:)`,
  // run inside that function's reader transaction.
  static func episodesNeedingEmbeddings(
    _ db: Database,
    revision: Int
  ) throws -> [Episode.ID] {
    let embeddingAlias = TableAlias()
    let podcastAlias = TableAlias()

    return
      try Episode
      .joining(required: Episode.podcast.aliased(podcastAlias))
      .joining(optional: Episode.embedding.aliased(embeddingAlias))
      .filter(
        embeddingAlias[EpisodeEmbedding.Columns.id] == nil
          || embeddingAlias[EpisodeEmbedding.Columns.embeddingRevision] != revision
          || Episode.Columns.contentUpdatedAt
            > embeddingAlias[EpisodeEmbedding.Columns.verificationDate]
          || podcastAlias[Podcast.Columns.contentUpdatedAt]
            > embeddingAlias[EpisodeEmbedding.Columns.verificationDate]
      )
      .order(Episode.Columns.pubDate.desc)
      .select(Episode.Columns.id, as: Episode.ID.self)
      .fetchAll(db)
  }

  // The hash check in EmbeddingService skips embeddings whose cleaned source
  // text hasn't changed. We still need to advance verificationDate on those
  // rows so the next `episodesNeedingEmbeddings` query stops returning them —
  // otherwise a `contentUpdatedAt` bump on a hash-stable change (e.g. a feed
  // refresh that leaves cleaned title/description unchanged) loops forever.
  func touchEmbeddingVerification(
    forEpisodeIDs episodeIDs: [Episode.ID],
    at date: Date
  ) async throws {
    guard !episodeIDs.isEmpty else { return }
    try await writer.write { db in
      _ =
        try EpisodeEmbedding
        .filter(episodeIDs.contains(EpisodeEmbedding.Columns.episodeId))
        .updateAll(db, EpisodeEmbedding.Columns.verificationDate.set(to: date))
    }
  }
}
