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
  private static let log = Log.as("Navigation")

  fileprivate init() {}

  // MARK: - Tab Management

  enum Tab {
    case settings, search, upNext, episodes, podcasts
  }

  var currentTab: Tab = .settings {
    willSet { clearPaths() }
  }

  private func clearPaths() {
    settings = Settings()
    search = Search()
    episodes = Episodes()
    podcasts = Podcasts()
  }

  // MARK: - Settings

  @MainActor @Observable
  class Settings {
    var path: [Destination] = []

    enum ViewType {
      case opml
    }

    @CasePathable
    enum Destination: Hashable {
      case viewType(ViewType)
    }

    @ViewBuilder
    func navigationDestination(for destination: Destination) -> some View {
      switch destination {
      case .viewType(let viewType):
        switch viewType {
        case .opml:
          IdentifiableView(OPMLView(), id: "opml")
        }
      }
    }
  }
  var settings = Settings()

  // MARK: - Settings Navigation

  func showOPMLImport() {
    Self.log.debug("Showing OPML import")

    currentTab = .settings
    settings.path.append(.viewType(.opml))
  }

  // MARK: - Search

  @MainActor @Observable
  class Search {
    var path: [Destination] = []

    @CasePathable
    enum Destination: Hashable {
      case searchedPodcast(SearchedPodcast)
      case searchedPodcastEpisode(SearchedPodcastEpisode)
    }

    @ViewBuilder
    func navigationDestination(for destination: Destination) -> some View {
      switch destination {
      case .searchedPodcast(let searchedPodcast):
        IdentifiableView(
          PodcastResultsDetailView(
            viewModel: PodcastResultsDetailViewModel(searchedPodcast: searchedPodcast)
          ),
          id: searchedPodcast.unsavedPodcast.feedURL
        )
      case .searchedPodcastEpisode(let searchedPodcastEpisode):
        IdentifiableView(
          EpisodeResultsDetailView(
            viewModel: EpisodeResultsDetailViewModel(searchedPodcastEpisode: searchedPodcastEpisode)
          ),
          id: searchedPodcastEpisode.unsavedPodcastEpisode.unsavedEpisode.media
        )
      }
    }
  }
  var search = Search()

  // MARK: - Episodes

  @MainActor @Observable
  class Episodes {
    var path: [Destination] = []

    enum ViewType {
      case completed, unfinished, previouslyQueued
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
        case .completed:
          IdentifiableView(
            StandardEpisodesView(
              viewModel: StandardEpisodesViewModel(
                title: "Completed",
                filter: Episode.completed,
                order: Episode.Columns.completionDate.desc
              )
            ),
            id: "completed"
          )
        case .unfinished:
          IdentifiableView(
            StandardEpisodesView(
              viewModel: StandardEpisodesViewModel(
                title: "Unfinished",
                filter: Episode.started && Episode.uncompleted
              )
            ),
            id: "unfinished"
          )
        case .previouslyQueued:
          IdentifiableView(
            StandardEpisodesView(
              viewModel: StandardEpisodesViewModel(
                title: "Previously Queued",
                filter: Episode.previouslyQueued && Episode.unqueued && Episode.uncompleted,
                order: Episode.Columns.lastQueued.desc
              )
            ),
            id: "previouslyQueued"
          )
        }
      case .episode(let podcastEpisode):
        IdentifiableView(
          EpisodeDetailView(viewModel: EpisodeDetailViewModel(podcastEpisode: podcastEpisode)),
          id: podcastEpisode.id
        )
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
  class Podcasts {
    var path: [Destination] = []

    enum ViewType {
      case all
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
        case .all:
          IdentifiableView(
            StandardPodcastsView(
              viewModel: StandardPodcastsViewModel(title: "All Podcasts")
            ),
            id: "all"
          )
        case .subscribed:
          IdentifiableView(
            StandardPodcastsView(
              viewModel: StandardPodcastsViewModel(
                title: "Subscribed",
                filter: Podcast.subscribed
              )
            ),
            id: "subscribed"
          )
        case .unsubscribed:
          IdentifiableView(
            StandardPodcastsView(
              viewModel: StandardPodcastsViewModel(
                title: "Unsubscribed",
                filter: Podcast.unsubscribed
              )
            ),
            id: "unsubscribed"
          )
        }
      case .podcast(let podcast):
        IdentifiableView(
          PodcastDetailView(viewModel: PodcastDetailViewModel(podcast: podcast)),
          id: podcast.id
        )
      case .episode(let podcastEpisode):
        IdentifiableView(
          EpisodeDetailView(viewModel: EpisodeDetailViewModel(podcastEpisode: podcastEpisode)),
          id: podcastEpisode.id
        )
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

  func showEpisode(_ viewType: Podcasts.ViewType, _ podcastEpisode: PodcastEpisode) {
    Self.log.debug("Showing PodcastEpisode: \(podcastEpisode.toString)")

    showPodcast(viewType, podcastEpisode.podcast)
    podcasts.path.append(.episode(podcastEpisode))
  }
}
