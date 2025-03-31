// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

@Observable @MainActor final class EpisodeListViewModel {
  let isSelected: Binding<Bool>
  let episode: Episode
  let isSelecting: Bool

  init(isSelected: Binding<Bool>, episode: Episode, isSelecting: Bool) {
    self.isSelected = isSelected
    self.episode = episode
    self.isSelecting = isSelecting
  }
}
