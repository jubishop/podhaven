// Copyright Justin Bishop, 2025

import Foundation

@Observable @MainActor class TitleResultsViewModel {
  let searchText: String
  let titleResult: TitleResult?
  let unsavedPodcasts: [UnsavedPodcast]

  init(searchText: String, titleResult: TitleResult?) {
    self.searchText = searchText
    self.titleResult = titleResult
    if let titleResult = titleResult {
      unsavedPodcasts = titleResult.feeds.compactMap { try? $0.toUnsavedPodcast() }
    } else {
      unsavedPodcasts = []
    }
  }
}
