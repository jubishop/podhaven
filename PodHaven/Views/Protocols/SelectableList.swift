// Copyright Justin Bishop, 2025

import Foundation
import IdentifiedCollections

@MainActor protocol SelectableList<Item> {
  associatedtype Item: Identifiable & Sendable where Item.ID: Hashable & Sendable

  var isSelecting: Bool { get }
  func setSelecting(_ value: Bool)

  var anyNotSelected: Bool { get }
  var anySelected: Bool { get }

  var isSelected: BindableDictionary<Item.ID, Bool> { get }
  var selectedEntries: IdentifiedArrayOf<Item> { get }
  var selectedEntryIDs: [Item.ID] { get }

  func selectAllEntries()
  func unselectAllEntries()
}
