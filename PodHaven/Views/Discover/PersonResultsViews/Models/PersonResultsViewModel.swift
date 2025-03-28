// Copyright Justin Bishop, 2025

import Factory
import Foundation
import IdentifiedCollections
import SwiftUI

@Observable @MainActor class PersonResultsViewModel: QueueableSelectableList, EpisodeQueueable {
  @ObservationIgnored @LazyInjected(\.alert) private var alert
  @ObservationIgnored @LazyInjected(\.repo) private var repo

  // MARK: - Data

  private let searchResult: PersonSearchResult
  var searchText: String { searchResult.searchedText }
  var personResult: PersonResult? { searchResult.personResult }

  // MARK: - EpisodeQueuable protocols

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
          uniqueElements: personResult.items.compactMap {
            try? $0.toUnsavedPodcastEpisode(merging: existingEpisodes[id: $0.enclosureUrl])
          },
          id: \.unsavedEpisode.media
        )
        self.existingEpisodes = existingEpisodes
      }
    } catch {
      alert.andReport(error)
    }
  }

  // MARK: - Public Functions

  func queueEpisodeOnTop(_ episode: UnsavedPodcastEpisode) {
  }

  func queueEpisodeAtBottom(_ episode: UnsavedPodcastEpisode) {
  }

  func playEpisode(_ episode: UnsavedPodcastEpisode) {
  }

  func addSelectedEpisodesToTopOfQueue() {
  }

  func addSelectedEpisodesToBottomOfQueue() {
  }

  func replaceQueue() {
  }

  func replaceQueueAndPlay() {
  }
}
