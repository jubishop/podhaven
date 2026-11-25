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

  // Must Implement: Saves any unsaved selected podcasts and returns their IDs
  func saveSelectedPodcasts() async -> [Podcast.ID]

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

    let savedTitles = selectedPodcastsWithMetadata.filter(\.isSaved).map(\.title)
    alert.confirmPodcastDeletion(titles: savedTitles) { [weak self] in
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
        }
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

      let podcastIDs = await saveSelectedPodcasts()
      let subscribedCount: Int
      do {
        subscribedCount = try await repo.markSubscribed(podcastIDs, level: .trace)
      } catch {
        Self.log.caughtError(
          "subscribeSelectedPodcasts: failed to subscribe \(podcastIDs.count) podcasts",
          error
        )
        return
      }

      Self.log.debug(
        "subscribeSelectedPodcasts: subscribed \(subscribedCount) of \(selectedCount) selected podcasts"
      )
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
    guard !podcastIDs.isEmpty else {
      Self.log.notice("removeTagFromSelectedPodcasts: no saved podcasts selected for tag \(tagID)")
      return
    }

    Self.log.debug(
      "removeTagFromSelectedPodcasts: untagging \(podcastIDs.count) podcasts from tag \(tagID)"
    )

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

extension SelectablePodcastList where PodcastType == ListablePodcast {
  func saveSelectedPodcasts() async -> [Podcast.ID] {
    selectedSavedPodcastIDs
  }
}
