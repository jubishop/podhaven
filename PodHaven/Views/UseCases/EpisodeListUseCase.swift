// Copyright Justin Bishop, 2025

import Foundation
import IdentifiedCollections
import SwiftUI

@Observable @MainActor final class EpisodeListUseCase {
  // MARK: - State Management

  var isSelected = BindableDictionary<Episode, Bool>(defaultValue: false)
  var anySelected: Bool { filteredEpisodes.contains { isSelected[$0] } }
  var anyNotSelected: Bool { filteredEpisodes.contains { !isSelected[$0] } }
  var selectedEpisodes: EpisodeArray {
    IdentifiedArray(uniqueElements: filteredEpisodes.filter({ isSelected[$0] }), id: \Episode.guid)
  }
  var selectedEpisodeIDs: [Episode.ID] { selectedEpisodes.map(\.id) }

  private var _allEpisodes: EpisodeArray
  var allEpisodes: EpisodeArray {
    get { _allEpisodes }
    set {
      _allEpisodes = newValue
      for episode in isSelected.keys where !allEpisodes.contains(episode) {
        isSelected.removeValue(forKey: episode)
      }
    }
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

  // MARK: - Initialization

  init(allEpisodes: EpisodeArray = IdentifiedArray(id: \Episode.guid)) {
    _allEpisodes = allEpisodes
  }

  // MARK: - View Functions

  func selectMenu() -> some View {
    Menu(
      content: {
        if anyNotSelected {
          Button("Select All") {
            self.selectAllEpisodes()
          }
        }
        if anySelected {
          Button("Unselect All") {
            self.unselectAllEpisodes()
          }
        }
      },
      label: {
        Image(systemName: "checklist")
      }
    )
  }

  // MARK: - Private Helpers

  private func selectAllEpisodes() {
    for episode in filteredEpisodes {
      isSelected[episode] = true
    }
  }

  private func unselectAllEpisodes() {
    for episode in filteredEpisodes {
      isSelected[episode] = false
    }
  }
}
