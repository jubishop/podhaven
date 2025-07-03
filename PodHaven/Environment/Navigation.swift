// Copyright Justin Bishop, 2025

import FactoryKit
import GRDB
import SwiftUI

extension Container {
  @MainActor var navigation: Factory<Navigation> {
    Factory(self) { @MainActor in Navigation() }.scope(.cached)
  }
}

@Observable @MainActor class Navigation {
  // MARK: - Navigation Enums

  enum Tab {
    case settings, search, upNext, playlists, podcasts
  }

  enum SettingsView {
    case opml
  }

  enum PodcastsView {
    case all
    case subscribed
    case unsubscribed
  }

  enum PlaylistsView {
    case completed, unfinished
  }

  fileprivate init() {}

  // MARK: - Navigation Paths

  var settingsPath = NavigationPath()
  var searchPath = NavigationPath()
  var upNextPath = NavigationPath()
  var playlistsPath = NavigationPath()
  var podcastsPath = NavigationPath()
  var currentTab: Tab = .settings {
    willSet {
      clearPaths(newValue)
    }
  }

  // MARK: - Navigation Methods

  func showPlaylist(_ view: PlaylistsView) {
    currentTab = .playlists
    playlistsPath.append(view)
  }

  func showPodcast(_ view: PodcastsView, _ podcast: Podcast) {
    currentTab = .podcasts
    podcastsPath.append(view)
    podcastsPath.append(podcast)
  }

  func showEpisode(_ view: PodcastsView, _ podcastEpisode: PodcastEpisode) {
    currentTab = .podcasts
    podcastsPath.append(view)
    podcastsPath.append(podcastEpisode.podcast)
    podcastsPath.append(podcastEpisode.episode)
  }

  // MARK: - Navigation Destination Views

  func podcastDetailView(for podcast: Podcast) -> IdentifiableView<PodcastDetailView, Podcast.ID> {
    IdentifiableView(
      PodcastDetailView(viewModel: PodcastDetailViewModel(podcast: podcast)),
      id: podcast.id
    )
  }

  func episodeDetailView(for episode: Episode, podcast: Podcast)
    -> IdentifiableView<EpisodeDetailView, Episode.ID>
  {
    IdentifiableView(
      EpisodeDetailView(
        viewModel: EpisodeDetailViewModel(
          podcastEpisode: PodcastEpisode(podcast: podcast, episode: episode)
        )
      ),
      id: episode.id
    )
  }

  func podcastResultsDetailView(for searchedPodcast: SearchedPodcast)
    -> IdentifiableView<PodcastResultsDetailView, FeedURL>
  {
    IdentifiableView(
      PodcastResultsDetailView(
        viewModel: PodcastResultsDetailViewModel(searchedPodcast: searchedPodcast)
      ),
      id: searchedPodcast.unsavedPodcast.feedURL
    )
  }

  func episodeResultsDetailView(for searchedPodcastEpisode: SearchedPodcastEpisode)
    -> IdentifiableView<EpisodeResultsDetailView, MediaURL>
  {
    IdentifiableView(
      EpisodeResultsDetailView(
        viewModel: EpisodeResultsDetailViewModel(searchedPodcastEpisode: searchedPodcastEpisode)
      ),
      id: searchedPodcastEpisode.unsavedPodcastEpisode.unsavedEpisode.media
    )
  }

  func standardPlaylistView(for playlistsView: PlaylistsView)
    -> IdentifiableView<StandardPlaylistView, String>
  {
    switch playlistsView {
    case .completed:
      return IdentifiableView(
        StandardPlaylistView(
          viewModel: StandardPlaylistViewModel(
            title: "Completed",
            filter: Episode.completed,
            order: Episode.Columns.completionDate.desc
          )
        ),
        id: "completed"
      )
    case .unfinished:
      return IdentifiableView(
        StandardPlaylistView(
          viewModel: StandardPlaylistViewModel(
            title: "Unfinished",
            filter: Episode.started && Episode.uncompleted
          )
        ),
        id: "unfinished"
      )
    }
  }

  func opmlView(for settingsView: SettingsView) -> IdentifiableView<OPMLView, String> {
    switch settingsView {
    case .opml:
      return IdentifiableView(OPMLView(), id: "opml")
    }
  }

  func standardPodcastsView(for podcastsView: PodcastsView)
    -> IdentifiableView<StandardPodcastsView, String>
  {
    switch podcastsView {
    case .all:
      return IdentifiableView(
        StandardPodcastsView(
          viewModel: StandardPodcastsViewModel(title: "All Podcasts")
        ),
        id: "all"
      )
    case .subscribed:
      return IdentifiableView(
        StandardPodcastsView(
          viewModel: StandardPodcastsViewModel(
            title: "Subscribed",
            filter: Podcast.subscribed
          )
        ),
        id: "subscribed"
      )
    case .unsubscribed:
      return IdentifiableView(
        StandardPodcastsView(
          viewModel: StandardPodcastsViewModel(
            title: "Unsubscribed",
            filter: Podcast.unsubscribed
          )
        ),
        id: "unsubscribed"
      )
    }
  }

  // MARK: - Private Helpers

  private func clearPaths(_ tab: Tab) {
    switch tab {
    case .settings:
      settingsPath = NavigationPath()
    case .search:
      searchPath = NavigationPath()
    case .upNext:
      upNextPath = NavigationPath()
    case .playlists:
      playlistsPath = NavigationPath()
    case .podcasts:
      podcastsPath = NavigationPath()
    }
  }
}
