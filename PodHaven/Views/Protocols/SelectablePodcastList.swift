// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import IdentifiedCollections
import Logging

@MainActor protocol SelectablePodcastList: AnyObject {
  associatedtype PodcastType: PodcastDisplayable
  associatedtype SortMethodType: PodcastSortMethod

  var isSelecting: Bool { get set }
  var podcastList: SelectableListUseCase<PodcastWithEpisodeMetadata<PodcastType>> { get }

  var selectedPodcastsWithMetadata: [PodcastWithEpisodeMetadata<PodcastType>] { get }
  var selectedSavedPodcasts: [Podcast] { get }
  var selectedSavedPodcastIDs: [Podcast.ID] { get }
  var selectedPodcasts: [Podcast] { get async throws }  // Must Implement
  var selectedPodcastIDs: [Podcast.ID] { get async throws }

  var currentSortMethod: SortMethodType { get set }
  var allSortMethods: [SortMethodType] { get }

  var anySelectedSubscribed: Bool { get }
  var anySelectedUnsubscribed: Bool { get }
  var anySelectedSaved: Bool { get }

  func deleteSelectedPodcasts()
  func subscribeSelectedPodcasts()
  func unsubscribeSelectedPodcasts()
}

extension SelectablePodcastList {
  private var repo: any Databasing { Container.shared.repo() }
  private var alert: Alert { Container.shared.alert() }

  private var log: Logger { Log.as(LogSubsystem.ViewProtocols.podcastList) }

  // MARK: - Selection Getters

  var selectedPodcastsWithMetadata: [PodcastWithEpisodeMetadata<PodcastType>] {
    podcastList.selectedEntries.elements
  }
  var selectedSavedPodcasts: [Podcast] {
    selectedPodcastsWithMetadata.compactMap { $0.getPodcast() }
  }
  var selectedSavedPodcastIDs: [Podcast.ID] { selectedSavedPodcasts.map(\.id) }
  var selectedPodcastIDs: [Podcast.ID] {
    get async throws {
      try await selectedPodcasts.map(\.id)
    }
  }

  // MARK: - "Any"? Getters

  var anySelectedSubscribed: Bool {
    selectedPodcastsWithMetadata.contains(where: \.subscribed)
  }

  var anySelectedUnsubscribed: Bool {
    selectedPodcastsWithMetadata.contains { $0.subscribed == false }
  }

  var anySelectedSaved: Bool {
    selectedPodcastsWithMetadata.contains(where: \.isSaved)
  }

  // MARK: - Actions

  func deleteSelectedPodcasts() {
    guard let savedPodcastIDs = selectedSavedPodcastIDs, !savedPodcastIDs.empty else { return }

    Task {
      try await repo.delete(savedPodcastIDs)
    }
  }

  func subscribeSelectedPodcasts() {
    Task { [weak self] in
      guard let self else { return }

      let podcastIDs = try await selectedPodcastIDs
      try await repo.markSubscribed(podcastIDs)
    }
  }

  func unsubscribeSelectedPodcasts() {
    guard let savedPodcastIDs = selectedSavedPodcastIDs, !savedPodcastIDs.empty else { return }

    Task {
      try await repo.markUnsubscribed(savedPodcastIDs)
    }
  }
}

extension SelectablePodcastList where PodcastType == Podcast {
  var selectedPodcasts: [Podcast] {
    get async throws { selectedPodcastsWithMetadata.map(\.podcast) }
  }
}
