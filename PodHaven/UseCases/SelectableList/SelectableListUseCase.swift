// Copyright Justin Bishop, 2025

import Foundation
import IdentifiedCollections
import SwiftUI

@Observable @MainActor class SelectableListUseCase<Item: Searchable>: SelectableList {
  // MARK: - Selection State Management

  var isSelected = BindableDictionary<Item.ID, Bool>(defaultValue: false)
  var anySelected: Bool { filteredEntries.ids.contains { isSelected[$0] } }
  var anyNotSelected: Bool { filteredEntries.ids.contains { !isSelected[$0] } }
  var selectedEntries: IdentifiedArrayOf<Item> {
    filteredEntries.filter({ isSelected[$0.id] })
  }
  var selectedEntryIDs: [Item.ID] { selectedEntries.ids.elements }

  // MARK: - Entry List Getters / Setters

  private var _allEntries: IdentifiedArrayOf<Item>
  var allEntries: IdentifiedArrayOf<Item> {
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
  var filteredEntries: IdentifiedArrayOf<Item> {
    let filteredEntries: IdentifiedArrayOf<Item>
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
        searchTerms.allSatisfy { entry.searchableString.lowercased().contains($0) }
      }
    )
  }
  var filteredEntryIDs: [Item.ID] { filteredEntries.ids.elements }

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

  // MARK: - Initialization

  init(
    filterMethod: ((Item) -> Bool)? = nil,
    sortMethod: ((Item, Item) -> Bool)? = nil
  ) {
    self.filterMethod = filterMethod
    self.sortMethod = sortMethod
    self._allEntries = IdentifiedArray(id: \.id)
  }

  // MARK: - Public Functions

  func selectAllEntries() {
    for entry in filteredEntries {
      isSelected[entry.id] = true
    }
  }

  func unselectAllEntries() {
    for entry in filteredEntries {
      isSelected[entry.id] = false
    }
  }
}
