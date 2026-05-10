// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import IdentifiedCollections
import Logging

@MainActor protocol SelectablePodcastList: AnyObject {
  associatedtype PodcastType: PodcastListable

  var podcastList: PowerList<PodcastWithEpisodeMetadata<PodcastType>> { get }

  var selectedPodcastsWithMetadata: [PodcastWithEpisodeMetadata<PodcastType>] { get }
  var selectedSavedPodcastIDs: [Podcast.ID] { get }

  // Must Implement: Iterates over selected podcasts, calling the closure for each one
  func forEachSelectedPodcast(
    perform action: @escaping @Sendable (Podcast) async throws -> Void
  ) async

  var anySelectedSubscribed: Bool { get }
  var anySelectedUnsubscribed: Bool { get }
  var anySelectedSaved: Bool { get }

  func deleteSelectedPodcasts()
  func subscribeSelectedPodcasts()
  func unsubscribeSelectedPodcasts()
  func applyTagToSelectedPodcasts(_ tagID: Tag.ID)
  func removeTagFromSelectedPodcasts(_ tagID: Tag.ID)
}

extension SelectablePodcastList {
  private var repo: any Databasing { Container.shared.repo() }
  private var alert: Alert { Container.shared.alert() }

  nonisolated private static var log: Logger { Log.as(LogSubsystem.ViewProtocols.podcastList) }

  // MARK: - Selection Getters

  var selectedPodcastsWithMetadata: [PodcastWithEpisodeMetadata<PodcastType>] {
    podcastList.selectedEntries.elements
  }
  var selectedSavedPodcastIDs: [Podcast.ID] {
    selectedPodcastsWithMetadata.compactMap(\.podcastID)
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
    let savedPodcastIDs = selectedSavedPodcastIDs
    guard !savedPodcastIDs.isEmpty else { return }

    Task { [weak self] in
      guard let self else { return }

      do {
        try await repo.deletePodcast(savedPodcastIDs)
      } catch {
        Self.log.caughtError(
          "deleteSelectedPodcasts: failed to delete \(savedPodcastIDs.count) podcasts",
          error
        )
      }
    }
  }

  func subscribeSelectedPodcasts() {
    Task { [weak self] in
      guard let self else { return }

      await forEachSelectedPodcast { podcast in
        try await Container.shared.repo().markSubscribed(podcast.id)
      }
    }
  }

  func unsubscribeSelectedPodcasts() {
    let savedPodcastIDs = selectedSavedPodcastIDs
    guard !savedPodcastIDs.isEmpty else { return }

    Task { [weak self] in
      guard let self else { return }

      do {
        try await repo.markUnsubscribed(savedPodcastIDs)
      } catch {
        Self.log.caughtError(
          "unsubscribeSelectedPodcasts: failed to unsubscribe \(savedPodcastIDs.count) podcasts",
          error
        )
      }
    }
  }

  func applyTagToSelectedPodcasts(_ tagID: Tag.ID) {
    let podcastIDs = selectedSavedPodcastIDs
    guard !podcastIDs.isEmpty else { return }

    let log = Self.log
    Task {
      do {
        try await Container.shared.repo().addTag(tagID, toPodcasts: podcastIDs)
      } catch {
        log.caughtError(
          "applyTagToSelectedPodcasts: failed for \(podcastIDs.count) podcasts, tag \(tagID)",
          error
        )
      }
    }
  }

  func removeTagFromSelectedPodcasts(_ tagID: Tag.ID) {
    let podcastIDs = selectedSavedPodcastIDs
    guard !podcastIDs.isEmpty else { return }

    let log = Self.log
    Task {
      do {
        _ = try await Container.shared.repo().removeTag(tagID, fromPodcasts: podcastIDs)
      } catch {
        log.caughtError(
          "removeTagFromSelectedPodcasts: failed for \(podcastIDs.count) podcasts, tag \(tagID)",
          error
        )
      }
    }
  }
}

// MARK: - Tag Selection Helpers

extension SelectablePodcastList {
  // True only when every selected podcast is saved (and so carries
  // observable tag rows). Mirrors `SelectableEpisodeList.selectionHasTagData`.
  var selectionHasTagData: Bool {
    !selectedPodcastsWithMetadata.isEmpty
      && selectedPodcastsWithMetadata.allSatisfy(\.isSaved)
  }

  var selectedPodcastsTagUnion: Set<Tag.ID> {
    selectedPodcastsWithMetadata.reduce(into: Set<Tag.ID>()) { union, metadata in
      union.formUnion(metadata.tags.ids)
    }
  }

  var selectedPodcastsTagIntersection: Set<Tag.ID> {
    var intersection: Set<Tag.ID>?
    for metadata in selectedPodcastsWithMetadata {
      let tagIDs = Set(metadata.tags.ids)
      if let current = intersection {
        let next = current.intersection(tagIDs)
        if next.isEmpty { return [] }
        intersection = next
      } else {
        intersection = tagIDs
      }
    }
    return intersection ?? []
  }
}

extension SelectablePodcastList where PodcastType == Podcast {
  func forEachSelectedPodcast(
    perform action: @escaping @Sendable (Podcast) async throws -> Void
  ) async {
    for podcastWithMetadata in selectedPodcastsWithMetadata {
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

extension SelectablePodcastList where PodcastType == ListablePodcast {
  func forEachSelectedPodcast(
    perform action: @escaping @Sendable (Podcast) async throws -> Void
  ) async {
    let repo = Container.shared.repo()

    for podcastID in selectedSavedPodcastIDs {
      do {
        guard let podcastSeries = try await repo.podcastSeries(podcastID) else {
          Self.log.warning("forEachSelectedPodcast: podcast \(podcastID) not found")
          continue
        }
        try await action(podcastSeries.podcast)
      } catch {
        Self.log.caughtError(
          "forEachSelectedPodcast: action failed for podcast \(podcastID)",
          error
        )
      }
    }
  }
}
