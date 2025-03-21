// Copyright Justin Bishop, 2025

import Foundation

@Observable @MainActor class AllFieldsResultsViewModel {
  let searchText: String
  let termResult: TermResult?
  let unsavedPodcasts: [UnsavedPodcast]

  init(searchText: String, termResult: TermResult?) {
    self.searchText = searchText
    self.termResult = termResult
    if let termResult = termResult {
      unsavedPodcasts = termResult.feeds.compactMap { try? $0.toUnsavedPodcast() }
    } else {
      unsavedPodcasts = []
    }
  }
}
