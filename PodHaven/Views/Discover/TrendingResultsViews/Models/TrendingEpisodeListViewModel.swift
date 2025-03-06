// Copyright Justin Bishop, 2025 

import Factory
import Foundation
import IdentifiedCollections
import SwiftUI

@Observable @MainActor final class TrendingEpisodeListViewModel {
  let isSelected: Binding<Bool>
  let unsavedEpisode: UnsavedEpisode
  let isSelecting: Bool

  init(
    isSelected: Binding<Bool>,
    unsavedEpisode: UnsavedEpisode,
    isSelecting: Bool
  ) {
    self.isSelected = isSelected
    self.unsavedEpisode = unsavedEpisode
    self.isSelecting = isSelecting
  }
}
