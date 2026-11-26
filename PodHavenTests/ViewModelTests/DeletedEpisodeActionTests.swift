// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

// Regression: acting on a card or row whose podcast was just deleted used to
// crash on the missing row instead of reporting the failure.
@Suite("of actions on a just-deleted episode", .container)
@MainActor final class DeletedEpisodeActionTests {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.repo) private var repo

  @Test("playing an on-deck card whose episode was deleted alerts instead of crashing")
  func playingDeletedOnDeckAlerts() async throws {
    let series = try await insertSeries()
    let onDeck = try #require(try await observatory.onDeck(series.episodes[0].id).get())
    _ = try await repo.deletePodcast(series.podcast.id)

    let viewModel = OnDeckViewModel()
    try await expectAlert(logContaining: "playEpisode: failed") {
      viewModel.playEpisode(onDeck)
    }
    withExtendedLifetime(viewModel) {}
  }

  @Test("marking a listed row whose episode was deleted finished alerts instead of crashing")
  func finishingDeletedListedEpisodeAlerts() async throws {
    let series = try await insertSeries()
    let episodeID = series.episodes[0].id
    let listable = try await repo.db.read { db in
      try #require(
        try ListablePodcastEpisode.request(filter: Episode.Columns.id == episodeID).fetchOne(db)
      )
    }
    _ = try await repo.deletePodcast(series.podcast.id)

    let viewModel = UpNextViewModel()
    try await expectAlert(logContaining: "markEpisodeFinished: failed") {
      viewModel.markEpisodeFinished(listable)
    }
    withExtendedLifetime(viewModel) {}
  }

  private func insertSeries() async throws -> PodcastSeries {
    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode()]
      )
    )
  }

  private func expectAlert(
    logContaining message: String,
    _ action: () -> Void
  ) async throws {
    try await LogCapture.withSink { sink in
      action()

      let alert = alert
      try await Wait.until(
        { @MainActor in alert.config != nil },
        { @MainActor in "Expected an alert after acting on a deleted episode" }
      )
      #expect(alert.config?.title == "Error")
      #expect(sink.captured().contains { $0.level == .error && $0.message.contains(message) })
    }
  }
}
