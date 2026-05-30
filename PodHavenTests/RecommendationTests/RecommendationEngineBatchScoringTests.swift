// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("RecommendationEngine batch similarity scoring", .container)
@MainActor final class RecommendationEngineBatchScoringTests {

  @Test("similarityScores returns nil at every index while the cache is cold")
  func coldCacheYieldsAllNil() async throws {
    let engine = Container.shared.recommendationEngine()
    let results = try await engine.similarityScores(forEmbeddings: [[1, 0, 0], [0, 0, 1]])
    #expect(results.count == 2)
    #expect(results.allSatisfy { $0 == nil })
  }

  @Test("similarityScores aligns positionally and matches single-vector scoring")
  func batchMatchesPerVectorPositionally() async throws {
    let embeddable = RecommendationScoringTestHelpers.scoringEmbeddable()
    try await RecommendationScoringTestHelpers.primeEngine(with: embeddable)
    let engine = Container.shared.recommendationEngine()

    // [1,0,0] is the liked-signal direction; [0,0,1] is the filler direction.
    let near: [Float] = [1, 0, 0]
    let far: [Float] = [0, 0, 1]

    let batch = try await engine.similarityScores(forEmbeddings: [near, far])
    let nearAlone = try await engine.similarityScores(forEmbeddings: [near])
    let farAlone = try await engine.similarityScores(forEmbeddings: [far])

    #expect(batch.count == 2)
    #expect(batch[0] == nearAlone[0], "Index 0 must score `near` regardless of batch size")
    #expect(batch[1] == farAlone[0], "Index 1 must score `far` regardless of batch size")

    let nearScore = try #require(batch[0])
    let farScore = try #require(batch[1])
    #expect(
      nearScore > farScore,
      "The liked-signal direction must outscore the filler direction"
    )
  }

  @Test("similarityScores yields nil only at indices whose dimension mismatches the centroid")
  func dimensionMismatchYieldsNilPositionally() async throws {
    let embeddable = RecommendationScoringTestHelpers.scoringEmbeddable()
    try await RecommendationScoringTestHelpers.primeEngine(with: embeddable)
    let engine = Container.shared.recommendationEngine()

    let results = try await engine.similarityScores(forEmbeddings: [[1, 0, 0], [1, 0]])
    #expect(results.count == 2)
    #expect(results[0] != nil, "A correctly sized embedding must score")
    #expect(results[1] == nil, "A dimension mismatch must score nil without shifting other indices")
  }
}
