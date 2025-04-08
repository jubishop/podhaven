// Copyright Justin Bishop, 2025

import Factory
import Foundation
import IdentifiedCollections
import SwiftUI

@Observable @MainActor
class PersonResultsListViewModel:
  PodcastEpisodeGettable,
  PodcastQueueableModel,
  QueueableSelectableEpisodeList
{
  @ObservationIgnored @LazyInjected(\.alert) private var alert
  @ObservationIgnored @LazyInjected(\.repo) private var repo

  // MARK: - Data

  private let searchResult: PersonSearchResult
  var searchText: String { searchResult.searchText }
  var personResult: PersonResult? { searchResult.personResult }

  // MARK: - Protocol Conformance

  typealias EpisodeType = UnsavedPodcastEpisode

  // MARK: - State Management

  private var _isSelecting = false
  var isSelecting: Bool {
    get { _isSelecting }
    set { withAnimation { _isSelecting = newValue } }
  }
  var unplayedOnly: Bool = false

  var episodeList = SelectableListUseCase<UnsavedPodcastEpisode, MediaURL>(
    idKeyPath: \.unsavedEpisode.media
  )
  private var existingEpisodes: IdentifiedArray<MediaURL, PodcastEpisode>?

  // MARK: - Initialization

  init(searchResult: PersonSearchResult) {
    self.searchResult = searchResult
  }

  func execute() async {
    do {
      if let personResult = personResult {
        let existingEpisodes = IdentifiedArray(
          uniqueElements: try await repo.episodes(personResult.items.map(\.enclosureUrl)),
          id: \.episode.media
        )
        episodeList.allEntries = IdentifiedArray(
          personResult.items.compactMap {
            try? $0.toUnsavedPodcastEpisode(merging: existingEpisodes[id: $0.enclosureUrl])
          },
          id: \.unsavedEpisode.media,
          uniquingIDsWith: { old, new in
            guard let existingEpisode = existingEpisodes[id: old.unsavedEpisode.media]
            else { return new }

            return (old.unsavedPodcast.feedURL == existingEpisode.podcast.feedURL) ? old : new
          }
        )
        self.existingEpisodes = existingEpisodes
      }
    } catch {
      alert.andReport(error)
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

  var selectedEpisodeIDs: [Episode.ID] {
    get async throws {
      try await selectedPodcastEpisodes.map(\.id)
    }
  }
}
