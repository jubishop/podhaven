// Copyright Justin Bishop, 2025

import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import SwiftUI
import Testing

@testable import PodHaven

@Suite("of Navigation tests", .container)
@MainActor class NavigationTests {
  @DynamicInjected(\.navigation) private var navigation

  @Test("that podcastDetailView has ID matching podcast ID")
  func podcastDetailViewIDMatchesPodcastID() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let podcast = podcastEpisode.podcast

    let identifiableView = navigation.podcastDetailView(for: podcast)

    #expect(identifiableView.viewID == podcast.id, "PodcastDetailView ID should match podcast ID")
  }

  @Test("that episodeDetailView has ID matching episode ID")
  func episodeDetailViewIDMatchesEpisodeID() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let episode = podcastEpisode.episode
    let podcast = podcastEpisode.podcast

    let identifiableView = navigation.episodeDetailView(for: episode, podcast: podcast)

    #expect(identifiableView.viewID == episode.id, "EpisodeDetailView ID should match episode ID")
  }

  @Test("that podcastResultsDetailView has ID matching feed URL")
  func podcastResultsDetailViewIDMatchesFeedURL() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    let searchedPodcast = SearchedPodcast(searchedText: "test", unsavedPodcast: unsavedPodcast)

    let identifiableView = navigation.podcastResultsDetailView(for: searchedPodcast)

    #expect(
      identifiableView.viewID == searchedPodcast.unsavedPodcast.feedURL,
      "PodcastResultsDetailView ID should match feed URL"
    )
  }

  @Test("that episodeResultsDetailView has ID matching media URL")
  func episodeResultsDetailViewIDMatchesMediaURL() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    let unsavedEpisode = try Create.unsavedEpisode()
    let unsavedPodcastEpisode = UnsavedPodcastEpisode(
      unsavedPodcast: unsavedPodcast,
      unsavedEpisode: unsavedEpisode
    )
    let searchedPodcastEpisode = SearchedPodcastEpisode(
      searchedText: "test",
      unsavedPodcastEpisode: unsavedPodcastEpisode
    )

    let identifiableView = navigation.episodeResultsDetailView(for: searchedPodcastEpisode)

    #expect(
      identifiableView.viewID == unsavedEpisode.media,
      "EpisodeResultsDetailView ID should match media URL"
    )
  }

  @Test("that different podcasts create views with different IDs")
  func differentPodcastsHaveDifferentViewIDs() async throws {
    let podcastEpisode1 = try await Create.podcastEpisode()
    let podcastEpisode2 = try await Create.podcastEpisode()

    let identifiableView1 = navigation.podcastDetailView(for: podcastEpisode1.podcast)
    let identifiableView2 = navigation.podcastDetailView(for: podcastEpisode2.podcast)

    #expect(
      identifiableView1.viewID != identifiableView2.viewID,
      "Different podcasts should create views with different IDs"
    )
  }

  @Test("that different episodes create views with different IDs")
  func differentEpisodesHaveDifferentViewIDs() async throws {
    let podcastEpisode1 = try await Create.podcastEpisode()
    let podcastEpisode2 = try await Create.podcastEpisode()

    let identifiableView1 = navigation.episodeDetailView(
      for: podcastEpisode1.episode,
      podcast: podcastEpisode1.podcast
    )
    let identifiableView2 = navigation.episodeDetailView(
      for: podcastEpisode2.episode,
      podcast: podcastEpisode2.podcast
    )

    #expect(
      identifiableView1.viewID != identifiableView2.viewID,
      "Different episodes should create views with different IDs"
    )
  }

  @Test("that different searched podcasts create views with different IDs")
  func differentSearchedPodcastsHaveDifferentViewIDs() async throws {
    let unsavedPodcast1 = try Create.unsavedPodcast(
      feedURL: FeedURL(URL(string: "https://example.com/1")!)
    )
    let unsavedPodcast2 = try Create.unsavedPodcast(
      feedURL: FeedURL(URL(string: "https://example.com/2")!)
    )

    let searchedPodcast1 = SearchedPodcast(searchedText: "test", unsavedPodcast: unsavedPodcast1)
    let searchedPodcast2 = SearchedPodcast(searchedText: "test", unsavedPodcast: unsavedPodcast2)

    let identifiableView1 = navigation.podcastResultsDetailView(for: searchedPodcast1)
    let identifiableView2 = navigation.podcastResultsDetailView(for: searchedPodcast2)

    #expect(
      identifiableView1.viewID != identifiableView2.viewID,
      "Different searched podcasts should create views with different IDs"
    )
  }

  @Test("that standardPlaylistView has ID matching playlist type")
  func standardPlaylistViewIDMatchesPlaylistType() async throws {
    let completedView = navigation.standardPlaylistView(for: .completed)
    let unfinishedView = navigation.standardPlaylistView(for: .unfinished)

    #expect(completedView.viewID == "completed", "Completed playlist view should have 'completed' ID")
    #expect(unfinishedView.viewID == "unfinished", "Unfinished playlist view should have 'unfinished' ID")
  }

  @Test("that opmlView has ID matching settings type")
  func opmlViewIDMatchesSettingsType() async throws {
    let opmlView = navigation.opmlView(for: .opml)

    #expect(opmlView.viewID == "opml", "OPML view should have 'opml' ID")
  }

  @Test("that standardPodcastsView has ID matching podcasts type")
  func standardPodcastsViewIDMatchesPodcastsType() async throws {
    let allView = navigation.standardPodcastsView(for: .all)
    let subscribedView = navigation.standardPodcastsView(for: .subscribed)
    let unsubscribedView = navigation.standardPodcastsView(for: .unsubscribed)

    #expect(allView.viewID == "all", "All podcasts view should have 'all' ID")
    #expect(subscribedView.viewID == "subscribed", "Subscribed podcasts view should have 'subscribed' ID")
    #expect(unsubscribedView.viewID == "unsubscribed", "Unsubscribed podcasts view should have 'unsubscribed' ID")
  }

  @Test("that different playlist types create views with different IDs")
  func differentPlaylistTypesHaveDifferentViewIDs() async throws {
    let completedView = navigation.standardPlaylistView(for: .completed)
    let unfinishedView = navigation.standardPlaylistView(for: .unfinished)

    #expect(
      completedView.viewID != unfinishedView.viewID,
      "Different playlist types should create views with different IDs"
    )
  }

  @Test("that different podcasts view types create views with different IDs")
  func differentPodcastsViewTypesHaveDifferentViewIDs() async throws {
    let allView = navigation.standardPodcastsView(for: .all)
    let subscribedView = navigation.standardPodcastsView(for: .subscribed)
    let unsubscribedView = navigation.standardPodcastsView(for: .unsubscribed)

    #expect(
      allView.viewID != subscribedView.viewID,
      "All and subscribed podcast views should have different IDs"
    )
    #expect(
      subscribedView.viewID != unsubscribedView.viewID,
      "Subscribed and unsubscribed podcast views should have different IDs"
    )
    #expect(
      allView.viewID != unsubscribedView.viewID,
      "All and unsubscribed podcast views should have different IDs"
    )
  }
}
