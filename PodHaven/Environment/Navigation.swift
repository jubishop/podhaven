// Copyright Justin Bishop, 2025

import FactoryKit
import GRDB
import SwiftNavigation
import SwiftUI

extension Container {
  @MainActor var navigation: Factory<Navigation> {
    Factory(self) { @MainActor in Navigation() }.scope(.cached)
  }
}

@Observable @MainActor class Navigation {
  @ObservationIgnored @DynamicInjected(\.sheet) private var sheet

  private static let log = Log.as("Navigation")

  fileprivate init() {}

  // MARK: - Tab Management

  enum Tab {
    case settings, search, upNext, episodes, podcasts
  }

  var currentTab: Tab = .upNext {
    willSet {
      sheet.dismiss()
      managerFor(tab: newValue).clearPath()
    }
  }

  private func managerFor(tab: Tab) -> any ManagingNavigationPaths {
    switch tab {
    case .settings: return settings
    case .search: return search
    case .upNext: return upNext
    case .episodes: return episodes
    case .podcasts: return podcasts
    }
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

    // UpNext destinations
    case upNextEpisode(PodcastEpisode)

    // Universal destinations
    case podcast(DisplayedPodcast)
    case episode(DisplayedEpisode)
  }

  enum SettingsSection {
    case opml
  }

  enum EpisodesViewType {
    case recentEpisodes, finished, unqueued, cached, unfinished, previouslyQueued
  }

  enum PodcastsViewType {
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
        EpisodesListView(
          viewModel: EpisodesListViewModel(
            title: "Recent Episodes",
            filter: AppDB.NoOp
          )
        )
        .id("recentEpisodes")
      case .unqueued:
        EpisodesListView(
          viewModel: EpisodesListViewModel(
            title: "Unqueued",
            filter: Episode.unfinished && Episode.unqueued
          )
        )
        .id("unqueued")
      case .cached:
        EpisodesListView(
          viewModel: EpisodesListViewModel(
            title: "Cached",
            filter: Episode.cached
          )
        )
        .id("cached")
      case .finished:
        EpisodesListView(
          viewModel: EpisodesListViewModel(
            title: "Finished",
            filter: Episode.finished,
            order: Episode.Columns.completionDate.desc
          )
        )
        .id("finished")
      case .unfinished:
        EpisodesListView(
          viewModel: EpisodesListViewModel(
            title: "Unfinished",
            filter: Episode.started && Episode.unfinished
          )
        )
        .id("unfinished")
      case .previouslyQueued:
        EpisodesListView(
          viewModel: EpisodesListViewModel(
            title: "Previously Queued",
            filter: Episode.previouslyQueued && Episode.unqueued && Episode.unfinished,
            order: Episode.Columns.lastQueued.desc
          )
        )
        .id("previouslyQueued")
      }

    // Podcasts destinations
    case .podcastsViewType(let viewType):
      switch viewType {
      case .subscribed:
        SelectablePodcastsGridView(
          viewModel: SelectablePodcastsGridViewModel(
            title: "Subscribed",
            filter: Podcast.subscribed
          )
        )
        .id("subscribed")
      case .unsubscribed:
        SelectablePodcastsGridView(
          viewModel: SelectablePodcastsGridViewModel(
            title: "Unsubscribed",
            filter: Podcast.unsubscribed
          )
        )
        .id("unsubscribed")
      }

    // UpNext destinations
    case .upNextEpisode(let podcastEpisode):
      EpisodeDetailWrapperView(podcastEpisode: podcastEpisode)
        .id(podcastEpisode.id)

    // Universal destinations
    case .episode(let DisplayedEpisode):
      EpisodeDetailView(viewModel: EpisodeDetailViewModel(episode: DisplayedEpisode.episode))
        .id(DisplayedEpisode.mediaGUID)
    case .podcast(let podcast):
      PodcastDetailView(viewModel: PodcastDetailViewModel(podcast: podcast))
        .id(podcast.id)
    }
  }

  // MARK: - Settings

  @MainActor @Observable
  class Settings: ManagingNavigationPaths {
    var path: [Destination] = []
    var resetId = UUID()
  }
  var settings = Settings()

  // MARK: - Settings Navigation

  func showOPMLImport() {
    Self.log.debug("Showing OPML import")

    currentTab = .settings
    settings.path.append(.settingsSection(.opml))
  }

  // MARK: - Search

  @MainActor @Observable
  class Search: ManagingNavigationPaths {
    var path: [Destination] = []
    var resetId = UUID()
  }
  var search = Search()

  // MARK: - UpNext

  @MainActor @Observable
  class UpNext: ManagingNavigationPaths {
    var path: [Destination] = []
    var resetId = UUID()
  }
  var upNext = UpNext()

  // MARK: - Episodes

  @MainActor @Observable
  class Episodes: ManagingNavigationPaths {
    var path: [Destination] = []
    var resetId = UUID()
  }
  var episodes = Episodes()

  // MARK: - Episodes Navigation

  func showEpisodes(_ viewType: EpisodesViewType) {
    currentTab = .episodes
    episodes.path.append(.episodesViewType(viewType))
  }

  // MARK: - Podcasts

  @MainActor @Observable
  class Podcasts: ManagingNavigationPaths {
    var path: [Destination] = []
    var resetId = UUID()
  }
  var podcasts = Podcasts()

  // MARK: - Podcast Navigation

  func showPodcastList(_ viewType: PodcastsViewType) {
    Self.log.debug("Showing podcast list: \(viewType)")

    currentTab = .podcasts
    podcasts.path.append(.podcastsViewType(viewType))
  }

  func showPodcast(_ podcast: Podcast) {
    Self.log.debug("Showing podcast: \(podcast.toString)")

    showPodcastList(podcast.subscribed ? .subscribed : .unsubscribed)
    podcasts.path.append(.podcast(DisplayedPodcast(podcast)))
  }

  func showEpisode(_ podcastEpisode: PodcastEpisode) {
    Self.log.debug("Showing PodcastEpisode: \(podcastEpisode.toString)")

    showPodcast(podcastEpisode.podcast)
    podcasts.path.append(.episode(DisplayedEpisode(podcastEpisode)))
  }
}
