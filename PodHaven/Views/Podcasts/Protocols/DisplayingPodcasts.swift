// Copyright Justin Bishop, 2025

import Foundation

enum PodcastDisplayMode: String, DefaultsStorable {
  case grid
  case list
}

@MainActor protocol DisplayingPodcasts: AnyObject {
  var displayMode: PodcastDisplayMode { get set }
  func toggleDisplayMode()
}

extension DisplayingPodcasts {
  func toggleDisplayMode() {
    displayMode = displayMode == .grid ? .list : .grid
  }
}
