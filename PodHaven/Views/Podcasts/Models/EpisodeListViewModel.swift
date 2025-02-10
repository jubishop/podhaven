// Copyright Justin Bishop, 2025

import Factory
import Foundation
import IdentifiedCollections
import SwiftUI

@Observable @MainActor final class EpisodeListViewModel {
  let isSelected: Binding<Bool>
  let episode: Episode
  let isEditing: Bool

  init(
    isSelected: Binding<Bool>,
    episode: Episode,
    isEditing: Bool
  ) {
    self.isSelected = isSelected
    self.episode = episode
    self.isEditing = isEditing
  }
}
