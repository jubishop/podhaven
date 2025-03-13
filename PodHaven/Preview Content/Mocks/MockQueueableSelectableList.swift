// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

@Observable @MainActor
final class MockQueueableSelectableList: QueueableSelectableList {
  func addSelectedEpisodesToTopOfQueue() {}
  func addSelectedEpisodesToBottomOfQueue() {}
  func replaceQueue() {}
  func replaceQueueAndPlay() {}
}
