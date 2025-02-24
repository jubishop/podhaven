// Copyright Justin Bishop, 2025

import Foundation
import IdentifiedCollections

@Observable @MainActor final class EpisodeListModel {
  var allEpisodes: EpisodeArray

  init(allEpisodes: EpisodeArray = IdentifiedArray(id: \Episode.guid)) {
    self.allEpisodes = allEpisodes
  }

  var isSelected = BindableDictionary<Episode, Bool>(defaultValue: false)
  var anySelected: Bool { filteredEpisodes.contains { isSelected[$0] } }
  var anyNotSelected: Bool { filteredEpisodes.contains { !isSelected[$0] } }
  var selectedEpisodes: EpisodeArray {
    IdentifiedArray(uniqueElements: filteredEpisodes.filter({ isSelected[$0] }), id: \Episode.guid)
  }

  var filteredEpisodes: EpisodeArray {
    let searchTerms =
      episodeFilter
      .lowercased()
      .components(separatedBy: CharacterSet.whitespacesAndNewlines)
      .filter { !$0.isEmpty }

    guard !searchTerms.isEmpty else { return allEpisodes }

    return EpisodeArray(
      allEpisodes.filter { episode in
        let lowercasedTitle = episode.title.lowercased()
        return searchTerms.allSatisfy { lowercasedTitle.contains($0) }
      }
    )
  }
  var episodeFilter: String = ""

  func selectAllEpisodes() {
    for episode in filteredEpisodes {
      isSelected[episode] = true
    }
  }

  func unselectAllEpisodes() {
    for episode in filteredEpisodes {
      isSelected[episode] = false
    }
  }
}
