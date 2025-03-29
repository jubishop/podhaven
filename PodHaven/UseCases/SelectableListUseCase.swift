// Copyright Justin Bishop, 2025

import Foundation
import IdentifiedCollections
import SwiftUI

@Observable @MainActor
final class SelectableListUseCase<T: Stringable, ID: Hashable>: SelectableList {
  // MARK: - State Management

  // TODO: Make isSelected private
  var isSelected = BindableDictionary<T, Bool>(defaultValue: false)
  func selectionBinding(for key: T) -> Binding<Bool> {
    Binding<Bool>(
      get: { [weak self] in
        guard let self = self else { return false }
        return self.isSelected[key]
      },
      set: { [weak self] newValue in
        guard let self = self else { return }
        self.isSelected[key] = newValue
      }
    )
  }
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

  private var _entryFilter: String = ""
  var entryFilter: Binding<String> {
    Binding(
      get: { self._entryFilter },
      set: { self._entryFilter = $0 }
    )
  }

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
