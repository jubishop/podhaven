// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import IdentifiedCollections
import Logging
import SwiftUI

@Observable @MainActor class UpNextListViewModel {
  let isSelected: Binding<Bool>
  let podcastEpisode: PodcastEpisode
  let editMode: EditMode
  var isEditing: Bool { editMode.isEditing == true }

  init(
    isSelected: Binding<Bool>,
    podcastEpisode: PodcastEpisode,
    editMode: EditMode
  ) {
    self.isSelected = isSelected
    self.podcastEpisode = podcastEpisode
    self.editMode = editMode
  }
}
