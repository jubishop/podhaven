// Copyright Justin Bishop, 2025

import Factory
import Foundation
import IdentifiedCollections
import SwiftUI

@Observable @MainActor
class PersonResultsListViewModel:
  EpisodeUpserter,
  QueueableSelectableListModel,
  UnsavedPodcastQueueableModel
{
  @ObservationIgnored @LazyInjected(\.alert) private var alert
  @ObservationIgnored @LazyInjected(\.repo) private var repo

  // MARK: - Data

  private let searchResult: PersonSearchResult
  var searchText: String { searchResult.searchedText }
  var personResult: PersonResult? { searchResult.personResult }

  // MARK: - Protocol Conformance

  typealias EpisodeId = MediaURL
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

  // MARK: - QueueableSelectableListModel

  func upsertSelectedEpisodes() async throws -> [PodcastEpisode] {
    try await repo.upsertPodcastEpisodes(selectedEpisodes)
  }

  // MARK: - EpisodeUpserter

  func upsert(_ episode: UnsavedPodcastEpisode) async throws -> PodcastEpisode {
    try await repo.upsertPodcastEpisode(episode)
  }
}
