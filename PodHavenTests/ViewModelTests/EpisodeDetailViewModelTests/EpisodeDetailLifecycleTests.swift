// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("of EpisodeDetailViewModel lifecycle tests", .container)
@MainActor final class EpisodeDetailLifecycleTests {
  @DynamicInjected(\.repo) private var repo

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

    try await yieldForSpuriousAsyncWork()

    #expect(viewModel.observationTask == nil)
    #expect(viewModel.appearTask == nil)
    #expect(viewModel.auxiliaryTasks.isEmpty)
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

    #expect(viewModel.observationTask == nil)

    viewModel.appear()

    try await Wait.until(
      { @MainActor in viewModel.observationTask != nil },
      { @MainActor in
        "Expected appear to start observation; task=\(String(describing: viewModel.observationTask))"
      }
    )

    let firstTask = try #require(viewModel.observationTask)
    #expect(!firstTask.isCancelled)

    viewModel.appear()

    try await Wait.until(
      { @MainActor in viewModel.appearTask == nil },
      { @MainActor in
        "Expected second appear to finish; appearTask=\(String(describing: viewModel.appearTask))"
      }
    )

    let secondTask = try #require(viewModel.observationTask)
    #expect(firstTask == secondTask)
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
    #expect(!viewModel.isOnScreen)
  }
}
