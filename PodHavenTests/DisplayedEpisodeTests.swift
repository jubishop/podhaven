// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of DisplayedEpisode tests", .container)
class DisplayedEpisodeTests {
  @DynamicInjected(\.observatory) private var observatory

  private func fetchListablePodcastEpisode(
    _ episodeID: Episode.ID
  ) async throws -> ListablePodcastEpisode {
    let listables =
      try await observatory.listablePodcastEpisodes(
        filter: Episode.Columns.id == episodeID
      )
      .get()
    return try #require(listables.first)
  }

  // MARK: - Identity

  @Test("DisplayedEpisode.id forwards mediaGUID for unsaved episodes")
  func idForwardsMediaGUIDForUnsaved() throws {
    let unsavedPodcastEpisode = UnsavedPodcastEpisode(
      unsavedPodcast: try Create.unsavedPodcast(title: "Displayed Identity Unsaved"),
      unsavedEpisode: try Create.unsavedEpisode(
        guid: "displayed-identity-unsaved",
        title: "Displayed Identity Unsaved Episode"
      )
    )
    let displayed = DisplayedEpisode(unsavedPodcastEpisode)

    #expect(displayed.id == unsavedPodcastEpisode.mediaGUID)
    #expect(displayed.mediaGUID == unsavedPodcastEpisode.mediaGUID)
  }

  @Test("DisplayedEpisode.id forwards mediaGUID for saved episodes")
  func idForwardsMediaGUIDForSaved() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Displayed Identity Saved"),
        unsavedEpisode: try Create.unsavedEpisode(
          guid: "displayed-identity-saved",
          title: "Displayed Identity Saved Episode"
        )
      )
    )
    let displayed = DisplayedEpisode(podcastEpisode)

    #expect(displayed.id == podcastEpisode.mediaGUID)
    #expect(displayed.mediaGUID == podcastEpisode.mediaGUID)
  }

  // MARK: - Property forwarding

  @Test("DisplayedEpisode forwards displayable fields from UnsavedPodcastEpisode")
  func forwardsFieldsFromUnsaved() throws {
    let unsavedPodcastEpisode = UnsavedPodcastEpisode(
      unsavedPodcast: try Create.unsavedPodcast(title: "Forward Unsaved Podcast Display"),
      unsavedEpisode: try Create.unsavedEpisode(
        guid: "forward-unsaved-display",
        title: "Forward Unsaved Display Episode",
        pubDate: Date(timeIntervalSince1970: 5_000),
        duration: CMTime.seconds(600),
        description: "Some unsaved description",
        currentTime: CMTime.seconds(42),
        queueOrder: 1,
        saveInCache: true
      )
    )
    let displayed = DisplayedEpisode(unsavedPodcastEpisode)

    #expect(displayed.feedURL == unsavedPodcastEpisode.feedURL)
    #expect(displayed.title == unsavedPodcastEpisode.title)
    #expect(displayed.pubDate == unsavedPodcastEpisode.pubDate)
    #expect(displayed.duration == unsavedPodcastEpisode.duration)
    #expect(displayed.currentTime == unsavedPodcastEpisode.currentTime)
    #expect(displayed.queueOrder == unsavedPodcastEpisode.queueOrder)
    #expect(displayed.cacheStatus == unsavedPodcastEpisode.cacheStatus)
    #expect(displayed.finishDate == unsavedPodcastEpisode.finishDate)
    #expect(displayed.image == unsavedPodcastEpisode.image)
    #expect(displayed.podcastImage == unsavedPodcastEpisode.podcastImage)
    #expect(displayed.saveInCache == unsavedPodcastEpisode.saveInCache)
    #expect(displayed.rating == unsavedPodcastEpisode.rating)
    #expect(displayed.podcastTitle == unsavedPodcastEpisode.podcastTitle)
    #expect(displayed.description == unsavedPodcastEpisode.description)
    #expect(displayed.queueDate == unsavedPodcastEpisode.queueDate)
    #expect(displayed.isSaved == false)
  }

  @Test("DisplayedEpisode forwards displayable fields from PodcastEpisode")
  func forwardsFieldsFromSaved() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Forward Saved Display Podcast"),
        unsavedEpisode: try Create.unsavedEpisode(
          guid: "forward-saved-display",
          title: "Forward Saved Display Episode",
          duration: CMTime.seconds(900)
        )
      )
    )
    let displayed = DisplayedEpisode(podcastEpisode)

    #expect(displayed.feedURL == podcastEpisode.feedURL)
    #expect(displayed.title == podcastEpisode.title)
    #expect(displayed.pubDate == podcastEpisode.pubDate)
    #expect(displayed.duration == podcastEpisode.duration)
    #expect(displayed.currentTime == podcastEpisode.currentTime)
    #expect(displayed.queueOrder == podcastEpisode.queueOrder)
    #expect(displayed.cacheStatus == podcastEpisode.cacheStatus)
    #expect(displayed.finishDate == podcastEpisode.finishDate)
    #expect(displayed.image == podcastEpisode.image)
    #expect(displayed.podcastImage == podcastEpisode.podcastImage)
    #expect(displayed.saveInCache == podcastEpisode.saveInCache)
    #expect(displayed.rating == podcastEpisode.rating)
    #expect(displayed.podcastTitle == podcastEpisode.podcastTitle)
    #expect(displayed.description == podcastEpisode.description)
    #expect(displayed.isSaved == true)
  }

  // MARK: - Hashable / Equatable

  @Test("two DisplayedEpisodes with the same UnsavedPodcastEpisode are equal and hash alike")
  func unsavedEqualityAndHash() throws {
    let unsavedPodcastEpisode = UnsavedPodcastEpisode(
      unsavedPodcast: try Create.unsavedPodcast(title: "Displayed Equality Unsaved"),
      unsavedEpisode: try Create.unsavedEpisode(
        guid: "displayed-equality-unsaved",
        title: "Displayed Equality Unsaved Episode"
      )
    )
    let first = DisplayedEpisode(unsavedPodcastEpisode)
    let second = DisplayedEpisode(unsavedPodcastEpisode)

    #expect(first == second)
    #expect(Set([first, second]).count == 1)
  }

  @Test("two DisplayedEpisodes with the same PodcastEpisode are equal and hash alike")
  func savedEqualityAndHash() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Displayed Equality Saved"),
        unsavedEpisode: try Create.unsavedEpisode(
          guid: "displayed-equality-saved",
          title: "Displayed Equality Saved Episode"
        )
      )
    )
    let first = DisplayedEpisode(podcastEpisode)
    let second = DisplayedEpisode(podcastEpisode)

    #expect(first == second)
    #expect(Set([first, second]).count == 1)
  }

  @Test("DisplayedEpisodes wrapping different concrete types are not equal")
  func differentConcreteTypesAreNotEqual() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Displayed Mixed"),
        unsavedEpisode: try Create.unsavedEpisode(
          guid: "displayed-mixed",
          title: "Displayed Mixed Episode"
        )
      )
    )
    let savedDisplayed = DisplayedEpisode(podcastEpisode)
    let unsavedDisplayed = DisplayedEpisode(
      try podcastEpisode.toOriginalUnsavedPodcastEpisode()
    )

    #expect(savedDisplayed != unsavedDisplayed)
  }

  // MARK: - getOrCreatePodcastEpisode

  @Test("getOrCreatePodcastEpisode returns the saved PodcastEpisode for saved input")
  func getOrCreatePodcastEpisodeForSaved() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Displayed GetOrCreate Saved"),
        unsavedEpisode: try Create.unsavedEpisode(
          guid: "displayed-get-or-create-saved",
          title: "Displayed GetOrCreate Saved Episode"
        )
      )
    )
    let displayed = DisplayedEpisode(podcastEpisode)

    let resolved = try await displayed.getOrCreatePodcastEpisode()

    #expect(resolved.id == podcastEpisode.id)
    #expect(resolved.mediaGUID == podcastEpisode.mediaGUID)
  }

  @Test("getOrCreatePodcastEpisode upserts and returns a PodcastEpisode for unsaved input")
  func getOrCreatePodcastEpisodeForUnsaved() async throws {
    let unsavedPodcastEpisode = UnsavedPodcastEpisode(
      unsavedPodcast: try Create.unsavedPodcast(title: "Displayed GetOrCreate Unsaved"),
      unsavedEpisode: try Create.unsavedEpisode(
        guid: "displayed-get-or-create-unsaved",
        title: "Displayed GetOrCreate Unsaved Episode"
      )
    )
    let displayed = DisplayedEpisode(unsavedPodcastEpisode)

    let resolved = try await displayed.getOrCreatePodcastEpisode()

    #expect(resolved.mediaGUID == unsavedPodcastEpisode.mediaGUID)
    #expect(resolved.title == unsavedPodcastEpisode.title)
  }
}
