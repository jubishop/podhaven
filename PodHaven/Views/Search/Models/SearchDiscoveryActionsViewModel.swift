// Copyright Justin Bishop, 2026

import SwiftUI

// Drops each pick from the collector after the underlying ManagingEpisodes
// action succeeds. All action plumbing comes from the protocol's default
// implementations; only the post-success hook is overridden here.
@Observable @MainActor
final class SearchDiscoveryActionsViewModel: ManagingEpisodes, nonisolated Hashable {
  typealias EpisodeType = ListedEpisode

  nonisolated static func == (
    lhs: SearchDiscoveryActionsViewModel,
    rhs: SearchDiscoveryActionsViewModel
  ) -> Bool {
    lhs === rhs
  }

  nonisolated func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(self))
  }

  let collector: SearchRecommendationCollector

  init(collector: SearchRecommendationCollector) {
    self.collector = collector
  }

  func didPerformAction(_ episode: ListedEpisode) {
    collector.removePick(mediaGUID: episode.mediaGUID)
  }
}
