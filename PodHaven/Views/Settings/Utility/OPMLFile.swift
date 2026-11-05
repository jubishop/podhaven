// Copyright Justin Bishop, 2025

import Foundation

@Observable @MainActor class OPMLFile: Identifiable {
  let id = UUID()
  let title: String
  let skippedCount: Int
  var totalCount: Int {
    failed.count
      + waiting.count
      + downloading.count
      + finished.count
  }
  var inProgressCount: Int {
    waiting.count + downloading.count
  }
  var failed: Set<OPMLOutline> = []
  var waiting: Set<OPMLOutline> = []
  var downloading: Set<OPMLOutline> = []
  var finished: Set<OPMLOutline> = []

  init(title: String, skippedCount: Int) {
    self.title = title
    self.skippedCount = skippedCount
  }
}
