// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

@Observable @MainActor class PersonResultsViewModel: QueueableSelectableList, EpisodeQueueable {
  // MARK: - Data

  private let searchResult: PersonSearchResult
  let unsavedPodcastEpisodes: [UnsavedPodcastEpisode]
  var searchText: String { searchResult.searchedText }
  var personResult: PersonResult? { searchResult.personResult }

  // MARK: - EpisodeQueuable protocols

  typealias EpisodeType = Episode

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

  // MARK: - Initialization

  init(searchResult: PersonSearchResult) {
    self.searchResult = searchResult
    if let personResult = searchResult.personResult {
      unsavedPodcastEpisodes = personResult.items.compactMap { try? $0.toUnsavedPodcastEpisode() }
    } else {
      unsavedPodcastEpisodes = []
    }
  }

  func execute() async {
  }

  // MARK: - Public Functions

  func queueEpisodeOnTop(_ episode: Episode) {
  }

  func queueEpisodeAtBottom(_ episode: Episode) {
  }

  func playEpisode(_ episode: Episode) {
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
