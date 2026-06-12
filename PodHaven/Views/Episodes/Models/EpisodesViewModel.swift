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
    } catch is CancellationError {
    } catch {
      Self.log.caughtError("observeSmartLists: observation failed", error)
      guard !Task.isCancelled else { return }
      loadingState = .failed
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
}
