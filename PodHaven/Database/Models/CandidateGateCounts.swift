// Copyright Justin Bishop, 2026

import Foundation

// Snapshot of the column counts that gate `Episode.candidate`. Used by
// `Observing.candidateGateCounts()` to wake the recommendation engine on
// transitions (queue, finish, rate) that move episodes in or out of the
// candidate pool without otherwise touching the scoring context.
struct CandidateGateCounts: Equatable, Sendable {
  let rated: Int
  let finished: Int
  let queued: Int
}
