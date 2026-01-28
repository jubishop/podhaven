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

  @ObservationIgnored private var entriesTask: Task<Void, Never>?

  private func scheduleEntriesUpdate() {
    entriesTask?.cancel()

    entriesTask = Task { [weak self, baselineEntries, sortMethod, filterMethod, searchTerms] in
      let (allEntries, filteredEntries) = await Self.computeEntries(
        baselineEntries: baselineEntries,
        sortMethod: sortMethod,
        filterMethod: filterMethod,
        searchTerms: searchTerms
      )
      guard !Task.isCancelled, let self else { return }

      self._allEntries = allEntries
      self.filteredEntries = filteredEntries
    }
  }

  private nonisolated static func computeEntries(
    baselineEntries: IdentifiedArrayOf<Item>,
    sortMethod: (@Sendable (Item, Item) -> Bool)?,
    filterMethod: (@Sendable (Item) -> Bool)?,
    searchTerms: [String]
  ) async -> (IdentifiedArrayOf<Item>, IdentifiedArrayOf<Item>) {
    let allEntries = sortMethod.map { baselineEntries.sorted(by: $0) } ?? baselineEntries
    let filteredByMethod = filterMethod.map { allEntries.filter($0) } ?? allEntries

    guard !searchTerms.isEmpty else {
      return (allEntries, filteredByMethod)
    }

    let filteredBySearchTerms = filteredByMethod.filter { entry in
      let searchable = entry.searchableString.lowercased()
      return searchTerms.allSatisfy { searchable.contains($0) }
    }

    return (allEntries, filteredBySearchTerms)
  }
}
