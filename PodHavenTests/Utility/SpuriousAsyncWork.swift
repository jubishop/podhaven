// Copyright Justin Bishop, 2026

import Foundation

@testable import PodHaven

// Bounded settle for a NEGATIVE assertion — "no spurious async work ran" — when
// the correct outcome is that nothing happened, so there is no positive signal
// to wait on (a freshly-spawned observation/task that must NOT exist, an init
// that must have no side effects). Each round yields the cooperative thread and
// the poll's inter-attempt delay gives any erroneously-spawned task real
// wall-clock time to surface before the caller asserts its absence.
//
// Prefer waiting on a deterministic positive signal whenever one exists (an
// awaited effect, a driven sleeper, a revision counter). Reach for this only
// for the genuine absence-assertion case. It is not for racing background
// scoring under load — see `RecommendationScoringTestHelpers`.
@MainActor
func yieldForSpuriousAsyncWork() async throws {
  let yields = ThreadSafe(0)
  try await Wait.until(
    { @MainActor in
      await Task.yield()
      yields { $0 += 1 }
      return yields() >= 20
    },
    { "Expected to finish yielding before asserting no spurious async work ran." }
  )
}
