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
    let selectedCount = selectedPodcastsWithMetadata.count
    let savedPodcastIDs = selectedSavedPodcastIDs
    guard !savedPodcastIDs.isEmpty else {
      Self.log.notice("deleteSelectedPodcasts: no saved podcasts among \(selectedCount) selected")
      return
    }

    Self.log.debug(
      "deleteSelectedPodcasts: deleting \(savedPodcastIDs.count) of \(selectedCount) selected podcasts"
    )

    Task { [weak self] in
      guard let self else { return }

      do {
        try await repo.deletePodcast(savedPodcastIDs)
      } catch {
        Self.log.caughtError(
          "deleteSelectedPodcasts: failed to delete \(savedPodcastIDs.count) podcasts",
          error
        )
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func subscribeSelectedPodcasts() {
    let selectedCount = selectedPodcastsWithMetadata.count
    guard anySelectedUnsubscribed else {
      Self.log.notice(
        "subscribeSelectedPodcasts: no unsubscribed podcasts among \(selectedCount) selected"
      )
      return
    }

    Self.log.debug("subscribeSelectedPodcasts: subscribing \(selectedCount) selected podcasts")

    Task { [weak self] in
      guard let self else { return }

      await forEachSelectedPodcast { podcast in
        try await Container.shared.repo().markSubscribed(podcast.id)
      }
    }
  }

  func unsubscribeSelectedPodcasts() {
    let selectedCount = selectedPodcastsWithMetadata.count
    let savedPodcastIDs = selectedSavedPodcastIDs
    guard !savedPodcastIDs.isEmpty else {
      Self.log.notice(
        "unsubscribeSelectedPodcasts: no saved podcasts among \(selectedCount) selected"
      )
      return
    }

    Self.log.debug(
      "unsubscribeSelectedPodcasts: unsubscribing \(savedPodcastIDs.count) of \(selectedCount) selected podcasts"
    )

    Task { [weak self] in
      guard let self else { return }

      do {
        try await repo.markUnsubscribed(savedPodcastIDs)
      } catch {
        Self.log.caughtError(
          "unsubscribeSelectedPodcasts: failed to unsubscribe \(savedPodcastIDs.count) podcasts",
          error
        )
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func applyTagToSelectedPodcasts(_ tagID: Tag.ID) {
    let podcastIDs = selectedSavedPodcastIDs
    guard !podcastIDs.isEmpty else {
      Self.log.notice("applyTagToSelectedPodcasts: no saved podcasts selected for tag \(tagID)")
      return
    }

    Self.log.debug(
      "applyTagToSelectedPodcasts: tagging \(podcastIDs.count) podcasts with tag \(tagID)"
    )

    let log = Self.log
    let alert = alert
    Task {
      do {
        try await Container.shared.repo().addTag(tagID, toPodcasts: podcastIDs)
      } catch {
        log.caughtError(
          "applyTagToSelectedPodcasts: failed for \(podcastIDs.count) podcasts, tag \(tagID)",
          error
        )
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func removeTagFromSelectedPodcasts(_ tagID: Tag.ID) {
    let podcastIDs = selectedSavedPodcastIDs
    guard !podcastIDs.isEmpty else {
      Self.log.notice("removeTagFromSelectedPodcasts: no saved podcasts selected for tag \(tagID)")
      return
    }

    Self.log.debug(
      "removeTagFromSelectedPodcasts: untagging \(podcastIDs.count) podcasts from tag \(tagID)"
    )

    let log = Self.log
    let alert = alert
    Task {
      do {
        _ = try await Container.shared.repo().removeTag(tagID, fromPodcasts: podcastIDs)
      } catch {
        log.caughtError(
          "removeTagFromSelectedPodcasts: failed for \(podcastIDs.count) podcasts, tag \(tagID)",
          error
        )
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  // MARK: - Tag Selection Helpers

  // True only when every selected podcast is saved (and so carries
  // observable tag rows).
  var selectionHasTagData: Bool {
    !selectedPodcastsWithMetadata.isEmpty
      && selectedPodcastsWithMetadata.allSatisfy(\.isSaved)
  }

  var selectedPodcastsTagUnion: Set<Tag.ID> {
    selectedPodcastsWithMetadata.reduce(into: Set<Tag.ID>()) { union, metadata in
      union.formUnion(metadata.tagIDs)
    }
  }

  var selectedPodcastsTagIntersection: Set<Tag.ID> {
    var intersection: Set<Tag.ID>?
    for metadata in selectedPodcastsWithMetadata {
      if let current = intersection {
        let next = current.intersection(metadata.tagIDs)
        if next.isEmpty { return [] }
        intersection = next
      } else {
        intersection = metadata.tagIDs
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
