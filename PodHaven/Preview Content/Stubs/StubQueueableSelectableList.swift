#if DEBUG
// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

@Observable @MainActor class StubQueueableSelectableList: QueueableSelectableList {
  func addSelectedEpisodesToTopOfQueue() {}
  func addSelectedEpisodesToBottomOfQueue() {}
  func replaceQueueWithSelected() {}
  func replaceQueueWithSelectedAndPlay() {}
  func cacheSelectedEpisodes() {}
}
#endif
