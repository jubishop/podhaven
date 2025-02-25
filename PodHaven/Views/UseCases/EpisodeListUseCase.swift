// Copyright Justin Bishop, 2025

import Foundation
import IdentifiedCollections
import SwiftUI

@Observable @MainActor final class EpisodeListUseCase<T: EpisodeIdentifiable, ID: Hashable> {
  // MARK: - State Management

  var isSelected = BindableDictionary<T, Bool>(defaultValue: false)
  var anySelected: Bool { filteredEpisodes.contains { isSelected[$0] } }
  var anyNotSelected: Bool { filteredEpisodes.contains { !isSelected[$0] } }
  var selectedEpisodes: IdentifiedArray<ID, T> {
    IdentifiedArray(uniqueElements: filteredEpisodes.filter({ isSelected[$0] }), id: idKeyPath)
  }
  var selectedEpisodeIDs: [Episode.ID] { selectedEpisodes.map { $0.id } }

  private var _allEpisodes: IdentifiedArray<ID, T>
  var allEpisodes: IdentifiedArray<ID, T> {
    get { _allEpisodes }
    set {
      _allEpisodes = newValue
      for episode in isSelected.keys where !allEpisodes.contains(episode) {
        isSelected.removeValue(forKey: episode)
      }
    }
  }

  var filteredEpisodes: IdentifiedArray<ID, T> {
    let searchTerms =
      episodeFilter
      .lowercased()
      .components(separatedBy: CharacterSet.whitespacesAndNewlines)
      .filter { !$0.isEmpty }

    guard !searchTerms.isEmpty else { return allEpisodes }

    return IdentifiedArray(
      allEpisodes.filter { episode in
        let lowercasedTitle = episode.title.lowercased()
        return searchTerms.allSatisfy { lowercasedTitle.contains($0) }
      }
    )
  }

  var episodeFilter: String = ""

  private let idKeyPath: KeyPath<T, ID>

  // MARK: - Initialization

  init(idKeyPath: KeyPath<T, ID>) {
    self.idKeyPath = idKeyPath
    self._allEpisodes = IdentifiedArray(id: idKeyPath)
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
