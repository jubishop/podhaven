#if DEBUG
// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

@Observable @MainActor class StubSelectableEpisodeListModel: SelectableEpisodeListModel {
  var isSelecting: Bool = false
  var episodeList = SelectableListUseCase<PodcastEpisode, Episode.ID>(idKeyPath: \.id)
  var selectedEpisodes: [PodcastEpisode] = []
  var selectedEpisodeIDs: [Episode.ID] = []

  func addSelectedEpisodesToTopOfQueue() {}
  func addSelectedEpisodesToBottomOfQueue() {}
  func replaceQueueWithSelected() {}
  func replaceQueueWithSelectedAndPlay() {}
  func cacheSelectedEpisodes() {}
}
#endif
