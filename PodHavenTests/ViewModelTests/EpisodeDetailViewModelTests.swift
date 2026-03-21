// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("EpisodeDetailViewModel tests", .container)
@MainActor final class EpisodeDetailViewModelTests {
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.repo) private var repo

  private var fakeQueue: FakeQueue { queue as! FakeQueue }

  @Test("performAppear loads a saved episode and observes finish updates")
  func performAppearLoadsSavedEpisodeAndObservesFinishUpdates() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Episode Detail"),
        unsavedEpisode: try Create.unsavedEpisode(
          guid: "episode-detail",
          title: "Episode Detail",
          currentTime: CMTime.seconds(123)
        )
      )
    )
    let viewModel = EpisodeDetailViewModel(
      episode: DisplayedEpisode(try podcastEpisode.toOriginalUnsavedPodcastEpisode())
    )

    try await viewModel.performAppear()

    #expect(viewModel.episode.isSaved)
    #expect(viewModel.episode.episodeID == podcastEpisode.id)

    _ = try await repo.markFinished(podcastEpisode.id)

    try await Wait.until(
      { @MainActor in
        viewModel.episode.finished && viewModel.episode.currentTime == .zero
      },
      { @MainActor in
        """
        Expected performAppear observation to pick up finish changes.
        finished: \(viewModel.episode.finished)
        currentTime: \(viewModel.episode.currentTime)
        """
      }
    )
  }

  @Test("addToTopOfQueue is a no-op for the first queued episode")
  func addToTopOfQueueIsNoOpForFirstQueuedEpisode() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Queue Guard"),
        unsavedEpisode: try Create.unsavedEpisode(
          guid: "queue-guard",
          title: "Queue Guard",
          queueOrder: 0,
          queueDate: Date()
        )
      )
    )
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(podcastEpisode))

    viewModel.addToTopOfQueue()

    try fakeQueue.expectNoCall(methodName: "unshift")
    #expect(viewModel.atTopOfQueue == true)
  }

  @Test("markFinished saves an unsaved episode before finishing it")
  func markFinishedSavesUnsavedEpisodeBeforeFinishingIt() async throws {
    let unsavedPodcastEpisode = UnsavedPodcastEpisode(
      unsavedPodcast: try Create.unsavedPodcast(title: "Unsaved Podcast"),
      unsavedEpisode: try Create.unsavedEpisode(
        guid: "unsaved-finish",
        title: "Unsaved Episode",
        currentTime: CMTime.seconds(42)
      )
    )
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(unsavedPodcastEpisode))

    viewModel.markFinished()

    try await Wait.until(
      { @MainActor in
        viewModel.episode.isSaved && viewModel.episode.finished
      },
      { @MainActor in
        """
        Expected markFinished to save and finish the unsaved episode.
        saved: \(viewModel.episode.isSaved)
        finished: \(viewModel.episode.finished)
        """
      }
    )

    let savedEpisode = try await repo.podcastEpisode(unsavedPodcastEpisode.unsavedEpisode.id)
    #expect(savedEpisode != nil)
    #expect(savedEpisode?.episode.finishDate != nil)
    #expect(savedEpisode?.episode.currentTime == .zero)
  }
}
