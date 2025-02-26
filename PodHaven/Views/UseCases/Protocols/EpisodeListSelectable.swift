// Copyright Justin Bishop, 2025

import Foundation

@MainActor protocol EpisodeListSelectable {
  var anyNotSelected: Bool { get }
  var anySelected: Bool { get }

  func selectAllEpisodes()
  func unselectAllEpisodes()
}
