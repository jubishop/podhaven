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

  var currentTab: Tab = .settings {
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

    // Search destinations
    case searchType(SearchType)
    case category(String)
    case searchedPodcast(SearchedPodcast)

    // Episodes destinations
    case episodesViewType(EpisodesViewType)

    // Podcasts destinations
    case podcastsViewType(PodcastsViewType)
    case podcast(Podcast)

    // UpNext destinations
    case upNextEpisode(PodcastEpisode)

    // Universal destinations
    case episode(DisplayableEpisode)
  }

  enum SettingsSection {
    case opml
  }

  enum SearchType {
    case trending
    case podcasts
    case episodes
    case manualEntry
  }

  enum EpisodesViewType {
    case recentEpisodes, completed, unqueued, cached, unfinished, previouslyQueued
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

    // Search destinations
    case .searchType(let searchType):
      switch searchType {
      case .trending:
        TrendingView().id("trendingType")
      case .podcasts:
        PodcastSearchView(viewModel: PodcastSearchViewModel())
          .id("podcastSearchType")
      case .episodes:
        EpisodeSearchView(viewModel: EpisodeSearchViewModel())
          .id("episodeSearchType")
      case .manualEntry:
        ManualFeedEntryView(viewModel: ManualFeedEntryViewModel())
          .id("manualEntryType")
      }
    case .category(let category):
      TrendingCategoryGridView(viewModel: TrendingCategoryGridViewModel(category: category))
        .id("trending_\(category)")
    case .searchedPodcast(let searchedPodcast):
      PodcastDetailView(viewModel: PodcastDetailViewModel(podcast: searchedPodcast.unsavedPodcast))
        .id(searchedPodcast.unsavedPodcast.feedURL)

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
            filter: Episode.uncompleted && Episode.unqueued
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
      case .completed:
        EpisodesListView(
          viewModel: EpisodesListViewModel(
            title: "Completed",
            filter: Episode.completed,
            order: Episode.Columns.completionDate.desc
          )
        )
        .id("completed")
      case .unfinished:
        EpisodesListView(
          viewModel: EpisodesListViewModel(
            title: "Unfinished",
            filter: Episode.started && Episode.uncompleted
          )
        )
        .id("unfinished")
      case .previouslyQueued:
        EpisodesListView(
          viewModel: EpisodesListViewModel(
            title: "Previously Queued",
            filter: Episode.previouslyQueued && Episode.unqueued && Episode.uncompleted,
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
    case .podcast(let podcast):
      PodcastDetailView(viewModel: PodcastDetailViewModel(podcast: podcast))
        .id(podcast.id)

    // UpNext destinations
    case .upNextEpisode(let podcastEpisode):
      EpisodeDetailWrapperView(podcastEpisode: podcastEpisode)
        .id(podcastEpisode.id)

    // Universal destinations
    case .episode(let displayableEpisode):
      EpisodeDetailView(viewModel: EpisodeDetailViewModel(episode: displayableEpisode.episode))
        .id(displayableEpisode.mediaGUID)
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
    podcasts.path.append(.podcast(podcast))
  }

  func showEpisode(_ podcastEpisode: PodcastEpisode) {
    Self.log.debug("Showing PodcastEpisode: \(podcastEpisode.toString)")

    showPodcast(podcastEpisode.podcast)
    podcasts.path.append(.episode(DisplayableEpisode(podcastEpisode)))
  }
}
