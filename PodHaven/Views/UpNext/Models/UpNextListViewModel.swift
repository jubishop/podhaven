// Copyright Justin Bishop, 2025

import Factory
import Foundation
import IdentifiedCollections
import SwiftUI

@Observable @MainActor final class UpNextListViewModel {
  @ObservationIgnored @LazyInjected(\.navigation) private var navigation
  @ObservationIgnored @LazyInjected(\.playManager) private var playManager
  @ObservationIgnored @LazyInjected(\.queue) private var queue

  let isSelected: Binding<Bool>
  let podcastEpisode: PodcastEpisode
  let editMode: EditMode

  var podcast: Podcast { podcastEpisode.podcast }
  var episode: Episode { podcastEpisode.episode }
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

  func playNow() {
    Task {
      try await playManager.load(podcastEpisode)
      await playManager.play()
    }
  }

  func playNext() {
    Task { try await queue.unshift(episode.id) }
  }

  func viewDetails() {
    Task {
      navigation.showEpisode(
        podcastEpisode.podcast.subscribed ? .subscribed : .unsubscribed,
        podcastEpisode
      )
    }
  }

  func delete() {
    Task { try await queue.dequeue(episode.id) }
  }
}
