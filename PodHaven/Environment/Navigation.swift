// Copyright Justin Bishop, 2025

import FactoryKit
import GRDB
import IdentifiedCollections
import Logging
import Sharing
import SwiftNavigation
import SwiftUI
import UIKit

extension Container {
  @MainActor var navigation: Factory<Navigation> {
    Factory(self) { @MainActor in Navigation() }.scope(.cached)
  }
}

@Observable @MainActor class Navigation {
  @ObservationIgnored @DynamicInjected(\.sheet) private var sheet
  @ObservationIgnored @DynamicInjected(\.userSettings) private var userSettings
  @ObservationIgnored @DynamicInjected(\.notifications) private var notifications

  @MainActor
  protocol ManagingPath: AnyObject, Observable {
    var path: [Destination] { get set }
  }

  @MainActor @Observable
  class PathManager: ManagingPath {
    var path: [Destination] = []
  }

  @MainActor @Observable
  class SavedPathManager<TopDestination: Codable & Hashable & Sendable>: ManagingPath {
    @ObservationIgnored @Shared private var topDestination: TopDestination?

    var path: [Destination] = [] {
      didSet {
        guard let first = path.first
        else {
          $topDestination.withLock { $0 = nil }
          return
        }

        guard let extracted = extractTopDestination(first)
        else { Assert.fatal("Top view isn't the expected destination type?") }

        $topDestination.withLock { $0 = extracted }
      }
    }

    private let extractTopDestination: (Destination) -> TopDestination?
    private let makeDestination: (TopDestination) -> Destination

    init(
      storageKey: String,
      extractTopDestination: @escaping (Destination) -> TopDestination?,
      makeDestination: @escaping (TopDestination) -> Destination
    ) {
      self._topDestination = Shared(.appStorage(storageKey))
      self.extractTopDestination = extractTopDestination
      self.makeDestination = makeDestination

      if let topDestination = topDestination {
        self.path = [makeDestination(topDestination)]
      }
    }
  }

  private static let log = Log.as("Navigation")

  // MARK: - Tab Management

  enum Tab {
    case settings, search, upNext, episodes, podcasts
  }

  var currentTab: Tab = .upNext {
    willSet { sheet.dismiss() }
  }

  // MARK: - Unified Navigation Destination

  @CasePathable
  enum Destination: Hashable {
    // Settings destinations
    case settingsSection(SettingsSection)

    // Episodes destinations
    case episodesViewType(EpisodesViewType)

    // Podcasts destinations
    case podcastsViewType(PodcastsViewType)

    // Universal destinations
    case podcast(DisplayedPodcast)
    case episode(DisplayedEpisode)
    case unsavedPodcastSeries(UnsavedPodcastSeries)
  }

  enum SettingsSection {
    case opml
  }

  enum EpisodesViewType: String, CaseIterable, Codable {
    case recentEpisodes, finished, unqueued, cached, saved, unfinished, previouslyQueued
  }

  enum PodcastsViewType: String, CaseIterable, Codable {
    case subscribed
    case unsubscribed
  }

  @ViewBuilder
  func navigationDestination(for destination: Destination) -> some View {
    switch destination {
    // Settings destinations
    case .settingsSection(let section):
      switch section {
      case .opml:
        OPMLView().id("opml")
      }

    // Episodes destinations
    case .episodesViewType(let viewType):
      switch viewType {
      case .recentEpisodes:
        EpisodesListView(viewModel: EpisodesListViewModel(title: "Recent Episodes"))
          .id("recentEpisodes")
      case .unqueued:
        EpisodesListView(
          viewModel: EpisodesListViewModel(title: "Unqueued", filter: Episode.unqueued)
        )
        .id("unqueued")
      case .cached:
        EpisodesListView(
          viewModel: EpisodesListViewModel(title: "Cached", filter: Episode.cached)
        )
        .id("cached")
      case .saved:
        EpisodesListView(
          viewModel: EpisodesListViewModel(title: "Saved", filter: Episode.savedInCache)
        )
        .id("saved")
      case .finished:
        EpisodesListView(
          viewModel: EpisodesListViewModel(title: "Finished", filter: Episode.finished)
        )
        .id("finished")
      case .unfinished:
        EpisodesListView(
          viewModel: EpisodesListViewModel(title: "Unfinished", filter: Episode.unfinished)
        )
        .id("unfinished")
      case .previouslyQueued:
        EpisodesListView(
          viewModel: EpisodesListViewModel(
            title: "Previously Queued",
            filter: Episode.previouslyQueued
          )
        )
        .id("previouslyQueued")
      }

    // Podcasts destinations
    case .podcastsViewType(let viewType):
      switch viewType {
      case .subscribed:
        PodcastsListView(
          viewModel: PodcastsListViewModel(
            title: "Subscribed",
            filter: Podcast.subscribed
          )
        )
        .id("subscribed")
      case .unsubscribed:
        PodcastsListView(
          viewModel: PodcastsListViewModel(
            title: "Unsubscribed",
            filter: Podcast.unsubscribed
          )
        )
        .id("unsubscribed")
      }

    // Universal destinations
    case .episode(let episode):
      EpisodeDetailView(viewModel: EpisodeDetailViewModel(episode: episode))
        .id(episode.id)
    case .podcast(let podcast):
      PodcastDetailView(viewModel: PodcastDetailViewModel(podcast: podcast))
        .id(podcast.id)
    case .unsavedPodcastSeries(let unsavedPodcastSeries):
      PodcastDetailView(
        viewModel: PodcastDetailViewModel(unsavedPodcastSeries: unsavedPodcastSeries)
      )
      .id(unsavedPodcastSeries.id)
    }
  }

  // MARK: - Settings

  var settings = PathManager()

  // MARK: - Settings Navigation

  func showOPMLImport() {
    Self.log.debug("Showing OPML import")

    settings.path.append(.settingsSection(.opml))
    currentTab = .settings
  }

  // MARK: - Search

  var search = PathManager()

  // MARK: - Search Navigation

  func showSearchedPodcast(_ unsavedPodcast: UnsavedPodcast) {
    Self.log.debug("Showing searched podcast: \(unsavedPodcast.toString)")

    search.path = [.podcast(DisplayedPodcast(unsavedPodcast))]
    currentTab = .search
  }

  func showSearchedUnsavedPodcastSeries(_ unsavedPodcastSeries: UnsavedPodcastSeries) {
    Self.log.debug("Showing searched unsaved series: \(unsavedPodcastSeries.toString)")

    search.path = [.unsavedPodcastSeries(unsavedPodcastSeries)]
    currentTab = .search
  }

  func showSearchedEpisode(
    unsavedPodcastSeries: UnsavedPodcastSeries,
    unsavedEpisode: UnsavedEpisode
  ) {
    Self.log.debug("Showing searched episode: \(unsavedEpisode.toString)")

    search.path = [
      .unsavedPodcastSeries(unsavedPodcastSeries),
      .episode(
        DisplayedEpisode(
          UnsavedPodcastEpisode(
            unsavedPodcast: unsavedPodcastSeries.unsavedPodcast,
            unsavedEpisode: unsavedEpisode
          )
        )
      ),
    ]
    currentTab = .search
  }

  // MARK: - UpNext

  var upNext = PathManager()

  // MARK: - Episodes

  var episodes = SavedPathManager<EpisodesViewType>(
    storageKey: "navigationEpisodesTopDestination",
    extractTopDestination: {
      guard case .episodesViewType(let viewType) = $0 else { return nil }
      return viewType
    },
    makeDestination: { .episodesViewType($0) }
  )

  // MARK: - Episodes Navigation

  func showEpisodes(_ viewType: EpisodesViewType) {
    Self.log.debug("Showing episode list: \(viewType)")

    episodes.path = [.episodesViewType(viewType)]
    currentTab = .episodes
  }

  // MARK: - Podcasts

  var podcasts = SavedPathManager<PodcastsViewType>(
    storageKey: "navigationPodcastsTopDestination",
    extractTopDestination: {
      guard case .podcastsViewType(let viewType) = $0 else { return nil }
      return viewType
    },
    makeDestination: { .podcastsViewType($0) }
  )

  // MARK: - Podcast Navigation

  func showPodcastList(_ viewType: PodcastsViewType) {
    Self.log.debug("Showing podcast list: \(viewType)")

    podcasts.path = [.podcastsViewType(viewType)]
    currentTab = .podcasts
  }

  func showPodcast(_ podcast: Podcast) {
    Self.log.debug("Showing podcast: \(podcast.toString)")

    podcasts.path = [
      .podcastsViewType(podcast.subscribed ? .subscribed : .unsubscribed),
      .podcast(DisplayedPodcast(podcast)),
    ]
    currentTab = .podcasts
  }

  func showEpisode(_ podcastEpisode: PodcastEpisode) {
    Self.log.debug("Showing PodcastEpisode: \(podcastEpisode.toString)")

    podcasts.path = [
      .podcastsViewType(podcastEpisode.podcast.subscribed ? .subscribed : .unsubscribed),
      .podcast(DisplayedPodcast(podcastEpisode.podcast)),
      .episode(DisplayedEpisode(podcastEpisode)),
    ]
    currentTab = .podcasts
  }
}
