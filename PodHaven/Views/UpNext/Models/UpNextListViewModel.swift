// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import IdentifiedCollections
import Logging
import SwiftUI

@Observable @MainActor class UpNextListViewModel {
  @ObservationIgnored @DynamicInjected(\.navigation) private var navigation
  @ObservationIgnored @DynamicInjected(\.playManager) private var playManager
  @ObservationIgnored @DynamicInjected(\.queue) private var queue

  private static let log = Log.as(LogSubsystem.UpNextView.list)

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
    Task { [weak self] in
      guard let self else { return }
      do {
        try await playManager.load(podcastEpisode)
        await playManager.play()
      } catch {
        Self.log.error(error)
      }
    }
  }

  func playNext() {
    Task { [weak self] in
      guard let self else { return }
      try await queue.unshift(episode.id)
    }

  }

  func viewDetails() {
    Task { [weak self] in
      guard let self else { return }
      navigation.showEpisode(
        podcastEpisode.podcast.subscribed ? .subscribed : .unsubscribed,
        podcastEpisode
      )
    }
  }

  func delete() {
    Task { [weak self] in
      guard let self else { return }
      try await queue.dequeue(episode.id)
    }
  }
}
