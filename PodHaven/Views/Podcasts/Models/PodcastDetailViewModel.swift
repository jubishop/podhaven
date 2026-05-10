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
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory
  @ObservationIgnored @DynamicInjected(\.playManager) private var playManager
  @ObservationIgnored @DynamicInjected(\.queue) private var queue
  @ObservationIgnored @DynamicInjected(\.refreshManager) private var refreshManager
  @ObservationIgnored @DynamicInjected(\.repo) private var repo
  @ObservationIgnored @DynamicInjected(\.sharedState) private var sharedState
  @ObservationIgnored @DynamicInjected(\.userNotificationManager) private
    var userNotificationManager

  private static let log = Log.as(LogSubsystem.PodcastsView.detail)
  private static let unavailableMessage = "This podcast is no longer available."

  // MARK: - Data

  var podcast: DisplayedPodcast
  private var _podcastSeries: PodcastSeriesDetail?
  private var podcastSeries: PodcastSeriesDetail? {
    get { _podcastSeries }
    set {
      guard let newValue
      else { Assert.fatal("Setting podcastSeries to nil is not allowed") }

      Self.log.debug("Setting podcastSeries to: \(newValue.toString)")

      _podcastSeries = newValue
      podcast = DisplayedPodcast(newValue.podcast)

      // Skip the allEntries update when the incoming detail carries no
      // episodes — that's the bootstrap case (subscribe() before
      // observation hydrates the inserted episodes). Wholesale-replacing
      // here would briefly blank the feed-parsed unsaved rows on screen.
      // For the populated case, do a wholesale replacement so episodes
      // removed from the DB get pruned (a merge-only update would leave
      // deleted rows on screen).
      guard !newValue.episodes.isEmpty else { return }
      episodeList.allEntries = IdentifiedArray(
        uniqueElements: newValue.episodes.map { listableEpisode in
          ListedEpisode(
            ListablePodcastEpisode(podcast: newValue.podcast, episode: listableEpisode)
          )
        }
      )
    }
  }

  // MARK: - ManagingEpisodes

  func getOrCreatePodcastEpisode(_ episode: ListedEpisode) async throws -> PodcastEpisode {
    let podcastEpisode = try await episode.getOrCreatePodcastEpisode()
    startObservation(podcastEpisode.podcast.id)
    return podcastEpisode
  }

  // MARK: - SelectableEpisodeList & SortableEpisodeList

  var episodeList = PowerList<ListedEpisode>(debounceDuration: .milliseconds(250))

  enum SortMethod: SortingMethod {
    case newestFirst
    case oldestFirst
    case recentlyAdded
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
      case .recentlyAdded:
        return .sortByRecentlyAdded
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

    var sortMethod: (@Sendable (ListedEpisode, ListedEpisode) -> Bool)? {
      switch self {
      case .newestFirst:
        return { $0.pubDate > $1.pubDate }
      case .oldestFirst:
        return { $0.pubDate < $1.pubDate }
      case .recentlyAdded:
        return { lhs, rhs in
          let lhsDate = lhs.creationDate ?? Date.distantFuture
          let rhsDate = rhs.creationDate ?? Date.distantFuture
          return lhsDate > rhsDate
        }
      case .longest:
        return { $0.duration > $1.duration }
      case .shortest:
        return { $0.duration < $1.duration }
      case .recentlyFinished:
        return { lhs, rhs in
          let lhsDate = lhs.finishDate ?? Date.distantPast
          let rhsDate = rhs.finishDate ?? Date.distantPast
          return lhsDate > rhsDate
        }
      case .recentlyQueued:
        return { lhs, rhs in
          let lhsDate = lhs.queueDate ?? Date.distantPast
          let rhsDate = rhs.queueDate ?? Date.distantPast
          return lhsDate > rhsDate
        }
      }
    }

    var filterMethod: (@Sendable (ListedEpisode) -> Bool)? {
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

      let savedEpisodeIDs = selectedEpisodes.compactMap(\.episodeID)
      let unsavedPodcastEpisodes = selectedEpisodes.compactMap(\.unsavedPodcastEpisode)
      let savedByID = Dictionary(
        uniqueKeysWithValues: try await repo.podcastEpisodes(savedEpisodeIDs).map { ($0.id, $0) }
      )
      let upsertedByMediaGUID = Dictionary(
        uniqueKeysWithValues: try await repo.upsertPodcastEpisodes(unsavedPodcastEpisodes)
          .map { ($0.mediaGUID, $0) }
      )
      // Walk `selectedEpisodes` (PowerList visible order) to interleave
      // saved + just-upserted rows in user-visible order.
      let podcastEpisodes: [PodcastEpisode] = selectedEpisodes.compactMap { episode in
        if let episodeID = episode.episodeID { return savedByID[episodeID] }
        return upsertedByMediaGUID[episode.mediaGUID]
      }

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
          Self.log.caughtError(
            "defaultPlaybackRate: failed to update for podcast \(podcastID)",
            error
          )
          guard ErrorKit.isRemarkable(error) else { return }
          alert(ErrorKit.message(for: error))
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
          Self.log.caughtError("queueAllEpisodes: failed to update for podcast \(podcastID)", error)
          guard ErrorKit.isRemarkable(error) else { return }
          alert(ErrorKit.message(for: error))
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
          Self.log.caughtError("cacheAllEpisodes: failed to update for podcast \(podcastID)", error)
          guard ErrorKit.isRemarkable(error) else { return }
          alert(ErrorKit.message(for: error))
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
          Self.log.caughtError(
            "notifyNewEpisodes: failed to update for podcast \(podcastID)",
            error
          )
          guard ErrorKit.isRemarkable(error) else { return }
          alert(ErrorKit.message(for: error))
        }
      }
    }
  }

  var freshnessCadence: FreshnessCadence? {
    get { podcast.freshnessCadence }
    set {
      guard let podcastID = podcastSeries?.id else {
        Self.log.warning("Cannot update freshnessCadence for unsaved podcast")
        return
      }

      Task { [weak self] in
        guard let self else { return }

        do {
          try await repo.updateFreshnessCadence(podcastID, freshnessCadence: newValue)
        } catch {
          Self.log.caughtError(
            "freshnessCadence: failed to update for podcast \(podcastID)",
            error
          )
          guard ErrorKit.isRemarkable(error) else { return }
          alert(ErrorKit.message(for: error))
        }
      }
    }
  }

  var inferredFreshnessCadence: FreshnessCadence {
    FreshnessCadence.infer(from: episodeList.allEntries.map(\.pubDate))
  }

  var loaded: Bool { !episodeList.allEntries.isEmpty }
  var saved: Bool { podcastSeries != nil }

  var tags: IdentifiedArrayOf<Tag> { podcastSeries?.tags ?? [] }
  var allTags: IdentifiedArrayOf<Tag> { sharedState.tags }

  var mostRecentEpisodeDate: Date {
    episodeList.allEntries.first?.pubDate ?? Date.epoch
  }

  var hasCustomPlayRate: Bool {
    defaultPlaybackRate != nil
  }

  // MARK: - Share

  var shareURL: URL? { ShareURL.podcast(feedURL: podcast.feedURL) }
  private var shareArtwork: UIImage?

  var sharePreview: SharePreview<Image, Image> {
    let image = sharePreviewImage
    return SharePreview(Text(podcast.title), image: image, icon: image)
  }

  private var sharePreviewImage: Image {
    guard let shareArtwork else { return AppIcon.showPodcast.rawImage }
    return Image(uiImage: shareArtwork)
  }

  // MARK: - Initialization

  private init(detailSeed: PodcastDetailSeed) {
    let initialPresentation = detailSeed.initialPresentation
    self.podcast = initialPresentation.podcast
    episodeList.sortMethod = currentSortMethod.sortMethod
    episodeList.allEntries = initialPresentation.episodes

    Task { [weak self] in
      guard let self else { return }

      do {
        shareArtwork = try await imagePipeline.image(for: podcast.image)
      } catch {
        Self.log.caughtError(
          "init: failed to load share artwork for \(podcast.image)",
          error,
          level: { _ in .info }
        )
      }
    }
  }

  convenience init(podcast: DisplayedPodcast) {
    self.init(detailSeed: .displayedPodcast(podcast))
  }

  convenience init(listedPodcast: ListedPodcast) {
    self.init(detailSeed: .listedPodcast(listedPodcast))
  }

  convenience init(unsavedPodcastSeries: UnsavedPodcastSeries) {
    self.init(detailSeed: .unsavedPodcastSeries(unsavedPodcastSeries))
  }

  func appear() {
    Task { [weak self] in
      guard let self else { return }

      do {
        try await performAppear()
      } catch {
        Self.log.caughtError("appear: failed for \(podcast.toString)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
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

    try await loadPresentationFromFeed()

    Self.log.debug("Attempting observation again in case FeedURL got updated by parsing the feed")
    try await attemptObservation()
  }

  // MARK: - Public Methods

  func subscribe() {
    Task { [weak self] in
      guard let self else { return }
      do {
        if let podcastID = try await ensureObservedSeries(for: podcast) {
          try await repo.markSubscribed(podcastID)
        } else if let unsavedPodcast = podcast.getUnsavedPodcast() {
          let insertedSeries = try await repo.insertSeries(
            UnsavedPodcastSeries(
              unsavedPodcast: unsavedPodcast,
              unsavedEpisodes: episodeList.allEntries.map {
                guard let unsavedEpisode = $0.unsavedPodcastEpisode?.unsavedEpisode
                else { Assert.fatal("Saved PodcastEpisodes but PodcastSeries is nil?") }

                return unsavedEpisode
              }
            )
          )
          try await repo.markSubscribed(insertedSeries.id)
          self.podcastSeries = PodcastSeriesDetail(podcast: insertedSeries.podcast)
          startObservation(insertedSeries.id)
        } else {
          Assert.fatal("Podcast type is not supported: \(String(describing: podcast))")
        }
      } catch {
        Self.log.caughtError("subscribe: failed for \(podcast.toString)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func unsubscribe() {
    Task { [weak self] in
      guard let self else { return }
      do {
        guard let podcastID = try await ensureObservedSeries(for: podcast)
        else {
          Self.log.warning("Trying to unsubscribe from a non-saved podcast")
          return
        }

        try await repo.markUnsubscribed(podcastID)
      } catch {
        Self.log.caughtError("unsubscribe: failed for \(podcast.toString)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func delete() {
    Task { [weak self] in
      guard let self else { return }

      do {
        guard let podcastID = try await ensureObservedSeries(for: podcast)
        else {
          Self.log.warning("Trying to delete a non-saved podcast")
          return
        }

        Self.log.info("Deleting podcast: \(podcast.toString)")
        try await repo.deletePodcast(podcastID)
      } catch {
        Self.log.caughtError("delete: failed for \(podcast.toString)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func refreshSeries() async {
    do {
      if let podcastID = podcastSeries?.id,
        let operationalSeries = try await repo.podcastSeries(podcastID)
      {
        Self.log.debug("refreshing saved podcast series \(operationalSeries.toString)")
        try await refreshManager.refreshSeries(podcastSeries: operationalSeries)
      } else {
        Self.log.debug("refreshing unsaved podcast series \(podcast.toString)")
        try await loadPresentationFromFeed()
      }
    } catch {
      Self.log.caughtError("refreshSeries: failed for \(podcast.toString)", error)
      guard ErrorKit.isRemarkable(error) else { return }
      alert(ErrorKit.message(for: error))
    }
  }

  // MARK: - Tag Management

  func addTag(_ tagID: Tag.ID) {
    guard let podcastID = podcastSeries?.id else {
      Self.log.warning("Cannot add tag to unsaved podcast")
      return
    }

    Task { [weak self] in
      guard let self else { return }

      do {
        try await repo.addTag(tagID, to: podcastID)
      } catch {
        Self.log.caughtError("addTag: failed to add tag \(tagID) to podcast \(podcastID)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func removeTag(_ tagID: Tag.ID) {
    guard let podcastID = podcastSeries?.id else {
      Self.log.warning("Cannot remove tag from unsaved podcast")
      return
    }

    Task { [weak self] in
      guard let self else { return }

      do {
        try await repo.removeTag(tagID, from: podcastID)
      } catch {
        Self.log.caughtError(
          "removeTag: failed to remove tag \(tagID) from podcast \(podcastID)",
          error
        )
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
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

    guard let savedSeries = try await savedSeries(for: podcast) else { return false }

    Self.log.debug("\(savedSeries.toString) exists in db")

    // Soft migration: backfill iTunesID for pre-existing podcasts
    if savedSeries.podcast.iTunesID == nil, let iTunesID = podcast.iTunesID {
      try await repo.updateITunesID(savedSeries.podcast.id, iTunesID: iTunesID)
    }

    self.podcastSeries = savedSeries
    startObservation(savedSeries.id)

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
        Self.log.caughtError("startObservation: failed for podcast \(podcastID)", error)
      }
      clearObservationTask()
    }
  }

  private func observePodcastSeries(_ podcastID: Podcast.ID) async throws {
    Self.log.debug("Observing podcast series with ID: \(podcastID)")

    for try await updatedSeries in observatory.podcastSeriesDetail(podcastID) {
      try Task.checkCancellation()

      Self.log.debug("Updating observed series: \(String(describing: updatedSeries?.toString))")

      guard let updatedSeries
      else {
        Self.log.debug("Podcast was deleted")
        _podcastSeries = nil
        do {
          try await loadPresentationFromFeed()
        } catch {
          Self.log.caughtError(
            "observePodcastSeries: failed to re-parse feed after podcast \(podcastID) was deleted",
            error
          )
          alert(Self.unavailableMessage)
        }
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
  private func ensureObservedSeries(for podcast: DisplayedPodcast) async throws -> Podcast.ID? {
    if let podcastID = podcastSeries?.id { return podcastID }

    guard let savedSeries = try await savedSeries(for: podcast) else { return nil }

    self.podcastSeries = savedSeries
    startObservation(savedSeries.id)
    return savedSeries.id
  }

  private func loadPresentationFromFeed() async throws {
    guard podcastSeries == nil else {
      Self.log.debug("PodcastSeries already exists, no need to fetch again")
      return
    }

    Self.log.debug("Now fetching and parsing feed for \(podcast.toString)")
    apply(
      try await parsedFeedPresentation(for: podcast)
    )
  }

  private func savedSeries(for currentPodcast: DisplayedPodcast) async throws
    -> PodcastSeriesDetail?
  {
    try await repo.podcastSeriesDetail(
      currentPodcast.feedURL,
      iTunesID: currentPodcast.iTunesID
    )
  }

  private func parsedFeedPresentation(for currentPodcast: DisplayedPodcast) async throws
    -> PodcastDetailPresentation
  {
    let podcastFeed = try await PodcastFeed.parse(currentPodcast.feedURL)
    let unsavedPodcast = try podcastFeed.toUnsavedPodcast(iTunesID: currentPodcast.iTunesID)
    return PodcastDetailPresentation(
      podcast: DisplayedPodcast(unsavedPodcast),
      episodes: IdentifiedArray(
        uniqueElements: podcastFeed.toUnsavedEpisodes()
          .map {
            ListedEpisode(
              UnsavedPodcastEpisode(
                unsavedPodcast: unsavedPodcast,
                unsavedEpisode: $0
              )
            )
          },
        id: \.id
      )
    )
  }

  private func apply(_ presentation: PodcastDetailPresentation) {
    podcast = presentation.podcast
    episodeList.allEntries = presentation.episodes
  }
}
