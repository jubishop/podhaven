// Copyright Justin Bishop, 2026

import FactoryKit
import GRDB
import SwiftUI
import Testing

@testable import PodHaven

@Suite("of detail description preparation", .container)
@MainActor struct DescriptionPreparationTests {
  @Test("episode and podcast preparation cache bounded content with the correct links")
  func preparesAndCaches() async throws {
    let html = String(repeating: "<p>Chapter 12:34 with <b>bold</b> notes.</p>", count: 100)
    let podcast = try Create.unsavedPodcast(description: html)
    let episode = UnsavedPodcastEpisode(
      unsavedPodcast: podcast,
      unsavedEpisode: try Create.unsavedEpisode(description: html)
    )
    let episodeModel = EpisodeDetailViewModel(episode: DisplayedEpisode(episode))
    let podcastModel = PodcastDetailViewModel(podcast: DisplayedPodcast(podcast))
    await episodeModel.prepareDescription(font: .body)
    await podcastModel.prepareDescription(font: .body)
    let episodeBlocks = episodeModel.descriptionBlocks
    let podcastBlocks = podcastModel.descriptionBlocks
    #expect(episodeBlocks.count > 1)
    #expect(podcastBlocks.count > 1)
    #expect(episodeBlocks.flatMap { $0.content.runs }.contains { $0.link != nil })
    #expect(podcastBlocks.flatMap { $0.content.runs }.allSatisfy { $0.link == nil })
    await episodeModel.prepareDescription(font: .body)
    await podcastModel.prepareDescription(font: .body)
    #expect(episodeModel.descriptionBlocks == episodeBlocks)
    #expect(podcastModel.descriptionBlocks == podcastBlocks)
  }

  @Test(
    "a description update supersedes pending episode preparation and empty content clears the cache"
  )
  func episodeUpdatesDuringPreparation() async throws {
    let oldHTML = String(repeating: "<p>Old description with many words.</p>", count: 6000)
    let saved = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisode: try Create.unsavedEpisode(description: oldHTML)
      )
    )
    let model = EpisodeDetailViewModel(episode: DisplayedEpisode(saved))
    model.appear()
    defer { model.disappear() }
    let started = AsyncLatch<Void>()
    let pending = Task {
      started.open()
      await model.prepareDescription(font: .body)
    }
    try await started.wait()
    let appDB = Container.shared.appDB()
    _ = try await appDB.unsafeTestDB.write { db in
      try Episode.filter(Episode.Columns.id == saved.id)
        .updateAll(db, Episode.Columns.description.set(to: "New description at 12:34"))
    }
    try await Wait.until(
      { @MainActor in model.episode.description == "New description at 12:34" },
      { "Expected observed episode description update" }
    )
    await model.prepareDescription(font: .body)
    await pending.value
    #expect(
      model.descriptionBlocks.map { String($0.content.characters) } == ["New description at 12:34"]
    )
    _ = try await appDB.unsafeTestDB.write { db in
      try Episode.filter(Episode.Columns.id == saved.id)
        .updateAll(db, Episode.Columns.description.set(to: ""))
    }
    try await Wait.until(
      { @MainActor in model.episode.description == "" },
      { "Expected observed episode description update" }
    )
    await model.prepareDescription(font: .body)
    #expect(model.descriptionBlocks.isEmpty)
  }

  @Test(
    "a description update supersedes pending podcast preparation and empty content clears the cache"
  )
  func podcastUpdatesDuringPreparation() async throws {
    let oldHTML = String(repeating: "<p>Old description with many words.</p>", count: 6000)
    let saved = try await Create.podcast(description: oldHTML)
    let model = PodcastDetailViewModel(podcast: DisplayedPodcast(saved))
    model.appear()
    defer { model.disappear() }
    let started = AsyncLatch<Void>()
    let pending = Task {
      started.open()
      await model.prepareDescription(font: .body)
    }
    try await started.wait()
    let appDB = Container.shared.appDB()
    _ = try await appDB.unsafeTestDB.write { db in
      try Podcast.filter(Podcast.Columns.id == saved.id)
        .updateAll(db, Podcast.Columns.description.set(to: "New description at 12:34"))
    }
    try await Wait.until(
      { @MainActor in model.podcast.description == "New description at 12:34" },
      { "Expected observed podcast description update" }
    )
    await model.prepareDescription(font: .body)
    await pending.value
    #expect(
      model.descriptionBlocks.map { String($0.content.characters) } == ["New description at 12:34"]
    )
    #expect(model.descriptionBlocks.flatMap { $0.content.runs }.allSatisfy { $0.link == nil })
    _ = try await appDB.unsafeTestDB.write { db in
      try Podcast.filter(Podcast.Columns.id == saved.id)
        .updateAll(db, Podcast.Columns.description.set(to: ""))
    }
    try await Wait.until(
      { @MainActor in model.podcast.description == "" },
      { "Expected observed podcast description update" }
    )
    await model.prepareDescription(font: .body)
    #expect(model.descriptionBlocks.isEmpty)
  }
}
