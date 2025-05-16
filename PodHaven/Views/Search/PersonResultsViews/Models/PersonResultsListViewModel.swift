// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import IdentifiedCollections
import SwiftUI

@Observable @MainActor
class PersonResultsListViewModel:
  PodcastQueueableModel,
  QueueableSelectableEpisodeList
{
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.repo) private var repo

  // MARK: - Data

  var searchText: String { searchResult.searchText }
  var personResult: PersonResult? { searchResult.personResult }

  private let searchResult: PersonSearchResult

  // MARK: - State Management

  var unplayedOnly: Bool = false

  var episodeList = SelectableListUseCase<UnsavedPodcastEpisode, MediaURL>(
    idKeyPath: \.unsavedEpisode.media
  )
  private var existingPodcastEpisodes: IdentifiedArray<MediaURL, PodcastEpisode>?

  // MARK: - Initialization

  init(searchResult: PersonSearchResult) {
    self.searchResult = searchResult
  }

  func execute() async {
    do {
      if let personResult = personResult {
        existingPodcastEpisodes = IdentifiedArray(
          uniqueElements: try await repo.episodes(personResult.items.map(\.enclosureUrl)),
          id: \.episode.media
        )
        episodeList.allEntries = personResult.toPodcastEpisodeArray(
          merging: existingPodcastEpisodes
        )
      }
    } catch {
      alert("Couldn't execute PersonResultsListViewModel")
    }
  }

  // MARK: - PodcastQueueableModel

  func getPodcastEpisode(_ episode: UnsavedPodcastEpisode) async throws -> PodcastEpisode {
    try await repo.upsertPodcastEpisode(episode)
  }

  func getEpisodeID(_ episode: UnsavedPodcastEpisode) async throws -> Episode.ID {
    try await getPodcastEpisode(episode).id
  }

  // MARK: - QueueableSelectableEpisodeList

  var selectedPodcastEpisodes: [PodcastEpisode] {
    get async throws {
      try await repo.upsertPodcastEpisodes(selectedEpisodes)
    }
  }
}
