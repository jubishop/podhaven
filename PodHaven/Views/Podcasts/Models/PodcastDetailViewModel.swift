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

  enum EpisodeFilterMethod: CaseIterable {
    case all
    case unstarted
    case unfinished
    case unqueued

    var appIcon: AppIcon {
      switch self {
      case .all:
        return .filterAllEpisodes
      case .unstarted:
        return .filterUnstarted
      case .unfinished:
        return .filterUnfinished
      case .unqueued:
        return .filterUnqueued
      }
    }

    func filterMethod() -> ((DisplayedEpisode) -> Bool)? {
      switch self {
      case .all:
        return nil
      case .unstarted:
        return { !$0.started }
      case .unfinished:
        return { !$0.finished }
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

      podcast = podcastSeries.podcast

      // Careful to only update allEntries once
      var allEntries = episodeList.allEntries
      for episode in podcastSeries.episodes {
        allEntries[id: episode.unsaved.id] = DisplayedEpisode(
          PodcastEpisode(podcast: podcastSeries.podcast, episode: episode)
        )
      }
      episodeList.allEntries = allEntries
    }
  }

  // MARK: - ManagingEpisodes

  func getOrCreatePodcastEpisode(_ episode: DisplayedEpisode) async throws -> PodcastEpisode {
    let podcastEpisode = try await episode.getOrCreatePodcastEpisode()
    startObservation(podcastEpisode.podcast.id)
    return podcastEpisode
  }

  // MARK: - SelectableEpisodeList

  var episodeList = SelectableListUseCase<DisplayedEpisode>()
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
        guard let podcastID = podcastEpisodes.first?.podcast.id
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
      if try await attemptObservation() { return }

      Self.log.debug("\(podcast.toString) does not exist in db")
      try await parsePodcastFeed()

      // Try again in case FeedURL got updated by parsing the feed
      try await attemptObservation()
    } catch {
      Self.log.error(error)
      guard ErrorKit.isRemarkable(error) else { return }
      alert(ErrorKit.coreMessage(for: error))
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
        guard ErrorKit.isRemarkable(error) else { return }
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
        guard ErrorKit.isRemarkable(error) else { return }
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
      guard ErrorKit.isRemarkable(error) else { return }
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
        guard ErrorKit.isRemarkable(error) else { return }
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
      guard let updatedSeries, updatedSeries != podcastSeries else { continue }
      self.podcastSeries = updatedSeries
    }
  }

  // MARK: - Disappear

  func disappear() {
    Self.log.debug("disappear: executing")
    clearObservationTask()
  }

  private func clearObservationTask() {
    observationTask?.cancel()
    observationTask = nil
  }

  // MARK: - Private Helpers

  @discardableResult
  private func attemptObservation() async throws -> Bool {
    guard let podcastSeries = try await repo.podcastSeries(podcast.feedURL)
    else { return false }

    Self.log.debug("\(podcastSeries.toString) exists in db")

    try await refreshManager.refreshSeries(podcastSeries: podcastSeries)
    self.podcastSeries = podcastSeries
    startObservation(podcastSeries.id)
    return true
  }

  private func parsePodcastFeed() async throws {
    let podcastFeed = try await PodcastFeed.parse(podcast.feedURL)
    let unsavedPodcast = try podcastFeed.toUnsavedPodcast()
    podcast = unsavedPodcast
    episodeList.allEntries = IdentifiedArray(
      uniqueElements: podcastFeed.toEpisodeArray(merging: podcastSeries)
        .map {
          DisplayedEpisode(
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
