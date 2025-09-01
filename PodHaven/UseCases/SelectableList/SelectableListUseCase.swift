// Copyright Justin Bishop, 2025

import Foundation
import IdentifiedCollections
import SwiftUI

@Observable @MainActor class SelectableListUseCase<Item: Searchable, ID: Hashable>: SelectableList {
  // MARK: - Selection State Management

  var isSelected = BindableDictionary<ID, Bool>(defaultValue: false)
  var anySelected: Bool { filteredEntries.ids.contains { isSelected[$0] } }
  var anyNotSelected: Bool { filteredEntries.ids.contains { !isSelected[$0] } }
  var selectedEntries: IdentifiedArray<ID, Item> {
    filteredEntries.filter({ isSelected[$0[keyPath: idKeyPath]] })
  }
  var selectedEntryIDs: [ID] { selectedEntries.ids.elements }

  // MARK: - Entry List Getters / Setters

  private var _allEntries: IdentifiedArray<ID, Item>
  var allEntries: IdentifiedArray<ID, Item> {
    get { _allEntries }
    set {
      if let sortMethod {
        _allEntries = newValue.sorted(by: sortMethod)
      } else {
        _allEntries = newValue
      }

      for entry in isSelected.keys where !allEntries.ids.contains(entry) {
        isSelected.removeValue(forKey: entry)
      }
    }
  }
  var filteredEntries: IdentifiedArray<ID, Item> {
    let filteredEntries: IdentifiedArray<ID, Item>
    if let filterMethod {
      filteredEntries = allEntries.filter { filterMethod($0) }
    } else {
      filteredEntries = allEntries
    }

    if entryFilter.isEmpty { return filteredEntries }

    let searchTerms =
      entryFilter
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
  var filteredEntryIDs: [ID] { filteredEntries.ids.elements }

  // MARK: - Customization Parameters

  var filterMethod: ((Item) -> Bool)?
  var sortMethod: ((Item, Item) -> Bool)? {
    didSet {
      if let sortMethod {
        _allEntries.sort(by: sortMethod)
      }
    }
  }
  var entryFilter: String = ""

  private let idKeyPath: KeyPath<Item, ID>

  // MARK: - Initialization

  init(
    idKeyPath: KeyPath<Item, ID>,
    filterMethod: ((Item) -> Bool)? = nil,
    sortMethod: ((Item, Item) -> Bool)? = nil
  ) {
    self.idKeyPath = idKeyPath
    self.filterMethod = filterMethod
    self.sortMethod = sortMethod
    self._allEntries = IdentifiedArray(id: idKeyPath)
  }

  // MARK: - Public Functions

  func selectAllEntries() {
    for entry in filteredEntries {
      isSelected[entry[keyPath: idKeyPath]] = true
    }
  }

  func unselectAllEntries() {
    for entry in filteredEntries {
      isSelected[entry[keyPath: idKeyPath]] = false
    }
  }
}
