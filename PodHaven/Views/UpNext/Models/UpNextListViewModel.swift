// Copyright Justin Bishop, 2025

import Factory
import Foundation
import IdentifiedCollections
import SwiftUI

@Observable @MainActor final class UpNextListViewModel {
  @ObservationIgnored @Injected(\.queue) private var queue

  let isSelected: Binding<Bool>
  let podcastEpisode: PodcastEpisode
  let editMode: Binding<EditMode>

  var podcast: Podcast { podcastEpisode.podcast }
  var episode: Episode { podcastEpisode.episode }
  var isEditing: Bool { editMode.wrappedValue.isEditing == true }

  init(
    isSelected: Binding<Bool>,
    podcastEpisode: PodcastEpisode,
    editMode: Binding<EditMode>
  ) {
    self.isSelected = isSelected
    self.podcastEpisode = podcastEpisode
    self.editMode = editMode
  }

  func playNow() {
    Task { @PlayActor in
      try await PlayManager.shared.load(podcastEpisode)
      PlayManager.shared.play()
    }
  }

  func playNext() {
    Task {
      try await queue.unshift(episode.id)
    }
  }

  func viewDetails() {
    Task {
      Navigation.shared.showEpisode(podcastEpisode)
    }
  }

  func delete() {
    Task {
      try await queue.dequeue(episode.id)
    }
  }
}
