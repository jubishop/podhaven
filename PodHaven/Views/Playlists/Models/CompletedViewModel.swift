// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB
import IdentifiedCollections
import SwiftUI

@Observable @MainActor
class CompletedViewModel:
  PodcastQueueableModel,
  QueueableSelectableEpisodeList
{
  @ObservationIgnored @LazyInjected(\.alert) private var alert
  @ObservationIgnored @LazyInjected(\.observatory) private var observatory
  @ObservationIgnored @LazyInjected(\.playManager) private var playManager
  @ObservationIgnored @LazyInjected(\.queue) private var queue
  @ObservationIgnored @LazyInjected(\.repo) private var repo

  // MARK: - State Management

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

  // MARK: - PodcastQueueableModel

  func getPodcastEpisode(_ episode: PodcastEpisode) async throws -> PodcastEpisode { episode }
  func getEpisodeID(_ episode: PodcastEpisode) async throws -> Episode.ID { episode.id }

  // MARK: - QueueableSelectableEpisodeList

  var selectedPodcastEpisodes: [PodcastEpisode] { selectedEpisodes }
  var selectedEpisodeIDs: [Episode.ID] { selectedPodcastEpisodes.map(\.id) }
}
