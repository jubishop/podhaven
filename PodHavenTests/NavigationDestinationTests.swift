// Copyright Justin Bishop, 2025

import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import SwiftUI
import Testing

@testable import PodHaven

@Suite("of Navigation destination view tests", .container)
@MainActor class NavigationDestinationTests {
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
}
