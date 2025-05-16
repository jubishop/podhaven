// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import SwiftUI

@Observable @MainActor final class UpNextViewModel {
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory
  @ObservationIgnored @DynamicInjected(\.queue) private var queue
  @ObservationIgnored @DynamicInjected(\.repo) private var repo
  private var playManager: PlayManager { get async { await Container.shared.playManager() } }

  // MARK: - State Management

  var editMode: EditMode = .inactive
  var isEditing: Bool { editMode == .active }

  var episodeList = SelectableListUseCase<PodcastEpisode, Episode.ID>(idKeyPath: \.id)
  var podcastEpisodes: IdentifiedArray<Episode.ID, PodcastEpisode> { episodeList.allEntries }

  // MARK: - Initialization

  func execute() async {
    do {
      for try await podcastEpisodes in observatory.queuedPodcastEpisodes() {
        self.episodeList.allEntries = IdentifiedArray(uniqueElements: podcastEpisodes)
      }
    } catch {
      alert("Couldn't execute UpNextViewModel")
    }
  }

  // MARK: - Public Functions

  func moveItem(from: IndexSet, to: Int) {
    guard from.count == 1, let from = from.first
    else { Log.fatal("Somehow dragged none or several?") }

    Task { try await queue.insert(podcastEpisodes[from].episode.id, at: to) }
  }

  func playItem(_ podcastEpisode: PodcastEpisode) {
    Task {
      try await playManager.load(podcastEpisode)
      await playManager.play()
    }
  }

  func deleteItem(_ podcastEpisode: PodcastEpisode) {
    Task { try await queue.dequeue(podcastEpisode.episode.id) }
  }

  func deleteSelected() {
    Task { try await queue.dequeue(episodeList.selectedEntryIDs) }
  }
}
