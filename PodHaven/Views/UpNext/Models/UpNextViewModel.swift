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

  var episodeList = SelectableListUseCase<PodcastEpisode, MediaURL>(idKeyPath: \.episode.media)
  var selectedEpisodeIDs: [Episode.ID] { episodeList.selectedEntries.map { $0.id } }
  var podcastEpisodes: PodcastEpisodeArray { episodeList.allEntries }

  // MARK: - Initialization

  func execute() async {
    do {
      for try await podcastEpisodes in observatory.queuedEpisodes() {
        self.episodeList.allEntries = podcastEpisodes
      }
    } catch {
      alert.andReport(error)
    }
  }

  // MARK: - Public Functions

  func moveItem(from: IndexSet, to: Int) {
    precondition(from.count == 1, "Somehow dragged several?")
    guard let from = from.first else { fatalError("No from in drag?") }

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
    Task { try await queue.dequeue(selectedEpisodeIDs) }
  }
}
