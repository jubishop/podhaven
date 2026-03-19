// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import IdentifiedCollections
import Logging

@MainActor protocol SelectablePodcastList: AnyObject {
  associatedtype PodcastType: PodcastDisplayable

  var podcastList: PowerList<PodcastWithEpisodeMetadata<PodcastType>> { get }

  var selectedPodcastsWithMetadata: [PodcastWithEpisodeMetadata<PodcastType>] { get }
  var selectedSavedPodcasts: [Podcast] { get }
  var selectedSavedPodcastIDs: [Podcast.ID] { get }

  // Must Implement: Iterates over selected podcasts, calling the closure for each one that passes
  // the filter. Subscribe passes all; delete/unsubscribe passes only isSaved to avoid creating
  // DB rows for unsaved search results.
  func forEachSelectedPodcast(
    where filter: @escaping (PodcastWithEpisodeMetadata<PodcastType>) -> Bool,
    perform action: @escaping @Sendable (Podcast) async throws -> Void
  ) async

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

  nonisolated private static var log: Logger { Log.as(LogSubsystem.ViewProtocols.podcastList) }

  // MARK: - Selection Getters

  var selectedPodcastsWithMetadata: [PodcastWithEpisodeMetadata<PodcastType>] {
    podcastList.selectedEntries.elements
  }
  var selectedSavedPodcasts: [Podcast] {
    selectedPodcastsWithMetadata.compactMap { $0.getPodcast() }
  }
  var selectedSavedPodcastIDs: [Podcast.ID] { selectedSavedPodcasts.map(\.id) }

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
    Task { [weak self] in
      guard let self else { return }

      await forEachSelectedPodcast(where: { $0.isSaved }) { podcast in
        try await Container.shared.repo().deletePodcast(podcast.id)
      }
    }
  }

  func subscribeSelectedPodcasts() {
    Task { [weak self] in
      guard let self else { return }

      await forEachSelectedPodcast(where: { _ in true }) { podcast in
        try await Container.shared.repo().markSubscribed(podcast.id)
      }
    }
  }

  func unsubscribeSelectedPodcasts() {
    Task { [weak self] in
      guard let self else { return }

      await forEachSelectedPodcast(where: { $0.isSaved }) { podcast in
        try await Container.shared.repo().markUnsubscribed(podcast.id)
      }
    }
  }
}

extension SelectablePodcastList where PodcastType == Podcast {
  func forEachSelectedPodcast(
    where filter: @escaping (PodcastWithEpisodeMetadata<Podcast>) -> Bool,
    perform action: @escaping @Sendable (Podcast) async throws -> Void
  ) async {
    for podcastWithMetadata in selectedPodcastsWithMetadata where filter(podcastWithMetadata) {
      do {
        try await action(podcastWithMetadata.podcast)
      } catch {
        Self.log.caughtError(
          "forEachSelectedPodcast: action failed for \(podcastWithMetadata.podcast.title)",
          error
        )
      }
    }
  }
}
