// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

@Observable @MainActor
final class StubQueueableSelectableList: QueueableSelectableList {
  func addSelectedEpisodesToTopOfQueue() {}
  func addSelectedEpisodesToBottomOfQueue() {}
  func replaceQueue() {}
  func replaceQueueAndPlay() {}
}
