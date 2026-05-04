// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("RecommendationEngine observation retry tests", .container)
class ObservationRetryTests {
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.appDB) private var appDB

  @Test("scoring observation retries after a transient failure")
  func scoringObservationRetriesAfterFailure() async throws {
    // Script the fake to hand back a throwing observation on the first call.
    // The engine's catch-and-retry loop should sleep, then call
    // `scoringContextInputs()` again; the script is empty by that point so
    // the fake falls through to the real (in-memory) observation. Without
    // the retry loop, the engine logs the error and the task exits, so
    // recommendations stay empty even though the DB has a complete signal
    // set.
    let fakeObservatory = try #require(observatory as? FakeObservatory)
    let dbReader = self.appDB.db
    fakeObservatory.scoringContextInputsScript([
      {
        ValueObservation
          .tracking { _ -> ScoringContextInputs in
            throw TestError.simulatedFailure
          }
          .values(in: dbReader)
      }
    ])

    let (_, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signals)
    let (_, candidates) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Candidate"
    )
    try await RecommendationHelpers.embedEpisodes(candidates)

    let recs = try await RecommendationHelpers.startAndWaitForRecs()
    #expect(!recs.isEmpty)
  }
}
