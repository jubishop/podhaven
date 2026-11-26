// Copyright Justin Bishop, 2026

import Foundation

@testable import PodHaven

extension FakeRepo {
  @discardableResult
  func insertTag(_ unsavedTag: UnsavedTag) async throws -> Tag {
    recordCall(methodName: "insertTag", parameters: unsavedTag)
    return try await repo.insertTag(unsavedTag)
  }

  @discardableResult
  func updateTag(_ tagID: Tag.ID, name: String, icon: LucideIcon) async throws -> Bool {
    recordCall(methodName: "updateTag", parameters: (tagID: tagID, name: name, icon: icon))
    return try await repo.updateTag(tagID, name: name, icon: icon)
  }

  @discardableResult
  func deleteTag(_ tagID: Tag.ID) async throws -> Bool {
    recordCall(methodName: "deleteTag", parameters: tagID)
    return try await repo.deleteTag(tagID)
  }

  func addTag(_ tagID: Tag.ID, to podcastID: Podcast.ID) async throws {
    recordCall(methodName: "addTag", parameters: (tagID: tagID, podcastID: podcastID))
    try await repo.addTag(tagID, to: podcastID)
  }

  @discardableResult
  func removeTag(_ tagID: Tag.ID, from podcastID: Podcast.ID) async throws -> Bool {
    recordCall(methodName: "removeTag", parameters: (tagID: tagID, podcastID: podcastID))
    return try await repo.removeTag(tagID, from: podcastID)
  }

  func addTag(_ tagID: Tag.ID, toPodcasts podcastIDs: [Podcast.ID]) async throws {
    recordCall(
      methodName: "addTag",
      parameters: (tagID: tagID, podcastIDs: podcastIDs)
    )
    try await repo.addTag(tagID, toPodcasts: podcastIDs)
  }

  @discardableResult
  func removeTag(_ tagID: Tag.ID, fromPodcasts podcastIDs: [Podcast.ID]) async throws -> Int {
    recordCall(
      methodName: "removeTag",
      parameters: (tagID: tagID, podcastIDs: podcastIDs)
    )
    return try await repo.removeTag(tagID, fromPodcasts: podcastIDs)
  }

  func addTag(_ tagID: Tag.ID, to episodeID: Episode.ID) async throws {
    recordCall(methodName: "addTag", parameters: (tagID: tagID, episodeID: episodeID))
    try await repo.addTag(tagID, to: episodeID)
  }

  @discardableResult
  func removeTag(_ tagID: Tag.ID, from episodeID: Episode.ID) async throws -> Bool {
    recordCall(
      methodName: "removeTag",
      parameters: (tagID: tagID, episodeID: episodeID)
    )
    return try await repo.removeTag(tagID, from: episodeID)
  }

  func addTag(_ tagID: Tag.ID, toEpisodes episodeIDs: [Episode.ID]) async throws {
    recordCall(
      methodName: "addTag",
      parameters: (tagID: tagID, episodeIDs: episodeIDs)
    )
    try await repo.addTag(tagID, toEpisodes: episodeIDs)
  }

  @discardableResult
  func removeTag(_ tagID: Tag.ID, fromEpisodes episodeIDs: [Episode.ID]) async throws -> Int {
    recordCall(
      methodName: "removeTag",
      parameters: (tagID: tagID, episodeIDs: episodeIDs)
    )
    return try await repo.removeTag(tagID, fromEpisodes: episodeIDs)
  }
}
