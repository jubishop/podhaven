// Copyright Justin Bishop, 2025

import Foundation
import IdentifiedCollections
import SwiftUI

@Observable @MainActor class SelectableListUseCase<T: Searchable, ID: Hashable>: SelectableList {
  // MARK: - Selection State Management

  private var _isSelecting = false
  var isSelecting: Bool {
    get { _isSelecting }
    set { withAnimation { _isSelecting = newValue } }
  }
  var isSelected = BindableDictionary<T, Bool>(defaultValue: false)
  var anySelected: Bool { filteredEntries.contains { isSelected[$0] } }
  var anyNotSelected: Bool { filteredEntries.contains { !isSelected[$0] } }
  var selectedEntries: IdentifiedArray<ID, T> { filteredEntries.filter({ isSelected[$0] }) }
  var selectedEntryIDs: [ID] { selectedEntries.ids.elements }

  // MARK: - Entry List Getters / Setters

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
    let filteredEntries = allEntries.filter { filterMethod($0) }

    let searchTerms =
      _entryFilter
      .lowercased()
      .components(separatedBy: CharacterSet.whitespacesAndNewlines)
      .filter { !$0.isEmpty }

    guard !searchTerms.isEmpty else { return filteredEntries }

    return IdentifiedArray(
      filteredEntries.filter { entry in
        return searchTerms.allSatisfy { entry.searchableString.lowercased().contains($0) }
      }
    )
  }
  var filteredSortedEntries: [T] { filteredEntries.sorted(by: sortMethod) }

  // MARK: - Customization Parameters

  var filterMethod: (T) -> Bool
  var sortMethod: (T, T) -> Bool
  var entryFilter: String = ""

  private let idKeyPath: KeyPath<T, ID>

  // MARK: - Initialization

  init(
    idKeyPath: KeyPath<T, ID>,
    filterMethod: @escaping (T) -> Bool = { _ in true },
    sortMethod: @escaping (T, T) -> Bool = { $0.searchableString < $1.searchableString }
  ) {
    self.idKeyPath = idKeyPath
    self.filterMethod = filterMethod
    self.sortMethod = sortMethod
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
