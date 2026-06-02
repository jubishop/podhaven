// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of episode full-text search", .container)
class EpisodeSearchTests {
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.repo) private var repo

  private func searchIDs(_ text: String) async throws -> Set<Episode.ID> {
    let pattern = try #require(FTS5Pattern(matchingAllPrefixesIn: text))
    let results =
      try await observatory
      .listablePodcastEpisodes(filter: Episode.matchesText(pattern))
      .get()
    return Set(results.map(\.id))
  }

  @Test("matches an episode by a word in its title")
  func matchesEpisodeTitle() async throws {
    let target = try await Create.podcastEpisode(
      try Create.unsavedEpisode(guid: "ep-swift", title: "Swift Concurrency Deep Dive")
    )
    let other = try await Create.podcastEpisode(
      try Create.unsavedEpisode(guid: "ep-garden", title: "Gardening Basics")
    )

    let ids = try await searchIDs("concurrency")

    #expect(ids.contains(target.id))
    #expect(!ids.contains(other.id))
  }

  @Test("matches an episode by a word in its description")
  func matchesEpisodeDescription() async throws {
    let target = try await Create.podcastEpisode(
      try Create.unsavedEpisode(
        guid: "ep-coffee",
        title: "Morning Routine",
        description: "All about espresso brewing at home"
      )
    )

    let ids = try await searchIDs("espresso")

    #expect(ids == [target.id])
  }

  @Test("matches an episode by a word in its podcast's title")
  func matchesPodcastTitle() async throws {
    let target = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Apple Insider Daily"),
        unsavedEpisode: try Create.unsavedEpisode(guid: "ep-news", title: "News Roundup")
      )
    )
    let other = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Android Weekly"),
        unsavedEpisode: try Create.unsavedEpisode(guid: "ep-droid", title: "News Roundup")
      )
    )

    let ids = try await searchIDs("apple")

    #expect(ids.contains(target.id))
    #expect(!ids.contains(other.id))
  }

  @Test("matches on a word prefix as the user types")
  func matchesPrefix() async throws {
    let target = try await Create.podcastEpisode(
      try Create.unsavedEpisode(guid: "ep-prefix", title: "Swift Concurrency Deep Dive")
    )

    let ids = try await searchIDs("concur")

    #expect(ids == [target.id])
  }

  @Test("requires every typed word to match")
  func requiresAllWords() async throws {
    let both = try await Create.podcastEpisode(
      try Create.unsavedEpisode(guid: "ep-both", title: "Swift Concurrency")
    )
    let onlyOne = try await Create.podcastEpisode(
      try Create.unsavedEpisode(guid: "ep-one", title: "Swift Basics")
    )

    let ids = try await searchIDs("swift concur")

    #expect(ids.contains(both.id))
    #expect(!ids.contains(onlyOne.id))
  }

  @Test("returns nothing when no episode matches")
  func excludesNonMatches() async throws {
    _ = try await Create.podcastEpisode(
      try Create.unsavedEpisode(guid: "ep-x", title: "Swift Concurrency")
    )

    let ids = try await searchIDs("nonexistentterm")

    #expect(ids.isEmpty)
  }

  @Test("reflects an episode title change from a feed refresh")
  func reflectsTitleUpdateFromFeed() async throws {
    let feedURL = FeedURL(URL.valid())
    let media = MediaURL(URL.valid())

    func upsert(title: String) async throws -> Episode.ID {
      try await repo.upsertPodcastEpisode(
        UnsavedPodcastEpisode(
          unsavedPodcast: try Create.unsavedPodcast(feedURL: feedURL, title: "Tech Pod"),
          unsavedEpisode: try Create.unsavedEpisode(
            guid: "ep-rename",
            mediaURL: media,
            title: title
          )
        )
      )
      .id
    }

    let episodeID = try await upsert(title: "Original Headline")
    #expect(try await searchIDs("original").contains(episodeID))

    let updatedID = try await upsert(title: "Refreshed Headline")
    #expect(updatedID == episodeID)
    #expect(try await searchIDs("refreshed").contains(episodeID))
    #expect(!(try await searchIDs("original").contains(episodeID)))
  }
}
