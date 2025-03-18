// Copyright Justin Bishop, 2025

import Foundation

@Observable @MainActor class TitleResultsViewModel {
  let titleResult: SearchResult?

  init(titleResult: SearchResult?) {
    self.titleResult = titleResult
  }
}
