// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of ListedEpisode tests", .container)
class ListedEpisodeTests {
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.repo) private var repo

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

  @Test("ListedEpisode.id forwards mediaGUID for unsaved episodes")
  func idForwardsMediaGUIDForUnsaved() throws {
    let unsavedPodcastEpisode = UnsavedPodcastEpisode(
      unsavedPodcast: try Create.unsavedPodcast(title: "Identity Unsaved"),
      unsavedEpisode: try Create.unsavedEpisode(
        guid: "identity-unsaved",
        title: "Identity Unsaved Episode"
      )
    )
    let listed = ListedEpisode(unsavedPodcastEpisode)

    #expect(listed.id == unsavedPodcastEpisode.mediaGUID)
    #expect(listed.mediaGUID == unsavedPodcastEpisode.mediaGUID)
  }

  @Test("ListedEpisode.id forwards mediaGUID for saved episodes")
  func idForwardsMediaGUIDForSaved() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Identity Saved"),
        unsavedEpisode: try Create.unsavedEpisode(
          guid: "identity-saved",
          title: "Identity Saved Episode"
        )
      )
    )
    let listable = try await fetchListablePodcastEpisode(podcastEpisode.id)
    let listed = ListedEpisode(listable)

    #expect(listed.id == podcastEpisode.mediaGUID)
    #expect(listed.mediaGUID == podcastEpisode.mediaGUID)
  }

  // MARK: - Property forwarding

  @Test("ListedEpisode forwards listable fields from UnsavedPodcastEpisode")
  func forwardsFieldsFromUnsaved() throws {
    let unsavedPodcastEpisode = UnsavedPodcastEpisode(
      unsavedPodcast: try Create.unsavedPodcast(title: "Forward Unsaved Podcast"),
      unsavedEpisode: try Create.unsavedEpisode(
        guid: "forward-unsaved",
        title: "Forward Unsaved Episode",
        pubDate: Date(timeIntervalSince1970: 5_000),
        duration: CMTime.seconds(600),
        currentTime: CMTime.seconds(42),
        queueOrder: 1,
        saveInCache: true
      )
    )
    let listed = ListedEpisode(unsavedPodcastEpisode)

    #expect(listed.feedURL == unsavedPodcastEpisode.feedURL)
    #expect(listed.title == unsavedPodcastEpisode.title)
    #expect(listed.pubDate == unsavedPodcastEpisode.pubDate)
    #expect(listed.duration == unsavedPodcastEpisode.duration)
    #expect(listed.currentTime == unsavedPodcastEpisode.currentTime)
    #expect(listed.queueOrder == unsavedPodcastEpisode.queueOrder)
    #expect(listed.cacheStatus == unsavedPodcastEpisode.cacheStatus)
    #expect(listed.finishDate == unsavedPodcastEpisode.finishDate)
    #expect(listed.image == unsavedPodcastEpisode.image)
    #expect(listed.podcastImage == unsavedPodcastEpisode.podcastImage)
    #expect(listed.saveInCache == unsavedPodcastEpisode.saveInCache)
    #expect(listed.rating == unsavedPodcastEpisode.rating)
    #expect(listed.isSaved == false)
  }

  @Test("ListedEpisode forwards listable fields from ListablePodcastEpisode")
  func forwardsFieldsFromSaved() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Forward Saved Podcast"),
        unsavedEpisode: try Create.unsavedEpisode(
          guid: "forward-saved",
          title: "Forward Saved Episode",
          duration: CMTime.seconds(900)
        )
      )
    )
    let listable = try await fetchListablePodcastEpisode(podcastEpisode.id)
    let listed = ListedEpisode(listable)

    #expect(listed.feedURL == listable.feedURL)
    #expect(listed.title == listable.title)
    #expect(listed.pubDate == listable.pubDate)
    #expect(listed.duration == listable.duration)
    #expect(listed.currentTime == listable.currentTime)
    #expect(listed.queueOrder == listable.queueOrder)
    #expect(listed.cacheStatus == listable.cacheStatus)
    #expect(listed.finishDate == listable.finishDate)
    #expect(listed.image == listable.image)
    #expect(listed.podcastImage == listable.podcastImage)
    #expect(listed.saveInCache == listable.saveInCache)
    #expect(listed.rating == listable.rating)
  }

  // MARK: - Hashable / Equatable

  @Test("two ListedEpisodes with the same UnsavedPodcastEpisode are equal and hash alike")
  func unsavedEqualityAndHash() throws {
    let unsavedPodcastEpisode = UnsavedPodcastEpisode(
      unsavedPodcast: try Create.unsavedPodcast(title: "Equality Unsaved"),
      unsavedEpisode: try Create.unsavedEpisode(
        guid: "equality-unsaved",
        title: "Equality Unsaved Episode"
      )
    )
    let first = ListedEpisode(unsavedPodcastEpisode)
    let second = ListedEpisode(unsavedPodcastEpisode)

    #expect(first == second)
    #expect(Set([first, second]).count == 1)
  }

  @Test("two ListedEpisodes with the same ListablePodcastEpisode are equal and hash alike")
  func savedEqualityAndHash() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Equality Saved Podcast"),
        unsavedEpisode: try Create.unsavedEpisode(
          guid: "equality-saved",
          title: "Equality Saved Episode"
        )
      )
    )
    let listable = try await fetchListablePodcastEpisode(podcastEpisode.id)
    let first = ListedEpisode(listable)
    let second = ListedEpisode(listable)

    #expect(first == second)
    #expect(Set([first, second]).count == 1)
  }

  @Test("ListedEpisodes wrapping different concrete types are not equal")
  func differentConcreteTypesAreNotEqual() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Mixed Concrete Podcast"),
        unsavedEpisode: try Create.unsavedEpisode(
          guid: "mixed-concrete",
          title: "Mixed Concrete Episode"
        )
      )
    )
    let listable = try await fetchListablePodcastEpisode(podcastEpisode.id)
    let savedListed = ListedEpisode(listable)

    let unsavedListed = ListedEpisode(
      try podcastEpisode.toOriginalUnsavedPodcastEpisode()
    )

    #expect(savedListed != unsavedListed)
  }

  // MARK: - getOrCreatePodcastEpisode

  @Test("getOrCreatePodcastEpisode returns the saved PodcastEpisode for saved input")
  func getOrCreatePodcastEpisodeForSaved() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "GetOrCreate Saved"),
        unsavedEpisode: try Create.unsavedEpisode(
          guid: "get-or-create-saved",
          title: "GetOrCreate Saved Episode"
        )
      )
    )
    let listable = try await fetchListablePodcastEpisode(podcastEpisode.id)
    let listed = ListedEpisode(listable)

    let resolved = try await listed.getOrCreatePodcastEpisode()

    #expect(resolved.id == podcastEpisode.id)
    #expect(resolved.mediaGUID == podcastEpisode.mediaGUID)
  }

  @Test("getOrCreatePodcastEpisode upserts and returns a PodcastEpisode for unsaved input")
  func getOrCreatePodcastEpisodeForUnsaved() async throws {
    let unsavedPodcastEpisode = UnsavedPodcastEpisode(
      unsavedPodcast: try Create.unsavedPodcast(title: "GetOrCreate Unsaved Podcast"),
      unsavedEpisode: try Create.unsavedEpisode(
        guid: "get-or-create-unsaved",
        title: "GetOrCreate Unsaved Episode"
      )
    )
    let listed = ListedEpisode(unsavedPodcastEpisode)

    let resolved = try await listed.getOrCreatePodcastEpisode()

    #expect(resolved.mediaGUID == unsavedPodcastEpisode.mediaGUID)
    #expect(resolved.title == unsavedPodcastEpisode.title)
  }
}
