// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Logging
import SwiftUI

@Observable @MainActor
class EpisodesViewModel {
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory
  @ObservationIgnored @DynamicInjected(\.smartListRepo) private var smartListRepo

  private static let log = Log.as(LogSubsystem.EpisodesView.main)

  // MARK: - State Management

  enum LoadingState: Equatable {
    case loading
    case loaded
    case failed
  }

  private(set) var smartLists: [SmartList] = []
  private(set) var unreadCounts: [SmartList.ID: Int] = [:]
  private(set) var loadingState: LoadingState = .loading
  var editMode: EditMode = .inactive

  // MARK: - Smart List Observation

  func observeSmartLists() async {
    do {
      let observation: AsyncValueObservation<[SmartList]> = observatory.smartLists()
      for try await smartLists in observation {
        try Task.checkCancellation()
        Self.log.debug("Updating \(smartLists.count) observed smart lists")
        self.smartLists = smartLists
        loadingState = .loaded
      }
    } catch {
      Self.log.caughtError("observeSmartLists: observation failed", error)
      guard !Task.isCancelled else { return }
      loadingState = .failed
    }
  }

  // Drives the per-row unread badge. Failures only drop the badges (not the
  // whole hub), so they log without flipping loadingState.
  func observeUnreadCounts() async {
    do {
      let observation: AsyncValueObservation<[SmartList.ID: Int]> =
        observatory.smartListUnreadCounts()
      for try await counts in observation {
        try Task.checkCancellation()
        unreadCounts = counts
      }
    } catch {
      Self.log.caughtError("observeUnreadCounts: observation failed", error)
    }
  }

  // MARK: - SwiftUI List Functions

  func moveSmartList(from: IndexSet, to: Int) {
    guard from.count == 1, let from = from.first
    else { Assert.fatal("Somehow dragged none or several?") }
    guard smartLists.indices.contains(from) else {
      Self.log.error("moveSmartList: stale source index \(from) with \(smartLists.count) lists")
      return
    }

    let smartListID = smartLists[from].id
    Task { [weak self] in
      guard let self else { return }
      do {
        try await smartListRepo.moveSmartList(smartListID, to: to)
      } catch {
        Self.log.caughtError("moveSmartList: failed to move from \(from) to \(to)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func deleteSmartList(at offsets: IndexSet) {
    guard let index = offsets.first, smartLists.indices.contains(index) else { return }
    deleteSmartList(smartLists[index])
  }

  func deleteSmartList(_ smartList: SmartList) {
    alert(
      title: "Delete Smart List?",
      "Are you sure you want to delete \"\(smartList.title)\"?"
    ) { [weak self] in
      Button("Delete", role: .destructive) {
        guard let self else { return }
        self.performDeleteSmartList(smartList)
      }
      Button("Cancel", role: .cancel) {}
    }
  }

  // MARK: - Private Helpers

  private func performDeleteSmartList(_ smartList: SmartList) {
    Task { [weak self] in
      guard let self else { return }
      do {
        try await smartListRepo.delete(smartList.id)
      } catch {
        Self.log.caughtError("deleteSmartList: failed to delete \(smartList.id)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }
}
