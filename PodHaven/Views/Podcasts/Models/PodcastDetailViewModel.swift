// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging
import Nuke
import SwiftUI
import Tagged
import UIKit

@Observable @MainActor
class PodcastDetailViewModel:
  ManagingEpisodes,
  SelectableEpisodeList,
  SortableEpisodeList
{
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.imagePipeline) private var imagePipeline
  @ObservationIgnored @DynamicInjected(\.navigation) private var navigation
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory
  @ObservationIgnored @DynamicInjected(\.playManager) private var playManager
  @ObservationIgnored @DynamicInjected(\.queue) private var queue
  @ObservationIgnored @DynamicInjected(\.refreshManager) private var refreshManager
  @ObservationIgnored @DynamicInjected(\.repo) private var repo
  @ObservationIgnored @DynamicInjected(\.userNotificationManager) private
    var userNotificationManager

  private static let log = Log.as(LogSubsystem.PodcastsView.detail)

  // MARK: - Data

  var podcast: DisplayedPodcast
  private var _podcastSeries: PodcastSeries?
  private var podcastSeries: PodcastSeries? {
    get { _podcastSeries }
    set {
      guard let newValue
      else { Assert.fatal("Setting podcastSeries to nil is not allowed") }

      Self.log.debug("Setting podcastSeries to: \(newValue.toString)")

      _podcastSeries = newValue
      podcast = DisplayedPodcast(newValue.podcast)

      // Careful to only update allEntries once
      var allEntries = episodeList.allEntries
      for episode in newValue.episodes {
        allEntries[id: episode.unsaved.id] = DisplayedEpisode(
          PodcastEpisode(podcast: newValue.podcast, episode: episode)
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

  // MARK: - SelectableEpisodeList & SortableEpisodeList

  var episodeList = PowerList<DisplayedEpisode>(debounceDuration: .milliseconds(250))

  enum SortMethod: SortingMethod {
    case newestFirst
    case oldestFirst
    case longest
    case shortest
    case recentlyFinished
    case recentlyQueued

    var appIcon: AppIcon {
      switch self {
      case .newestFirst:
        return .sortByNewest
      case .oldestFirst:
        return .sortByOldest
      case .longest:
        return .sortByLongest
      case .shortest:
        return .sortByShortest
      case .recentlyFinished:
        return .sortByRecentlyFinished
      case .recentlyQueued:
        return .sortByMostRecentlyQueued
      }
    }

    var sortMethod: (@Sendable (DisplayedEpisode, DisplayedEpisode) -> Bool)? {
      switch self {
      case .newestFirst:
        return nil  // This is the default for PodcastSeries
      case .oldestFirst:
        return { $0.pubDate < $1.pubDate }
      case .longest:
        return { $0.duration > $1.duration }
      case .shortest:
        return { $0.duration < $1.duration }
      case .recentlyFinished:
        return { lhs, rhs in
          let lhsDate = lhs.episode.finishDate ?? Date.distantPast
          let rhsDate = rhs.episode.finishDate ?? Date.distantPast
          return lhsDate > rhsDate
        }
      case .recentlyQueued:
        return { lhs, rhs in
          let lhsDate = lhs.episode.queueDate ?? Date.distantPast
          let rhsDate = rhs.episode.queueDate ?? Date.distantPast
          return lhsDate > rhsDate
        }
      }
    }

    var filterMethod: (@Sendable (DisplayedEpisode) -> Bool)? {
      switch self {
      case .recentlyFinished:
        return { $0.finished }
      case .recentlyQueued:
        return { $0.previouslyQueued }
      default: return nil
      }
    }
  }
  let allSortMethods = SortMethod.allCases
  var currentSortMethod: SortMethod = .newestFirst {
    didSet {
      episodeList.filterMethod = currentSortMethod.filterMethod
      episodeList.sortMethod = currentSortMethod.sortMethod
    }
  }

  var selectedPodcastEpisodes: [PodcastEpisode] {
    get async throws {
      let selectedEpisodes = self.selectedEpisodes
      guard !selectedEpisodes.isEmpty else { return [] }

      Self.log.debug("selectedPodcastEpisodes: \(selectedEpisodes.count) episodes selected")

      let podcastEpisodes =
        try await repo.upsertPodcastEpisodes(
          selectedEpisodes.compactMap { $0.getUnsavedPodcastEpisode() }
        )
        + selectedEpisodes.compactMap { $0.getPodcastEpisode() }

      guard let podcastEpisode = podcastEpisodes.first
      else { Assert.fatal("No PodcastEpisodes even tho selectedEpisodes was not empty?") }
      startObservation(podcastEpisode.podcast.id)

      return podcastEpisodes
    }
  }

  // MARK: - Derived State

  var displayingAboutSection: Bool = false
  var showingSettings: Bool = false

  var defaultPlaybackRate: Double? {
    get { podcast.defaultPlaybackRate }
    set {
      guard let podcastID = podcastSeries?.id else {
        Self.log.warning("Cannot update defaultPlaybackRate for unsaved podcast")
        return
      }

      Task { [weak self] in
        guard let self else { return }

        do {
          try await repo.updateDefaultPlaybackRate(podcastID, defaultPlaybackRate: newValue)
        } catch {
          Self.log.error(error)
        }
      }
    }
  }

  var queueAllEpisodes: QueueAllEpisodes {
    get { podcast.queueAllEpisodes }
    set {
      guard let podcastID = podcastSeries?.id else {
        Self.log.warning("Cannot update queueAllEpisodes for unsaved podcast")
        return
      }

      Task { [weak self] in
        guard let self else { return }

        do {
          try await repo.updateQueueAllEpisodes(podcastID, queueAllEpisodes: newValue)
        } catch {
          Self.log.error(error)
        }
      }
    }
  }

  var cacheAllEpisodes: CacheAllEpisodes {
    get { podcast.cacheAllEpisodes }
    set {
      guard let podcastID = podcastSeries?.id else {
        Self.log.warning("Cannot update cacheAllEpisodes for unsaved podcast")
        return
      }

      Task { [weak self] in
        guard let self else { return }

        do {
          try await repo.updateCacheAllEpisodes(podcastID, cacheAllEpisodes: newValue)
        } catch {
          Self.log.error(error)
        }
      }
    }
  }

  var notifyNewEpisodes: Bool {
    get { podcast.notifyNewEpisodes }
    set {
      guard let podcastID = podcastSeries?.id else {
        Self.log.warning("Cannot update notifyNewEpisodes for unsaved podcast")
        return
      }

      Task { [weak self] in
        guard let self else { return }

        do {
          try await repo.updateNotifyNewEpisodes(podcastID, notifyNewEpisodes: newValue)
          if newValue {
            await userNotificationManager.requestAuthorizationIfNeeded()
          }
        } catch {
          Self.log.error(error)
        }
      }
    }
  }

  var loaded: Bool { !episodeList.allEntries.isEmpty }
  var saved: Bool { podcastSeries != nil }

  var mostRecentEpisodeDate: Date {
    episodeList.allEntries.first?.pubDate ?? Date.epoch
  }

  var hasCustomPlayRate: Bool {
    defaultPlaybackRate != nil
  }

  var sharePreview: SharePreview<Image, Image> {
    SharePreview(
      Text(podcast.title),
      image: sharePreviewImage,
      icon: sharePreviewImage
    )
  }
  var shareURL: URL? {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "www.artisanalsoftware.com"
    components.path = "/podhaven/podcast"
    components.queryItems = [
      URLQueryItem(name: "feedURL", value: podcast.feedURL.rawValue.absoluteString)
    ]
    return components.url
  }

  private var sharePreviewImage: Image {
    guard let shareArtwork
    else { return AppIcon.showPodcast.rawImage }

    return Image(uiImage: shareArtwork)
  }
  private var shareArtwork: UIImage?

  // MARK: - Initialization

  init(podcast: DisplayedPodcast) {
    self.podcast = podcast
    episodeList.sortMethod = currentSortMethod.sortMethod

    Task { [weak self] in
      guard let self else { return }

      shareArtwork = try await imagePipeline.image(for: podcast.image)
    }
  }

  convenience init(unsavedPodcastSeries: UnsavedPodcastSeries) {
    self.init(podcast: DisplayedPodcast(unsavedPodcastSeries.unsavedPodcast))
    self.episodeList.allEntries =
      IdentifiedArrayOf(
        uniqueElements: unsavedPodcastSeries.unsavedEpisodes.map {
          DisplayedEpisode(
            UnsavedPodcastEpisode(
              unsavedPodcast: unsavedPodcastSeries.unsavedPodcast,
              unsavedEpisode: $0
            )
          )
        }
      )
  }

  func appear() {
    Task { [weak self] in
      guard let self else { return }

      do {
        try await performAppear()
      } catch {
        Self.log.error(error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.coreMessage(for: error))
      }
    }
  }

  func performAppear() async throws {
    if try await attemptObservation() { return }

    Self.log.debug("\(podcast.toString) does not exist in db")

    guard episodeList.allEntries.isEmpty else {
      Self.log.debug("PodcastDetailViewModel already has entries, no need to fetch again.")
      return
    }

    try await parsePodcastFeed()

    Self.log.debug("Attempting observation again in case FeedURL got updated by parsing the feed")
    try await attemptObservation()
  }

  // MARK: - Public Methods

  func subscribe() {
    Task { [weak self] in
      guard let self else { return }
      do {
        if let podcastSeries = try await getPodcastSeries(for: podcast) {
          try await repo.markSubscribed(podcastSeries.id)
        } else if let unsavedPodcast = podcast.getUnsavedPodcast() {
          let podcastSeries = try await repo.insertSeries(
            UnsavedPodcastSeries(
              unsavedPodcast: unsavedPodcast,
              unsavedEpisodes: episodeList.allEntries.map {
                guard let unsavedEpisode = $0.getUnsavedPodcastEpisode()?.unsavedEpisode
                else { Assert.fatal("Saved PodcastEpisodes but PodcastSeries is nil?") }

                return unsavedEpisode
              }
            )
          )
          try await repo.markSubscribed(podcastSeries.id)
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
    Task { [weak self] in
      guard let self else { return }
      do {
        guard let podcastSeries = try await getPodcastSeries(for: podcast)
        else {
          Self.log.warning("Trying to unsubscribe from a non-saved podcast")
          return
        }

        try await repo.markUnsubscribed(podcastSeries.id)
      } catch {
        Self.log.error(error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.coreMessage(for: error))
      }
    }
  }

  func delete() {
    Task { [weak self] in
      guard let self else { return }

      do {
        guard let podcastSeries = try await getPodcastSeries(for: podcast)
        else {
          Self.log.warning("Trying to delete a non-saved podcast")
          return
        }

        try await repo.deletePodcast(podcastSeries.id)
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
        Self.log.debug("refreshing saved podcast series \(podcastSeries.toString)")
        try await refreshManager.refreshSeries(podcastSeries: podcastSeries)
      } else {
        Self.log.debug("refreshing unsaved podcast series \(podcast.toString)")
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

  @discardableResult
  private func attemptObservation() async throws -> Bool {
    if let observationTask, !observationTask.isCancelled {
      Self.log.debug("Observation already active; not attempting observation")
      return true
    }

    guard let podcastSeries = try await repo.podcastSeries(podcast.feedURL)
    else { return false }

    Self.log.debug("\(podcastSeries.toString) exists in db")

    self.podcastSeries = podcastSeries
    startObservation(podcastSeries.id)

    Task { [weak self] in
      guard let self else { return }
      await refreshSeries()
    }

    return true
  }

  private func startObservation(_ podcastID: Podcast.ID) {
    if let observationTask, !observationTask.isCancelled {
      Self.log.debug("Observation already active; not starting observation")
      return
    }

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
    Self.log.debug("Observing podcast series with ID: \(podcastID)")

    for try await updatedSeries in observatory.podcastSeries(podcastID) {
      try Task.checkCancellation()

      Self.log.debug("Updating observed series: \(String(describing: updatedSeries?.toString))")

      guard let updatedSeries
      else {
        Self.log.debug("Podcast was deleted")
        _podcastSeries = nil
        try await parsePodcastFeed()
        return
      }

      guard updatedSeries != podcastSeries
      else {
        Self.log.debug("New podcastSeries is the same as the current one, skipping update")
        continue
      }

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
  private func getPodcastSeries(for podcast: DisplayedPodcast) async throws
    -> PodcastSeries?
  {
    if let podcastSeries { return podcastSeries }

    guard let podcastSeries = try await repo.podcastSeries(podcast.feedURL)
    else { return nil }

    self.podcastSeries = podcastSeries
    startObservation(podcastSeries.id)
    return podcastSeries
  }

  private func parsePodcastFeed() async throws {
    guard podcastSeries == nil else {
      Self.log.debug("PodcastSeries already exists, no need to fetch again")
      return
    }

    Self.log.debug("Now fetching and parsing feed for \(podcast.toString)")
    let podcastFeed = try await PodcastFeed.parse(podcast.feedURL)
    let unsavedPodcast = try podcastFeed.toUnsavedPodcast()
    podcast = DisplayedPodcast(unsavedPodcast)
    episodeList.allEntries = IdentifiedArray(
      uniqueElements: podcastFeed.toUnsavedEpisodes(merging: podcastSeries?.episodes)
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
