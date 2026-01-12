// Copyright Justin Bishop, 2025

import Foundation

@Observable @MainActor class OPMLFile: Identifiable {
  let id = UUID()
  let title: String
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

  init(title: String) {
    self.title = title
  }
}
