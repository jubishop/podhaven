// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

enum EpisodeNonSavedSeed: Sendable, CaseIterable, CustomTestStringConvertible {
  case listedSaved
  case unsavedDisplayed
  case listedUnsaved

  var testDescription: String {
    switch self {
    case .listedSaved: return "saved listed episode"
    case .unsavedDisplayed: return "unsaved displayed episode"
    case .listedUnsaved: return "unsaved listed episode"
    }
  }

  @MainActor
  func makeViewModel(
    repo: any Databasing,
    observatory: any Observing
  ) async throws -> EpisodeDetailViewModel {
    switch self {
    case .listedSaved:
      let podcastEpisode = try await Create.podcastEpisode(
        UnsavedPodcastEpisode(
          unsavedPodcast: try Create.unsavedPodcast(title: "Listed Episode Init"),
          unsavedEpisode: try Create.unsavedEpisode(
            guid: "listed-episode-init",
            title: "Listed Episode Init"
          )
        )
      )
      let listableEpisodes =
        try await observatory.listablePodcastEpisodes(
          filter: Episode.Columns.id == podcastEpisode.id
        )
        .get()
      let listedEpisode = try #require(listableEpisodes.first)
      return EpisodeDetailViewModel(listedEpisode: ListedEpisode(listedEpisode))
    case .unsavedDisplayed:
      return EpisodeDetailViewModel(
        episode: DisplayedEpisode(
          UnsavedPodcastEpisode(
            unsavedPodcast: try Create.unsavedPodcast(title: "Unsaved Episode Init"),
            unsavedEpisode: try Create.unsavedEpisode(
              guid: "unsaved-episode-init",
              title: "Unsaved Episode Init"
            )
          )
        )
      )
    case .listedUnsaved:
      let unsavedPodcastEpisode = UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Listed Unsaved Init"),
        unsavedEpisode: try Create.unsavedEpisode(
          guid: "listed-unsaved-init",
          title: "Listed Unsaved Init"
        )
      )
      return EpisodeDetailViewModel(listedEpisode: ListedEpisode(unsavedPodcastEpisode))
    }
  }
}

@Suite("of EpisodeDetailViewModel lifecycle tests", .container)
@MainActor final class EpisodeDetailLifecycleTests {
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.repo) private var repo

  private var fakeObservatory: FakeObservatory {
    observatory as! FakeObservatory
  }

  private func yieldForSpuriousAsyncWork() async throws {
    let yields = ThreadSafe(0)
    try await Wait.until(
      { @MainActor in
        await Task.yield()
        yields { $0 += 1 }
        return yields() >= 20
      },
      { "Expected to finish yielding before asserting init had no side effects." }
    )
  }

  @Test("init for a saved displayed episode does not start an observation task")
  func initForSavedDisplayedEpisodeDoesNotStartObservation() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Saved Episode Init"),
        unsavedEpisode: try Create.unsavedEpisode(title: "Episode Init")
      )
    )

    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(podcastEpisode))

    fakeObservatory.clearAllCalls()
    try await yieldForSpuriousAsyncWork()

    #expect(viewModel.observationTask == nil)
    #expect(viewModel.appearTask == nil)
    #expect(viewModel.auxiliaryTasks.isEmpty)
    _ = try fakeObservatory.expectCalls(methodName: "podcastEpisodeWithTags", count: 0)
  }

  @Test(
    "init for a non-saved seed does not start an observation task",
    arguments: EpisodeNonSavedSeed.allCases
  )
  func initForNonSavedSeedDoesNotStartObservation(seed: EpisodeNonSavedSeed) async throws {
    let viewModel = try await seed.makeViewModel(repo: repo, observatory: observatory)

    fakeObservatory.clearAllCalls()
    try await yieldForSpuriousAsyncWork()

    #expect(viewModel.observationTask == nil)
    #expect(viewModel.appearTask == nil)
    #expect(viewModel.auxiliaryTasks.isEmpty)
    _ = try fakeObservatory.expectCalls(methodName: "podcastEpisodeWithTags", count: 0)
  }

  @Test("appear starts observation for a saved displayed episode")
  func appearStartsObservationForSavedDisplayedEpisode() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Appear Episode"),
        unsavedEpisode: try Create.unsavedEpisode(
          guid: "appear-episode",
          title: "Appear Episode"
        )
      )
    )
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(podcastEpisode))

    fakeObservatory.clearAllCalls()

    #expect(viewModel.observationTask == nil)

    viewModel.appear()

    try await Wait.until(
      { @MainActor in viewModel.observationTask != nil },
      { @MainActor in
        "Expected appear to start observation; task=\(String(describing: viewModel.observationTask))"
      }
    )

    _ = try fakeObservatory.expectCalls(methodName: "podcastEpisodeWithTags", count: 1)

    viewModel.appear()

    try await Wait.until(
      { @MainActor in viewModel.appearTask == nil },
      { @MainActor in
        "Expected second appear to finish; appearTask=\(String(describing: viewModel.appearTask))"
      }
    )

    _ = try fakeObservatory.expectCalls(methodName: "podcastEpisodeWithTags", count: 1)
    #expect(viewModel.observationTask != nil)
  }

  @Test("playNow after disappear does not restart observation")
  func playNowAfterDisappearDoesNotRestartObservation() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Disappear Play"),
        unsavedEpisode: try Create.unsavedEpisode(guid: "disappear-play", title: "Disappear Play")
      )
    )
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(podcastEpisode))

    viewModel.appear()

    try await Wait.until(
      { @MainActor in viewModel.observationTask != nil },
      { @MainActor in
        "Expected observation before disappear; task=\(String(describing: viewModel.observationTask))"
      }
    )

    fakeObservatory.clearAllCalls()
    viewModel.disappear()

    #expect(viewModel.isOnScreen == false)
    viewModel.playNow()

    try await yieldForSpuriousAsyncWork()

    #expect(viewModel.observationTask == nil)
    _ = try fakeObservatory.expectCalls(methodName: "podcastEpisodeWithTags", count: 0)
  }

  @Test("disappear cancels observation after appear")
  func disappearCancelsObservationAfterAppear() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Disappear Episode"),
        unsavedEpisode: try Create.unsavedEpisode(
          guid: "disappear-episode",
          title: "Disappear Episode"
        )
      )
    )
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(podcastEpisode))
    let tag = try await repo.insertTag(UnsavedTag(name: "After Disappear"))

    viewModel.appear()

    try await Wait.until(
      { @MainActor in viewModel.observationTask != nil },
      { @MainActor in
        "Expected observation to start before disappear; task=\(String(describing: viewModel.observationTask))"
      }
    )

    viewModel.disappear()

    #expect(viewModel.observationTask == nil)
    #expect(viewModel.appearTask == nil)
    #expect(viewModel.auxiliaryTasks.isEmpty)

    try await repo.addTag(tag.id, to: podcastEpisode.id)

    try await yieldForSpuriousAsyncWork()

    #expect(viewModel.tags.isEmpty)
  }
}
