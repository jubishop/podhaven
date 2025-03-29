// Copyright Justin Bishop, 2025

import Foundation
import IdentifiedCollections
import SwiftUI

@Observable @MainActor
final class SelectableListUseCase<T: Stringable, ID: Hashable>: SelectableList {
  // MARK: - State Management

  var isSelected = BindableDictionary<T, Bool>(defaultValue: false)
  var anySelected: Bool { filteredEntries.contains { isSelected[$0] } }
  var anyNotSelected: Bool { filteredEntries.contains { !isSelected[$0] } }
  var selectedEntries: IdentifiedArray<ID, T> {
    IdentifiedArray(uniqueElements: filteredEntries.filter({ isSelected[$0] }), id: idKeyPath)
  }
  var customFilter: (T) -> Bool = { _ in true }

  private var _allEntries: IdentifiedArray<ID, T>
  var allEntries: IdentifiedArray<ID, T> {
    get { _allEntries }
    set {
      _allEntries = newValue
      for entry in isSelected.keys where !allEntries.contains(entry) {
        isSelected.removeValue(forKey: entry)
      }
    }
  }

  var filteredEntries: IdentifiedArray<ID, T> {
    let filteredEntries = allEntries.filter { customFilter($0) }

    let searchTerms =
      _entryFilter
      .lowercased()
      .components(separatedBy: CharacterSet.whitespacesAndNewlines)
      .filter { !$0.isEmpty }

    guard !searchTerms.isEmpty else { return filteredEntries }

    return IdentifiedArray(
      filteredEntries.filter { entry in
        let lowercasedTitle = entry.toString.lowercased()
        return searchTerms.allSatisfy { lowercasedTitle.contains($0) }
      }
    )
  }

  var entryFilter: String = ""

  private let idKeyPath: KeyPath<T, ID>

  // MARK: - Initialization

  init(idKeyPath: KeyPath<T, ID>) {
    self.idKeyPath = idKeyPath
    self._allEntries = IdentifiedArray(id: idKeyPath)
  }

  // MARK: - Public Functions

  func selectAllEntries() {
    for entry in filteredEntries {
      isSelected[entry] = true
    }
  }

  func unselectAllEntries() {
    for entry in filteredEntries {
      isSelected[entry] = false
    }
  }
}
