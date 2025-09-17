// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging
import SwiftUI

@Observable @MainActor
class PodcastDetailViewModel:
  ManagingEpisodes,
  SelectableEpisodeList
{
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.navigation) private var navigation
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory
  @ObservationIgnored @DynamicInjected(\.playManager) private var playManager
  @ObservationIgnored @DynamicInjected(\.queue) private var queue
  @ObservationIgnored @DynamicInjected(\.refreshManager) private var refreshManager
  @ObservationIgnored @DynamicInjected(\.repo) private var repo

  private static let log = Log.as(LogSubsystem.PodcastsView.detail)

  // MARK: - Filtering

  enum EpisodeFilterMethod: String, CaseIterable {
    case all = "All Episodes"
    case unstarted = "Unstarted"
    case unfinished = "Unfinished"
    case unqueued = "Unqueued"

    func filterMethod() -> ((DisplayableEpisode) -> Bool)? {
      switch self {
      case .all:
        return nil
      case .unstarted:
        return { !$0.started }
      case .unfinished:
        return { !$0.completed }
      case .unqueued:
        return { !$0.queued }
      }
    }
  }
  let allFilterMethods = EpisodeFilterMethod.allCases
  var currentFilterMethod: EpisodeFilterMethod = .all {
    didSet { episodeList.filterMethod = currentFilterMethod.filterMethod() }
  }

  // MARK: - Data

  var podcast: any PodcastDisplayable
  private var podcastSeries: PodcastSeries? {
    didSet {
      guard let podcastSeries = podcastSeries
      else { Assert.fatal("Setting podcastSeries to nil is not allowed") }

      Self.log.debug("podcastSeries: \(podcastSeries.toString)")

      self.podcast = podcastSeries.podcast

      // Careful to only update allEntries once
      var allEntries = episodeList.allEntries
      for episode in podcastSeries.episodes {
        allEntries[id: episode.unsaved.id] = DisplayableEpisode(
          PodcastEpisode(podcast: podcastSeries.podcast, episode: episode)
        )
      }
      episodeList.allEntries = allEntries
    }
  }

  // MARK: - ManagingEpisodes

  func getOrCreatePodcastEpisode(_ episode: any EpisodeDisplayable) async throws -> PodcastEpisode {
    let podcastEpisode = try await DisplayableEpisode.getOrCreatePodcastEpisode(episode)
    startObservation(podcastEpisode.podcast.id)
    return podcastEpisode
  }

  // MARK: - SelectableEpisodeList

  var episodeList = SelectableListUseCase<DisplayableEpisode, MediaGUID>(idKeyPath: \.mediaGUID)
  private var _isSelecting = false
  var isSelecting: Bool {
    get { _isSelecting }
    set { withAnimation { _isSelecting = newValue } }
  }
  var selectedPodcastEpisodes: [PodcastEpisode] {
    get async throws {
      guard !selectedEpisodes.isEmpty else { return [] }

      Self.log.debug("selectedPodcastEpisodes: \(selectedEpisodes.count) episodes selected")

      let unsavedPodcastEpisodes = selectedEpisodes.compactMap { $0.getUnsavedPodcastEpisode() }
      let podcastEpisodes = try await repo.upsertPodcastEpisodes(unsavedPodcastEpisodes)

      if observationTask == nil {
        guard
          let podcastID =
            (podcastEpisodes.first?.podcast.id
              ?? selectedEpisodes.first { $0.getPodcastEpisode() != nil }?.getPodcastEpisode()?
              .podcast.id)
        else { Assert.fatal("No podcastID found in \(selectedEpisodes.count) selected episodes") }
        startObservation(podcastID)
      }

      return selectedEpisodes.compactMap { $0.getPodcastEpisode() }
    }
  }

  // MARK: - Initialization

  init(podcast: any PodcastDisplayable) {
    self.podcast = podcast
    episodeList.sortMethod = { $0.pubDate > $1.pubDate }
    episodeList.filterMethod = currentFilterMethod.filterMethod()
  }

  func execute() async {
    defer { subscribable = true }

    do {
      try await performExecute()
    } catch {
      Self.log.error(error)
      if !ErrorKit.isRemarkable(error) { return }
      alert(ErrorKit.coreMessage(for: error))
    }
  }

  func performExecute() async throws {
    let podcastSeries = try await repo.podcastSeries(podcast.feedURL)

    if let podcastSeries {
      Self.log.debug("performExecute: \(podcastSeries.toString) exists in db")

      try await refreshManager.refreshSeries(podcastSeries: podcastSeries)
      self.podcastSeries = podcastSeries
      startObservation(podcastSeries.id)
    } else {
      Self.log.debug("performExecute: \(podcast.toString) does not exist in db")

      try await parsePodcastFeed()
    }
  }

  // MARK: - Derived State

  var displayAboutSection: Bool = false
  var mostRecentEpisodeDate: Date {
    episodeList.allEntries.first?.pubDate ?? Date.epoch
  }
  var subscribable = false

  // MARK: - Public Methods

  func subscribe() {
    guard subscribable
    else { Assert.fatal("Can't subscribe to non-subscribable podcast") }

    Task { [weak self] in
      guard let self else { return }
      do {
        if let podcastSeries = podcastSeries {
          try await repo.markSubscribed(podcastSeries.id)
        } else if var unsavedPodcast = podcast as? UnsavedPodcast {
          Assert.precondition(
            episodeList.allEntries.allSatisfy { $0.getPodcastEpisode() == nil },
            "Some episodes of the podcastSeries are already saved but podcastSeries is nil?"
          )

          unsavedPodcast.subscriptionDate = Date()
          let podcastSeries = try await repo.insertSeries(
            unsavedPodcast,
            unsavedEpisodes: episodeList.allEntries.compactMap {
              $0.getUnsavedPodcastEpisode()?.unsavedEpisode
            }
          )
          self.podcastSeries = podcastSeries
          startObservation(podcastSeries.id)
        } else {
          Assert.fatal("Podcast type is not supported: \(String(describing: podcast))")
        }
      } catch {
        Self.log.error(error)
        if !ErrorKit.isRemarkable(error) { return }
        alert(ErrorKit.coreMessage(for: error))
      }
    }
  }

  func unsubscribe() {
    guard let podcastSeries = podcastSeries
    else { Assert.fatal("Trying to unsubscribe from a non-saved podcast") }

    Task { [weak self] in
      guard let self else { return }
      do {
        try await repo.markUnsubscribed(podcastSeries.id)
      } catch {
        Self.log.error(error)
        if !ErrorKit.isRemarkable(error) { return }
        alert(ErrorKit.coreMessage(for: error))
      }
    }
  }

  func refreshSeries() async {
    do {
      if let podcastSeries = podcastSeries {
        Self.log.debug("refreshSeries: saved podcast series \(podcastSeries.toString)")
        try await refreshManager.refreshSeries(podcastSeries: podcastSeries)
      } else {
        Self.log.debug("refreshSeries: unsaved podcast series \(podcast.toString)")
        try await parsePodcastFeed()
      }
    } catch {
      Self.log.error(error)
      if !ErrorKit.isRemarkable(error) { return }
      alert(ErrorKit.coreMessage(for: error))
    }
  }

  // MARK: - Observation Management

  @ObservationIgnored private var observationTask: Task<Void, Never>?

  private func startObservation(_ podcastID: Podcast.ID) {
    guard observationTask == nil
    else { return }

    observationTask = Task { [weak self] in
      guard let self else { return }
      do {
        try await observePodcastSeries(podcastID)
      } catch {
        Self.log.error(error)
        if !ErrorKit.isRemarkable(error) { return }
        alert(ErrorKit.coreMessage(for: error))
      }
      clearObservationTask()
    }
  }

  private func observePodcastSeries(_ podcastID: Podcast.ID) async throws {
    Self.log.debug("observePodcastSeries: \(podcastID)")

    for try await updatedSeries in observatory.podcastSeries(podcastID) {
      try Task.checkCancellation()
      Self.log.debug(
        "Updating observed series: \(String(describing: updatedSeries?.toString))"
      )
      guard let updatedSeries, updatedSeries != self.podcastSeries else { continue }
      self.podcastSeries = updatedSeries
    }
  }

  func disappear() {
    Self.log.debug("disappear: executing")
    clearObservationTask()
  }

  private func clearObservationTask() {
    observationTask?.cancel()
    observationTask = nil
  }

  // MARK: - Private Helpers

  private func parsePodcastFeed() async throws {
    let podcastFeed = try await PodcastFeed.parse(podcast.feedURL)
    let unsavedPodcast = try podcastFeed.toUnsavedPodcast()
    self.podcast = unsavedPodcast
    episodeList.allEntries = IdentifiedArray(
      uniqueElements: podcastFeed.toEpisodeArray(merging: podcastSeries)
        .map {
          DisplayableEpisode(
            UnsavedPodcastEpisode(
              unsavedPodcast: unsavedPodcast,
              unsavedEpisode: $0
            )
          )
        },
      id: \.mediaGUID
    )
  }
}
