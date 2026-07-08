// Copyright Justin Bishop, 2026

import FactoryKit
import IdentifiedCollections
import Testing

@testable import PodHaven

@Suite("of PowerList tests", .container)
@MainActor final class PowerListTests {
  private struct Item: Searchable {
    let id: Int
    let searchableString: String
  }

  @Test("no client filter/sort/search updates entries synchronously")
  func noClientWorkUpdatesEntriesSynchronously() {
    let list = PowerList<Item>()
    let entries = IdentifiedArray(
      uniqueElements: [
        Item(id: 1, searchableString: "first"),
        Item(id: 2, searchableString: "second"),
      ]
    )

    list.allEntries = entries

    // No suspension point between the assignment and these reads: with no
    // sortMethod, filterMethod, or search terms there is nothing to compute,
    // so both arrays reflect the new baseline on the same runloop turn.
    #expect(list.allEntries == entries)
    #expect(list.filteredEntries == entries)
  }

  @Test("exiting selection mode clears selection")
  func exitingSelectionModeClearsSelection() {
    let list = PowerList<Item>()
    list.allEntries = IdentifiedArray(
      uniqueElements: [
        Item(id: 1, searchableString: "first"),
        Item(id: 2, searchableString: "second"),
      ]
    )

    list.setSelecting(true)
    list.isSelected[1] = true
    #expect(list.anySelected)

    // Ending a selection session discards its picks: a stale checkmark
    // surviving into a later session would silently include an unintended
    // row in the next bulk action.
    list.setSelecting(false)
    list.setSelecting(true)
    #expect(!list.anySelected)
    #expect(!list.isSelected[1])
  }

  @Test("a client filterMethod still recomputes via the async path")
  func clientFilterRecomputesViaAsyncPath() async throws {
    let list = PowerList<Item>(filterMethod: { $0.searchableString.contains("keep") })
    let entries = IdentifiedArray(
      uniqueElements: [
        Item(id: 1, searchableString: "keep this"),
        Item(id: 2, searchableString: "drop this"),
      ]
    )

    list.allEntries = entries

    // Genuine client-side work stays on the async Task, so filteredEntries is
    // not populated synchronously.
    #expect(list.filteredEntries.isEmpty)

    try await Wait.until(
      { @MainActor in list.filteredEntries.ids.elements == [1] },
      { @MainActor in "filter never settled; got \(list.filteredEntries.ids.elements)" }
    )
    #expect(list.allEntries == entries)
  }
}
