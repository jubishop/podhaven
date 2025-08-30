// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging
import SwiftUI

@Observable @MainActor
class PodcastDetailViewModel:
  ManagingEpisodesModel,
  SelectableEpisodeListModel
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

    func filterMethod<T: EpisodeDisplayable>() -> (T) -> Bool {
      switch self {
      case .all:
        return { _ in true }
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

  // MARK: - State Management

  var displayAboutSection: Bool = false
  var mostRecentEpisodeDate: Date {
    episodeList.allEntries.first?.pubDate ?? Date.epoch
  }
  var subscribable = false
  var refreshable: Bool { podcastSeries != nil }

  // MARK: - Data Properties

  var podcast: any PodcastDisplayable
  private var podcastFeed: PodcastFeed?
  private var podcastSeries: PodcastSeries? {
    didSet {
      guard let podcastSeries = podcastSeries
      else { Assert.fatal("Setting podcastSeries to nil is not allowed") }

      self.podcast = podcastSeries.podcast
      episodeList.allEntries = IdentifiedArray(
        uniqueElements:
          podcastSeries.episodes.map {
            DisplayableEpisode(PodcastEpisode(podcast: podcastSeries.podcast, episode: $0))
          },
        id: \.id
      )
    }
  }

  // MARK: - SelectableEpisodeListModel

  var episodeList = SelectableListUseCase<DisplayableEpisode, MediaGUID>(
    idKeyPath: \.mediaGUID
  )
  private var _isSelecting = false
  var isSelecting: Bool {
    get { _isSelecting }
    set { withAnimation { _isSelecting = newValue } }
  }
  var selectedPodcastEpisodes: [PodcastEpisode] {
    get async throws {
      var podcastEpisodes: [PodcastEpisode] = []
      for episode in selectedEpisodes {
        podcastEpisodes.append(try await episode.toPodcastEpisode())
      }
      return podcastEpisodes
    }
  }

  // MARK: - Initialization

  init(podcast: any PodcastDisplayable) {
    self.podcast = podcast
    episodeList.sortMethod = { $0.pubDate > $1.pubDate }
    episodeList.filterMethod = currentFilterMethod.filterMethod()
  }

  func execute() async {
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
      Self.log.debug("Podcast series: \(podcastSeries.toString) exists in db")

      self.podcastSeries = podcastSeries
      startObservation()
    } else {
      Self.log.debug("Podcast series: \(podcast.toString) does not exist in db")

      let podcastFeed = try await PodcastFeed.parse(podcast.feedURL)
      self.podcastFeed = podcastFeed

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

    subscribable = true
  }

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
          unsavedPodcast.subscriptionDate = Date()

          self.podcastSeries = try await repo.insertSeries(
            unsavedPodcast,
            unsavedEpisodes: episodeList.allEntries.map {
              $0.toUnsavedPodcastEpisode().unsavedEpisode
            }
          )
          startObservation()
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
    guard let podcastSeries = podcastSeries
    else { Assert.fatal("Trying to refresh a non-saved podcast") }

    guard podcastSeries.podcast.lastUpdate > 1.minutesAgo
    else { return }

    Self.log.debug("Refreshing podcast series \(podcastSeries.toString)")
    do {
      try await refreshManager.refreshSeries(podcastSeries: podcastSeries)
    } catch {
      Self.log.error(error)
      if !ErrorKit.isRemarkable(error) { return }
      alert(ErrorKit.message(for: error))
    }
  }

  // MARK: - Observation Management

  @ObservationIgnored private var observationTask: Task<Void, Never>?

  private func startObservation() {
    Assert.precondition(
      observationTask == nil,
      "Already observing"
    )

    observationTask = Task { [weak self] in
      guard let self else { return }
      await observePodcastSeries()
    }
  }

  private func observePodcastSeries() async {
    guard let podcastSeries = self.podcastSeries
    else { Assert.fatal("Observing a non-saved podcast") }

    do {
      Self.log.debug("Starting observation by ID: \(podcastSeries.id)")
      for try await updatedSeries in observatory.podcastSeries(podcastSeries.id) {
        guard !Task.isCancelled else { break }
        guard let updatedSeries, updatedSeries != self.podcastSeries else { continue }
        self.podcastSeries = updatedSeries
      }
    } catch {
      Self.log.error(error)
      if !ErrorKit.isRemarkable(error) { return }
      alert(ErrorKit.coreMessage(for: error))
    }
  }

  deinit {
    observationTask?.cancel()
  }
}
