// Copyright Justin Bishop, 2026

import Foundation

// Snapshot of every episode currently excluded from the candidate pool by
// one of the three gating columns (`rating`, `finishDate`, `queueOrder`).
// Used by `Observing.candidateGateExclusions()` to wake the recommendation
// engine on transitions that move episodes in or out of the candidate pool
// without otherwise touching the scoring context.
//
// The set membership — rather than per-gate counts — is what the engine
// reacts to: if one episode joins the gated set while another leaves on the
// same column in the same transaction, raw counts cancel out but the IDs
// don't, so `.removeDuplicates()` correctly fires for the genuine change.
struct CandidateGateExclusions: Equatable, Sendable {
  let episodeIDs: Set<Episode.ID>
}
