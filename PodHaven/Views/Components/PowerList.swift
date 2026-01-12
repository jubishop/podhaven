// Copyright Justin Bishop, 2025

import Foundation
import IdentifiedCollections
import OrderedCollections
import SwiftUI

@Observable @MainActor class PowerList<Item: Searchable & Sendable>: SelectableList
where Item.ID: Sendable {
  // MARK: - SelectableList

  private var _isSelecting = false
  var isSelecting: Bool { _isSelecting }
  func setSelecting(_ value: Bool) {
    withAnimation {
      _isSelecting = value
    }
  }

  var anySelected: Bool { filteredEntries.ids.contains { isSelected[$0] } }
  var anyNotSelected: Bool { filteredEntries.ids.contains { !isSelected[$0] } }

  var isSelected = BindableDictionary<Item.ID, Bool>(defaultValue: false)
  var selectedEntries: IdentifiedArrayOf<Item> {
    filteredEntries.filter({ isSelected[$0.id] })
  }
  var selectedEntryIDs: [Item.ID] { selectedEntries.ids.elements }

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

  // MARK: - Private State Caching

  private var searchTerms: [String] = [] {
    didSet { scheduleEntriesUpdate() }
  }
  private var baselineEntries = IdentifiedArrayOf<Item>()

  // MARK: - Entry List Getters / Setters

  private var _allEntries = IdentifiedArrayOf<Item>()
  var allEntries: IdentifiedArrayOf<Item> {
    get { _allEntries }
    set {
      baselineEntries = newValue
      scheduleEntriesUpdate()
    }
  }
  private(set) var filteredEntries = IdentifiedArrayOf<Item>()
  var filteredEntryIDs: [Item.ID] { filteredEntries.ids.elements }

  // MARK: - Debounce Management

  @ObservationIgnored var debounceDuration: Duration {
    get { filterDebouncer.debounceDuration }
    set { filterDebouncer.debounceDuration = newValue }
  }
  @ObservationIgnored private lazy var filterDebouncer = StringDebouncer {
    [weak self] filterText in
    guard let self else { return }
    searchTerms =
      filterText
      .lowercased()
      .split(separator: /\s+/)
      .map { String($0) }
  }

  // MARK: - Customization Parameters

  var filterMethod: (@Sendable (Item) -> Bool)? {
    didSet { scheduleEntriesUpdate() }
  }
  var sortMethod: (@Sendable (Item, Item) -> Bool)? {
    didSet { scheduleEntriesUpdate() }
  }
  var entryFilter: String {
    get { filterDebouncer.currentValue }
    set { filterDebouncer.currentValue = newValue }
  }

  // MARK: - Initialization

  init(
    filterMethod: (@Sendable (Item) -> Bool)? = nil,
    sortMethod: (@Sendable (Item, Item) -> Bool)? = nil,
    debounceDuration: Duration = .zero
  ) {
    self.filterMethod = filterMethod
    self.sortMethod = sortMethod
    filterDebouncer.debounceDuration = debounceDuration
  }

  // MARK: - Private Helpers

  @ObservationIgnored private var entriesTask:
    Task<(IdentifiedArrayOf<Item>, IdentifiedArrayOf<Item>), any Error>?

  private func scheduleEntriesUpdate() {
    entriesTask?.cancel()

    let task = Task {
      [baselineEntries, sortMethod, filterMethod, searchTerms]
      () throws -> (IdentifiedArrayOf<Item>, IdentifiedArrayOf<Item>) in

      try Task.checkCancellation()
      let sortedEntries: IdentifiedArrayOf<Item>
      if let sortMethod {
        sortedEntries = baselineEntries.sorted(by: sortMethod)
      } else {
        sortedEntries = baselineEntries
      }

      try Task.checkCancellation()
      let filteredByMethod: IdentifiedArrayOf<Item>
      if let filterMethod {
        filteredByMethod = sortedEntries.filter { filterMethod($0) }
      } else {
        filteredByMethod = sortedEntries
      }

      try Task.checkCancellation()
      guard !searchTerms.isEmpty else {
        return (sortedEntries, filteredByMethod)
      }

      try Task.checkCancellation()
      let filteredBySearchTerms = filteredByMethod.filter { entry in
        let searchable = entry.searchableString.lowercased()
        return searchTerms.allSatisfy { searchable.contains($0) }
      }

      try Task.checkCancellation()
      return (sortedEntries, filteredBySearchTerms)
    }

    entriesTask = task

    Task { [weak self] in
      guard let self else { return }

      let (sortedEntries, filteredBySearchTerms) = try await task.value
      try Task.checkCancellation()
      _allEntries = sortedEntries
      filteredEntries = filteredBySearchTerms
    }
  }
}
