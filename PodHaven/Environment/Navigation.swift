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

  // MARK: - Settings

  @MainActor @Observable
  class Settings: ManagingNavigationPaths {
    var path: [Destination] = []
    var resetId = UUID()

    enum Section {
      case opml
    }

    @CasePathable
    enum Destination: Hashable {
      case section(Section)
    }

    @ViewBuilder
    func navigationDestination(for destination: Destination) -> some View {
      switch destination {
      case .section(let section):
        switch section {
        case .opml:
          OPMLView().id("opml")
        }
      }
    }
  }
  var settings = Settings()

  // MARK: - Settings Navigation

  func showOPMLImport() {
    Self.log.debug("Showing OPML import")

    currentTab = .settings
    settings.path.append(.section(.opml))
  }

  // MARK: - Search

  @MainActor @Observable
  class Search: ManagingNavigationPaths {
    var path: [Destination] = []
    var resetId = UUID()

    enum SearchType {
      case trending
      case podcasts
      case episodes
      case manualEntry
    }

    @CasePathable
    enum Destination: Hashable {
      case searchType(SearchType)
      case category(String)
      case searchedPodcast(SearchedPodcast)
      case searchedPodcastEpisode(SearchedPodcastEpisode)
    }

    @ViewBuilder
    func navigationDestination(for destination: Destination) -> some View {
      switch destination {
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
        PodcastDetailView(
          viewModel: PodcastResultsDetailViewModel(searchedPodcast: searchedPodcast)
        )
        .id(searchedPodcast.unsavedPodcast.feedURL)
      case .searchedPodcastEpisode(let searchedPodcastEpisode):
        EpisodeDetailView(
          viewModel: EpisodeDetailViewModel(episode: searchedPodcastEpisode.episode)
        )
        .id(searchedPodcastEpisode.episode.mediaURL)
      }
    }
  }
  var search = Search()

  // MARK: - UpNext

  @MainActor @Observable
  class UpNext: ManagingNavigationPaths {
    var path: [Destination] = []
    var resetId = UUID()

    @CasePathable
    enum Destination: Hashable {
      case episode(PodcastEpisode)
    }

    @ViewBuilder
    func navigationDestination(for destination: Destination) -> some View {
      switch destination {
      case .episode(let podcastEpisode):
        EpisodeDetailWrapperView(podcastEpisode: podcastEpisode)
          .id(podcastEpisode.id)
      }
    }
  }
  var upNext = UpNext()

  // MARK: - Episodes

  @MainActor @Observable
  class Episodes: ManagingNavigationPaths {
    var path: [Destination] = []
    var resetId = UUID()

    enum ViewType {
      case recentEpisodes, completed, unqueued, cached, unfinished, previouslyQueued
    }

    @CasePathable
    enum Destination: Hashable {
      case viewType(ViewType)
      case episode(PodcastEpisode)
    }

    @ViewBuilder
    func navigationDestination(for destination: Destination) -> some View {
      switch destination {
      case .viewType(let viewType):
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
      case .episode(let podcastEpisode):
        EpisodeDetailView(viewModel: EpisodeDetailViewModel(episode: podcastEpisode))
          .id(podcastEpisode.id)
      }
    }
  }
  var episodes = Episodes()

  // MARK: - Episodes Navigation

  func showEpisodes(_ viewType: Episodes.ViewType) {
    currentTab = .episodes
    episodes.path.append(.viewType(viewType))
  }

  // MARK: - Podcasts

  @MainActor @Observable
  class Podcasts: ManagingNavigationPaths {
    var path: [Destination] = []
    var resetId = UUID()

    enum ViewType {
      case subscribed
      case unsubscribed
    }

    @CasePathable
    enum Destination: Hashable {
      case viewType(ViewType)
      case podcast(Podcast)
      case episode(PodcastEpisode)
    }

    @ViewBuilder
    func navigationDestination(for destination: Destination) -> some View {
      switch destination {
      case .viewType(let viewType):
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
      case .episode(let podcastEpisode):
        EpisodeDetailView(viewModel: EpisodeDetailViewModel(episode: podcastEpisode))
          .id(podcastEpisode.id)
      }
    }
  }
  var podcasts = Podcasts()

  // MARK: - Podcast Navigation

  func showPodcastList(_ viewType: Podcasts.ViewType) {
    Self.log.debug("Showing podcast list: \(viewType)")

    currentTab = .podcasts
    podcasts.path.append(.viewType(viewType))
  }

  func showPodcast(_ viewType: Podcasts.ViewType, _ podcast: Podcast) {
    Self.log.debug("Showing podcast: \(podcast.toString)")

    showPodcastList(viewType)
    podcasts.path.append(.podcast(podcast))
  }

  func showPodcast(_ podcast: Podcast) {
    showPodcast(podcast.subscribed ? .subscribed : .unsubscribed, podcast)
  }

  func showEpisode(_ viewType: Podcasts.ViewType, _ podcastEpisode: PodcastEpisode) {
    Self.log.debug("Showing PodcastEpisode: \(podcastEpisode.toString)")

    showPodcast(viewType, podcastEpisode.podcast)
    podcasts.path.append(.episode(podcastEpisode))
  }
}
