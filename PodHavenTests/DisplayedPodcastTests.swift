// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("of DisplayedPodcast tests", .container)
class DisplayedPodcastTests {
  // MARK: - Identity

  @Test("DisplayedPodcast.id forwards feedURL for unsaved podcasts")
  func idForwardsFeedURLForUnsaved() throws {
    let unsavedPodcast = try Create.unsavedPodcast(title: "Displayed Identity Unsaved")
    let displayed = DisplayedPodcast(unsavedPodcast)

    #expect(displayed.id == unsavedPodcast.feedURL)
    #expect(displayed.feedURL == unsavedPodcast.feedURL)
  }

  @Test("DisplayedPodcast.id forwards feedURL for saved podcasts")
  func idForwardsFeedURLForSaved() async throws {
    let podcast = try await Create.podcast(title: "Displayed Identity Saved")
    let displayed = DisplayedPodcast(podcast)

    #expect(displayed.id == podcast.feedURL)
    #expect(displayed.feedURL == podcast.feedURL)
  }

  // MARK: - Property forwarding

  @Test("DisplayedPodcast forwards displayable fields from UnsavedPodcast")
  func forwardsFieldsFromUnsaved() throws {
    let unsavedPodcast = try Create.unsavedPodcast(
      title: "Forward Unsaved Display",
      description: "Unsaved description",
      link: URL(string: "https://example.com/unsaved")!,
      subscriptionDate: Date(timeIntervalSince1970: 1_000),
      defaultPlaybackRate: 1.25,
      queueAllEpisodes: .onTop,
      cacheAllEpisodes: .cache,
      notifyNewEpisodes: true,
      freshnessCadence: .daily
    )
    let displayed = DisplayedPodcast(unsavedPodcast)

    #expect(displayed.podcastID == unsavedPodcast.podcastID)
    #expect(displayed.feedURL == unsavedPodcast.feedURL)
    #expect(displayed.iTunesID == unsavedPodcast.iTunesID)
    #expect(displayed.image == unsavedPodcast.image)
    #expect(displayed.title == unsavedPodcast.title)
    #expect(displayed.subscriptionDate == unsavedPodcast.subscriptionDate)
    #expect(displayed.subscribed == unsavedPodcast.subscribed)
    #expect(displayed.description == unsavedPodcast.description)
    #expect(displayed.link == unsavedPodcast.link)
    #expect(displayed.settings == unsavedPodcast.settings)
    #expect(displayed.toString == unsavedPodcast.toString)
    #expect(displayed.searchableString == unsavedPodcast.searchableString)
    #expect(displayed.isSaved == false)
  }

  @Test("DisplayedPodcast forwards displayable fields from Podcast")
  func forwardsFieldsFromSaved() async throws {
    let podcast = try await Create.podcast(
      title: "Forward Saved Display",
      description: "Saved description",
      link: URL(string: "https://example.com/saved")!,
      subscriptionDate: Date(timeIntervalSince1970: 2_000),
      defaultPlaybackRate: 1.5,
      queueAllEpisodes: .onBottom,
      cacheAllEpisodes: .save,
      notifyNewEpisodes: true,
      freshnessCadence: .weekly
    )
    let displayed = DisplayedPodcast(podcast)

    #expect(displayed.podcastID == podcast.podcastID)
    #expect(displayed.feedURL == podcast.feedURL)
    #expect(displayed.iTunesID == podcast.iTunesID)
    #expect(displayed.image == podcast.image)
    #expect(displayed.title == podcast.title)
    #expect(displayed.subscriptionDate == podcast.subscriptionDate)
    #expect(displayed.subscribed == podcast.subscribed)
    #expect(displayed.description == podcast.description)
    #expect(displayed.link == podcast.link)
    #expect(displayed.settings == podcast.unsaved.settings)
    #expect(displayed.toString == podcast.toString)
    #expect(displayed.searchableString == podcast.searchableString)
    #expect(displayed.isSaved == true)
  }

  // MARK: - Hashable / Equatable

  @Test("two DisplayedPodcasts with the same UnsavedPodcast are equal and hash alike")
  func unsavedEqualityAndHash() throws {
    let unsavedPodcast = try Create.unsavedPodcast(title: "Displayed Equality Unsaved")
    let first = DisplayedPodcast(unsavedPodcast)
    let second = DisplayedPodcast(unsavedPodcast)

    #expect(first == second)
    #expect(Set([first, second]).count == 1)
  }

  @Test("two DisplayedPodcasts with the same Podcast are equal and hash alike")
  func savedEqualityAndHash() async throws {
    let podcast = try await Create.podcast(title: "Displayed Equality Saved")
    let first = DisplayedPodcast(podcast)
    let second = DisplayedPodcast(podcast)

    #expect(first == second)
    #expect(Set([first, second]).count == 1)
  }

  @Test("DisplayedPodcasts wrapping different concrete types are not equal")
  func differentConcreteTypesAreNotEqual() async throws {
    let podcast = try await Create.podcast(title: "Displayed Mixed")
    let savedDisplayed = DisplayedPodcast(podcast)
    let unsavedDisplayed = DisplayedPodcast(try podcast.toOriginalUnsavedPodcast())

    #expect(savedDisplayed != unsavedDisplayed)
  }

  // MARK: - getOrCreatePodcast

  @Test("getOrCreatePodcast returns the saved Podcast for saved input")
  func getOrCreatePodcastForSaved() async throws {
    let podcast = try await Create.podcast(title: "Displayed GetOrCreate Saved")
    let displayed = DisplayedPodcast(podcast)

    let resolved = try await displayed.getOrCreatePodcast()

    #expect(resolved.id == podcast.id)
    #expect(resolved.feedURL == podcast.feedURL)
  }

  @Test("getOrCreatePodcast returns the existing Podcast for unsaved input")
  func getOrCreatePodcastForUnsaved() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/displayed-get-or-create.rss")!)
    let podcast = try await Create.podcast(
      feedURL: feedURL,
      title: "Displayed GetOrCreate Unsaved"
    )
    let unsavedPodcast = try Create.unsavedPodcast(
      feedURL: feedURL,
      title: "Stale Unsaved Copy"
    )
    let displayed = DisplayedPodcast(unsavedPodcast)

    let resolved = try await displayed.getOrCreatePodcast()

    #expect(resolved.id == podcast.id)
    #expect(resolved.feedURL == podcast.feedURL)
  }
}
