// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB
import IdentifiedCollections
import SwiftUI

@Observable @MainActor final class UpNextViewModel {
  @ObservationIgnored @LazyInjected(\.alert) private var alert
  @ObservationIgnored @LazyInjected(\.observatory) private var observatory
  @ObservationIgnored @LazyInjected(\.playManager) private var playManager
  @ObservationIgnored @LazyInjected(\.queue) private var queue
  @ObservationIgnored @LazyInjected(\.repo) private var repo

  // MARK: - State Management

  var editMode: EditMode = .inactive
  var isEditing: Bool { editMode == .active }

  var episodeList = SelectableListUseCase<PodcastEpisode, Episode.ID>(idKeyPath: \.id)
  var podcastEpisodes: IdentifiedArray<Episode.ID, PodcastEpisode> { episodeList.allEntries }

  // MARK: - Initialization

  func execute() async {
    do {
      for try await podcastEpisodes in observatory.queuedEpisodes() {
        self.episodeList.allEntries = IdentifiedArray(uniqueElements: podcastEpisodes)
      }
    } catch {
      alert.andReport("Couldn't execute UpNextViewModel")
    }
  }

  // MARK: - Public Functions

  func moveItem(from: IndexSet, to: Int) {
    guard from.count == 1, let from = from.first
    else { Log.fatal("Somehow dragged none or several?") }

    Task { try await queue.insert(podcastEpisodes[from].episode.id, at: to) }
  }

  func moveToTop(_ podcastEpisode: PodcastEpisode) {
    Task { try await queue.unshift(podcastEpisode.episode.id) }
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
