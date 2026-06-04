// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import MediaPlayer
import Testing

@testable import PodHaven

@Suite("of Like/Dislike command tests", .container)
@MainActor struct LikeDislikeCommandTests {
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.stateManager) private var stateManager
  @DynamicInjected(\.userSettings) private var userSettings

  private var mpRemoteCommandCenter: FakeMPRemoteCommandCenter {
    Container.shared.mpRemoteCommandCenter() as! FakeMPRemoteCommandCenter
  }

  init() async throws {
    stateManager.start()
    cacheManager.start()
    PlayHelpers.setupCommandHandling()
  }

  private func episodeTagIDs(_ episodeID: Episode.ID) async throws -> [PodHaven.Tag.ID] {
    try await observatory.podcastEpisodeWithTags(episodeID).get()?.tags.map(\.id) ?? []
  }

  @Test("like and dislike commands are enabled with default titles")
  func feedbackCommandsAreEnabled() async throws {
    #expect(mpRemoteCommandCenter.like.isEnabled == true)
    #expect(mpRemoteCommandCenter.dislike.isEnabled == true)
    #expect(mpRemoteCommandCenter.like.localizedTitle == "Like")
    #expect(mpRemoteCommandCenter.dislike.localizedTitle == "Dislike")
  }

  @Test("like applies the default Like rating to the on-deck episode")
  func likeAppliesDefaultRating() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()
    try await PlayHelpers.load(podcastEpisode)
    #expect(try await repo.episode(podcastEpisode.id)?.rating == nil)

    mpRemoteCommandCenter.fireLike()

    try await PlayHelpers.waitForEpisode(podcastEpisode.id, attribute: \.rating, toBe: .liked)
  }

  @Test("like honors a Love configuration")
  func likeAppliesLoveRating() async throws {
    userSettings.$commandCenterLikeAction.new(.love)
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()
    try await PlayHelpers.load(podcastEpisode)

    mpRemoteCommandCenter.fireLike()

    try await PlayHelpers.waitForEpisode(podcastEpisode.id, attribute: \.rating, toBe: .loved)
  }

  @Test("like configured to Save in Cache toggles the on-deck episode in and out of cache")
  func likeTogglesSaveInCache() async throws {
    userSettings.$commandCenterLikeAction.new(.saveInCache)
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()
    try await PlayHelpers.load(podcastEpisode)

    mpRemoteCommandCenter.fireLike()
    try await Wait.until(
      { try await self.repo.episode(podcastEpisode.id)?.saveInCache == true },
      { "Expected on-deck episode to be saved in cache after like" }
    )

    mpRemoteCommandCenter.fireLike()
    try await Wait.until(
      { try await self.repo.episode(podcastEpisode.id)?.saveInCache == false },
      { "Expected on-deck episode to be unsaved after a second like" }
    )
  }

  @Test("like configured to Add Tag tags the on-deck episode")
  func likeAddsConfiguredTag() async throws {
    let tag = try await repo.insertTag(UnsavedTag(name: "Sports"))
    userSettings.$commandCenterLikeAction.new(.addTag(tag.id))
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()
    try await PlayHelpers.load(podcastEpisode)

    mpRemoteCommandCenter.fireLike()

    try await Wait.until(
      { try await self.episodeTagIDs(podcastEpisode.id) == [tag.id] },
      { "Expected on-deck episode to be tagged after like" }
    )
  }

  @Test("dislike applies the default Dislike rating to the on-deck episode")
  func dislikeAppliesDefaultRating() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()
    try await PlayHelpers.load(podcastEpisode)

    mpRemoteCommandCenter.fireDislike()

    try await PlayHelpers.waitForEpisode(podcastEpisode.id, attribute: \.rating, toBe: .disliked)
  }

  @Test("dislike configured to Add Tag tags the on-deck episode")
  func dislikeAddsConfiguredTag() async throws {
    let tag = try await repo.insertTag(UnsavedTag(name: "Skip"))
    userSettings.$commandCenterDislikeAction.new(.addTag(tag.id))
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()
    try await PlayHelpers.load(podcastEpisode)

    mpRemoteCommandCenter.fireDislike()

    try await Wait.until(
      { try await self.episodeTagIDs(podcastEpisode.id) == [tag.id] },
      { "Expected on-deck episode to be tagged after dislike" }
    )
  }

  @Test("like command title tracks the configured action")
  func likeTitleTracksConfiguration() async throws {
    userSettings.$commandCenterLikeAction.new(.love)
    try await Wait.until(
      { @MainActor in self.mpRemoteCommandCenter.like.localizedTitle == "Love" },
      { @MainActor in
        "Expected like title to be Love, got \(self.mpRemoteCommandCenter.like.localizedTitle)"
      }
    )

    let tag = try await repo.insertTag(UnsavedTag(name: "Favorites"))
    userSettings.$commandCenterLikeAction.new(.addTag(tag.id))
    try await Wait.until(
      { @MainActor in self.mpRemoteCommandCenter.like.localizedTitle == "Tag: Favorites" },
      { @MainActor in
        "Expected like title to be Tag: Favorites, got \(self.mpRemoteCommandCenter.like.localizedTitle)"
      }
    )
  }

  @Test("like isActive reflects whether the on-deck episode already has the configured rating")
  func likeIsActiveReflectsRating() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()
    try await PlayHelpers.load(podcastEpisode)
    #expect(mpRemoteCommandCenter.like.isActive == false)

    mpRemoteCommandCenter.fireLike()
    try await Wait.until(
      { @MainActor in self.mpRemoteCommandCenter.like.isActive == true },
      { "Expected like isActive to become true after the episode is liked" }
    )
  }

  @Test("dislike isActive reflects whether the on-deck episode already has the configured rating")
  func dislikeIsActiveReflectsRating() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()
    try await PlayHelpers.load(podcastEpisode)
    #expect(mpRemoteCommandCenter.dislike.isActive == false)

    mpRemoteCommandCenter.fireDislike()
    try await Wait.until(
      { @MainActor in self.mpRemoteCommandCenter.dislike.isActive == true },
      { "Expected dislike isActive to become true after the episode is disliked" }
    )
  }

  @Test("like isActive reflects whether the on-deck episode already has the configured tag")
  func likeIsActiveReflectsTagMembership() async throws {
    let tag = try await repo.insertTag(UnsavedTag(name: "Sports"))
    userSettings.$commandCenterLikeAction.new(.addTag(tag.id))
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()
    try await PlayHelpers.load(podcastEpisode)
    #expect(mpRemoteCommandCenter.like.isActive == false)

    mpRemoteCommandCenter.fireLike()
    try await Wait.until(
      { @MainActor in self.mpRemoteCommandCenter.like.isActive == true },
      { "Expected like isActive to become true after the episode is tagged" }
    )
  }

  @Test("like pressed again clears the rating it applied")
  func likeTogglesRatingOff() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()
    try await PlayHelpers.load(podcastEpisode)

    mpRemoteCommandCenter.fireLike()
    try await PlayHelpers.waitForEpisode(podcastEpisode.id, attribute: \.rating, toBe: .liked)

    mpRemoteCommandCenter.fireLike()
    try await PlayHelpers.waitForEpisode(podcastEpisode.id, attribute: \.rating, toBe: nil)
  }

  @Test("dislike pressed again clears the rating it applied")
  func dislikeTogglesRatingOff() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()
    try await PlayHelpers.load(podcastEpisode)

    mpRemoteCommandCenter.fireDislike()
    try await PlayHelpers.waitForEpisode(podcastEpisode.id, attribute: \.rating, toBe: .disliked)

    mpRemoteCommandCenter.fireDislike()
    try await PlayHelpers.waitForEpisode(podcastEpisode.id, attribute: \.rating, toBe: nil)
  }

  @Test("like configured to Add Tag removes the tag when pressed again")
  func likeTogglesTagOff() async throws {
    let tag = try await repo.insertTag(UnsavedTag(name: "Sports"))
    userSettings.$commandCenterLikeAction.new(.addTag(tag.id))
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()
    try await PlayHelpers.load(podcastEpisode)

    mpRemoteCommandCenter.fireLike()
    try await Wait.until(
      { try await self.episodeTagIDs(podcastEpisode.id) == [tag.id] },
      { "Expected on-deck episode to be tagged after the first like" }
    )

    mpRemoteCommandCenter.fireLike()
    try await Wait.until(
      { try await self.episodeTagIDs(podcastEpisode.id) == [] },
      { "Expected on-deck episode to be untagged after a second like" }
    )
  }

  @Test("like configured to Save in Cache reflects cache state in isActive")
  func likeIsActiveReflectsSaveInCache() async throws {
    userSettings.$commandCenterLikeAction.new(.saveInCache)
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()
    try await PlayHelpers.load(podcastEpisode)
    #expect(mpRemoteCommandCenter.like.isActive == false)

    mpRemoteCommandCenter.fireLike()
    try await Wait.until(
      { @MainActor in self.mpRemoteCommandCenter.like.isActive == true },
      { "Expected like isActive to become true after the episode is saved in cache" }
    )

    mpRemoteCommandCenter.fireLike()
    try await Wait.until(
      { @MainActor in self.mpRemoteCommandCenter.like.isActive == false },
      { "Expected like isActive to become false after the episode is removed from cache" }
    )
  }

  @Test("dislike command title tracks the configured action")
  func dislikeTitleTracksConfiguration() async throws {
    let tag = try await repo.insertTag(UnsavedTag(name: "Skip"))
    userSettings.$commandCenterDislikeAction.new(.addTag(tag.id))
    try await Wait.until(
      { @MainActor in self.mpRemoteCommandCenter.dislike.localizedTitle == "Tag: Skip" },
      { @MainActor in
        "Expected dislike title to be Tag: Skip, got \(self.mpRemoteCommandCenter.dislike.localizedTitle)"
      }
    )
  }

  @Test("feedback titles follow a configured tag's rename")
  func titleFollowsTagRename() async throws {
    let tag = try await repo.insertTag(UnsavedTag(name: "Favorites"))
    userSettings.$commandCenterLikeAction.new(.addTag(tag.id))
    userSettings.$commandCenterDislikeAction.new(.addTag(tag.id))
    try await Wait.until(
      { @MainActor in
        self.mpRemoteCommandCenter.like.localizedTitle == "Tag: Favorites"
          && self.mpRemoteCommandCenter.dislike.localizedTitle == "Tag: Favorites"
      },
      { @MainActor in
        """
        Expected like/dislike titles to be Tag: Favorites, got \
        \(self.mpRemoteCommandCenter.like.localizedTitle) / \
        \(self.mpRemoteCommandCenter.dislike.localizedTitle)
        """
      }
    )

    _ = try await repo.renameTag(tag.id, newName: "Sports")
    try await Wait.until(
      { @MainActor in
        self.mpRemoteCommandCenter.like.localizedTitle == "Tag: Sports"
          && self.mpRemoteCommandCenter.dislike.localizedTitle == "Tag: Sports"
      },
      { @MainActor in
        """
        Expected like/dislike titles to be Tag: Sports after rename, got \
        \(self.mpRemoteCommandCenter.like.localizedTitle) / \
        \(self.mpRemoteCommandCenter.dislike.localizedTitle)
        """
      }
    )
  }
}
