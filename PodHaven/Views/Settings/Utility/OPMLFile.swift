// Copyright Justin Bishop, 2025

import Foundation
import OrderedCollections

@Observable @MainActor class OPMLFile: Identifiable {
  enum Phase {
    case reviewing, importing
  }

  let id = UUID()
  let title: String
  let skippedCount: Int
  var phase: Phase = .reviewing
  var totalCount: Int {
    failed.count
      + waiting.count
      + downloading.count
      + finished.count
  }
  var inProgressCount: Int {
    waiting.count + downloading.count
  }
  var failed: OrderedSet<OPMLOutline> = []
  var waiting: OrderedSet<OPMLOutline> = []
  var downloading: OrderedSet<OPMLOutline> = []
  var finished: OrderedSet<OPMLOutline> = []

  init(title: String, skippedCount: Int) {
    self.title = title
    self.skippedCount = skippedCount
  }
}
