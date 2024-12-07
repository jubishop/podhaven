// Copyright Justin Bishop, 2024 

import Foundation

@Observable @MainActor final class SeriesViewModel {
  let podcast: Podcast

  init(podcast: Podcast) {
    self.podcast = podcast
  }
}
