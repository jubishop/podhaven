// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB
import IdentifiedCollections
import SwiftUI

@Observable @MainActor final class CompletedViewModel {
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
      for try await podcastEpisodes in observatory.completedPodcastEpisodes() {
        self.episodeList.allEntries = IdentifiedArray(uniqueElements: podcastEpisodes)
      }
    } catch {
      alert("Couldn't execute CompletedViewModel")
    }
  }

  // MARK: - Public Functions

  func playItem(_ podcastEpisode: PodcastEpisode) {
    Task {
      try await playManager.load(podcastEpisode)
      await playManager.play()
    }
  }
}

