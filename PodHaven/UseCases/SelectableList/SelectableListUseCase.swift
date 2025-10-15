// Copyright Justin Bishop, 2025

import Foundation
import IdentifiedCollections
import SwiftUI

@Observable @MainActor class SelectableListUseCase<Item: Searchable>: SelectableList {
  // MARK: - SelectableList

  var anySelected: Bool { filteredEntries.ids.contains { isSelected[$0] } }
  var anyNotSelected: Bool { filteredEntries.ids.contains { !isSelected[$0] } }
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

  // MARK: - Selection State Management

  var isSelected = BindableDictionary<Item.ID, Bool>(defaultValue: false)
  var selectedEntries: IdentifiedArrayOf<Item> {
    filteredEntries.filter({ isSelected[$0.id] })
  }
  var selectedEntryIDs: [Item.ID] { selectedEntries.ids.elements }

  // MARK: - Private State Caching

  private var searchTerms: [String] = []
  private var baselineEntries = IdentifiedArrayOf<Item>()

  // MARK: - Entry List Getters / Setters

  private var _allEntries = IdentifiedArrayOf<Item>()
  var allEntries: IdentifiedArrayOf<Item> {
    get { _allEntries }
    set {
      baselineEntries = newValue
      _allEntries = applySort()

      isSelected.removeAll { key, _ in !allEntries.ids.contains(key) }
    }
  }
  var filteredEntries: IdentifiedArrayOf<Item> {
    let filteredEntries: IdentifiedArrayOf<Item>
    if let filterMethod {
      filteredEntries = allEntries.filter { filterMethod($0) }
    } else {
      filteredEntries = allEntries
    }

    guard !searchTerms.isEmpty else { return filteredEntries }

    return IdentifiedArray(
      filteredEntries.filter { entry in
        let searchable = entry.searchableString.lowercased()
        return searchTerms.allSatisfy { searchable.contains($0) }
      }
    )
  }
  var filteredEntryIDs: [Item.ID] { filteredEntries.ids.elements }

  // MARK: - Customization Parameters

  var filterMethod: ((Item) -> Bool)?
  var sortMethod: ((Item, Item) -> Bool)? {
    didSet {
      _allEntries = applySort()
    }
  }
  var entryFilter: String = "" {
    didSet {
      searchTerms =
        entryFilter
        .lowercased()
        .components(separatedBy: CharacterSet.whitespacesAndNewlines)
        .filter { !$0.isEmpty }
    }
  }

  // MARK: - Initialization

  init(
    filterMethod: ((Item) -> Bool)? = nil,
    sortMethod: ((Item, Item) -> Bool)? = nil
  ) {
    self.filterMethod = filterMethod
    self.sortMethod = sortMethod
  }

  // MARK: - Private Helpers

  private func applySort() -> IdentifiedArrayOf<Item> {
    guard let sortMethod else { return baselineEntries }
    return baselineEntries.sorted(by: sortMethod)
  }
}
