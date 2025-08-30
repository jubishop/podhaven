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
  var subscribable: Bool = false
  var refreshable: Bool { podcastSeries != nil }

  // MARK: - Data Properties

  var podcast: any PodcastDisplayable
  private var podcastSeries: PodcastSeries?
  private var podcastFeed: PodcastFeed?

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
      // Step 1: Check for existing saved podcast series by feedURL
      if let existingPodcastSeries = try await repo.podcastSeries(podcast.feedURL) {

        // Path A: Saved series exists - use refresh manager
        self.podcastSeries = existingPodcastSeries
        self.podcast = existingPodcastSeries.podcast  // Update to saved version

        // Refresh the series if it's stale
        if existingPodcastSeries.podcast.lastUpdate < 15.minutesAgo {
          await refreshSeries()
        }

        // Observe the saved series using its ID
        for try await updatedSeries in observatory.podcastSeries(existingPodcastSeries.id) {
          guard let updatedSeries = updatedSeries else {
            throw ObservatoryError.recordNotFound(
              type: PodcastSeries.self,
              id: existingPodcastSeries.id.rawValue
            )
          }

          if self.podcastSeries == updatedSeries { continue }
          self.podcastSeries = updatedSeries
          self.podcast = updatedSeries.podcast

          // Update episode list with saved PodcastEpisodes wrapped in DisplayableEpisode
          let episodes = updatedSeries.podcastEpisodes.map { DisplayableEpisode($0) }
          episodeList.allEntries = IdentifiedArray(
            uniqueElements: episodes,
            id: \.mediaGUID
          )
          subscribable = true
        }

      } else {

        // Path B: No saved series - parse feed directly
        let podcastFeed = try await PodcastFeed.parse(podcast.feedURL)
        self.podcastFeed = podcastFeed

        // Observe using the updated feed URL from the parsed feed
        for try await podcastSeries in observatory.podcastSeries(podcastFeed.updatedFeedURL) {

          // Update podcast with fresh feed data
          self.podcast = try podcastFeed.toUnsavedPodcast(merging: podcastSeries?.podcast.unsaved)

          // Create UnsavedPodcastEpisodes from fresh feed data wrapped in DisplayableEpisode
          let freshEpisodes = podcastFeed.toEpisodeArray(merging: podcastSeries)
            .map {
              UnsavedPodcastEpisode(
                unsavedPodcast: self.podcast as! UnsavedPodcast,
                unsavedEpisode: $0
              )
            }

          let episodes = freshEpisodes.map { DisplayableEpisode($0) }
          episodeList.allEntries = IdentifiedArray(uniqueElements: episodes, id: \.mediaGUID)
          subscribable = true
        }
      }

    } catch {
      Self.log.error(error)
      if !ErrorKit.isRemarkable(error) { return }
      alert(ErrorKit.message(for: error))
    }
  }

  // MARK: - ManagingEpisodesModel

  // This will be our main type-checking method
  func getPodcastEpisode(_ episode: DisplayableEpisode) async throws -> PodcastEpisode {
    try await episode.toPodcastEpisode()
  }

  func getEpisodeID(_ episode: DisplayableEpisode) async throws -> Episode.ID {
    let podcastEpisode = try await getPodcastEpisode(episode)
    return podcastEpisode.id
  }

  // MARK: - PodcastDetailViewableModel

  func subscribe() {
    guard subscribable else { return }

    Task { [weak self] in
      guard let self else { return }
      do {
        if let podcastSeries = podcastSeries, let podcastFeed = podcastFeed {
          // Update existing series
          var podcast = podcastSeries.podcast
          podcast.subscriptionDate = Date()
          let updatedPodcastSeries = PodcastSeries(
            podcast: podcast,
            episodes: podcastSeries.episodes
          )
          try await refreshManager.updateSeriesFromFeed(
            podcastSeries: updatedPodcastSeries,
            podcastFeed: podcastFeed
          )
          navigation.showPodcast(updatedPodcastSeries.podcast)
        } else if let unsavedPodcast = podcast as? UnsavedPodcast {
          // Create new series
          var unsavedPodcast = unsavedPodcast
          unsavedPodcast.subscriptionDate = Date()
          unsavedPodcast.lastUpdate = Date()

          let unsavedEpisodes = episodeList.allEntries.elements.compactMap {
            episode -> UnsavedEpisode? in
            if let unsavedPodcastEpisode = episode.episode as? UnsavedPodcastEpisode {
              return unsavedPodcastEpisode.unsavedEpisode
            }
            return nil
          }

          let newPodcastSeries = try await repo.insertSeries(
            unsavedPodcast,
            unsavedEpisodes: unsavedEpisodes
          )
          navigation.showPodcast(newPodcastSeries.podcast)
        }
      } catch {
        Self.log.error(error)
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func unsubscribe() {
    guard let podcastSeries = podcastSeries else {
      Assert.fatal("Trying to unsubscribe from a non-saved podcast")
    }

    Task { [weak self] in
      guard let self else { return }
      try await repo.markUnsubscribed(podcastSeries.id)
      navigation.showPodcast(podcastSeries.podcast)
    }
  }

  func refreshSeries() async {
    guard let podcastSeries = podcastSeries else { return }

    do {
      try await refreshManager.refreshSeries(podcastSeries: podcastSeries)
    } catch {
      Self.log.error(error)
      if !ErrorKit.isRemarkable(error) { return }
      alert(ErrorKit.message(for: error))
    }
  }

  func navigationDestination(for episode: DisplayableEpisode) -> Navigation.Destination {
    .episode(episode)
  }
}
