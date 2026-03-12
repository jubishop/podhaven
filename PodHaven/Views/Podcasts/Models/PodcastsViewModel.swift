// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Logging

@Observable @MainActor class PodcastsViewModel {
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory

  private static let log = Log.as(LogSubsystem.PodcastsView.main)

  // MARK: - State

  var counts: PodcastCounts?

  // MARK: - Initialization

  func execute() async {
    do {
      for try await counts in observatory.podcastCounts() {
        guard !Task.isCancelled else { return }
        self.counts = counts
      }
    } catch {
      Self.log.caughtError("execute: podcastCounts observation failed", error)
    }
  }
}
