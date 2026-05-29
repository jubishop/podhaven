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
  @DynamicInjected(\.sharedState) private var sharedState

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

    _ = EpisodeDetailViewModel(episode: DisplayedEpisode(podcastEpisode))

    fakeObservatory.clearAllCalls()
    try await yieldForSpuriousAsyncWork()

    _ = try fakeObservatory.expectCalls(methodName: "podcastEpisodeWithTags", count: 0)
  }

  @Test(
    "init for a non-saved seed does not start an observation task",
    arguments: EpisodeNonSavedSeed.allCases
  )
  func initForNonSavedSeedDoesNotStartObservation(seed: EpisodeNonSavedSeed) async throws {
    _ = try await seed.makeViewModel(repo: repo, observatory: observatory)

    fakeObservatory.clearAllCalls()
    try await yieldForSpuriousAsyncWork()

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

    viewModel.appear()

    try await Wait.until(
      { @MainActor in
        self.fakeObservatory.allCallsInOrder
          .filter { $0.methodName == "podcastEpisodeWithTags" }
          .count == 1
      },
      { @MainActor in
        """
        Expected appear to start observation exactly once.
        calls: \(self.fakeObservatory.allCallsInOrder.map(\.toString))
        """
      }
    )

    viewModel.appear()
    try await yieldForSpuriousAsyncWork()

    _ = try fakeObservatory.expectCalls(methodName: "podcastEpisodeWithTags", count: 1)
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
      { @MainActor in
        self.fakeObservatory.allCallsInOrder.contains { $0.methodName == "podcastEpisodeWithTags" }
      },
      { @MainActor in
        """
        Expected appear to start observation before disappearing.
        calls: \(self.fakeObservatory.allCallsInOrder.map(\.toString))
        """
      }
    )

    fakeObservatory.clearAllCalls()
    viewModel.disappear()

    #expect(viewModel.lifecycle.isOnScreen == false)
    viewModel.playNow()

    try await yieldForSpuriousAsyncWork()

    _ = try fakeObservatory.expectCalls(methodName: "podcastEpisodeWithTags", count: 0)
  }

  @Test("playNow without appear completes the action without starting observation")
  func playNowWithoutAppearCompletesWithoutStartingObservation() async throws {
    let unsavedPodcastEpisode = UnsavedPodcastEpisode(
      unsavedPodcast: try Create.unsavedPodcast(title: "Offscreen Play"),
      unsavedEpisode: try Create.unsavedEpisode(
        guid: "offscreen-play",
        title: "Offscreen Play"
      )
    )
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(unsavedPodcastEpisode))

    fakeObservatory.clearAllCalls()
    #expect(viewModel.lifecycle.isOnScreen == false)

    viewModel.playNow()

    try await Wait.until(
      { @MainActor in
        guard viewModel.episode.isSaved, let episodeID = viewModel.episode.episodeID else {
          return false
        }
        return self.sharedState.currentEpisodeID == episodeID
      },
      { @MainActor in
        """
        Expected off-screen playNow to save and load the episode.
        saved: \(viewModel.episode.isSaved)
        episodeID: \(String(describing: viewModel.episode.episodeID))
        currentEpisodeID: \(String(describing: self.sharedState.currentEpisodeID))
        """
      }
    )

    _ = try fakeObservatory.expectCalls(methodName: "podcastEpisodeWithTags", count: 0)
  }

  @Test("playNow after disappear loads playback")
  func playNowAfterDisappearLoadsPlayback() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Disappear Playback"),
        unsavedEpisode: try Create.unsavedEpisode(
          guid: "disappear-playback",
          title: "Disappear Playback"
        )
      )
    )
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(podcastEpisode))

    viewModel.appear()

    viewModel.disappear()
    #expect(viewModel.lifecycle.isOnScreen == false)

    viewModel.playNow()

    try await Wait.until(
      { @MainActor in self.sharedState.currentEpisodeID == podcastEpisode.id },
      { @MainActor in
        """
        Expected off-screen playNow to load playback.
        currentEpisodeID: \(String(describing: self.sharedState.currentEpisodeID))
        """
      }
    )
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
      { @MainActor in
        self.fakeObservatory.allCallsInOrder.contains { $0.methodName == "podcastEpisodeWithTags" }
      },
      { @MainActor in
        """
        Expected appear to start observation before disappearing.
        calls: \(self.fakeObservatory.allCallsInOrder.map(\.toString))
        """
      }
    )

    viewModel.disappear()

    try await repo.addTag(tag.id, to: podcastEpisode.id)

    try await yieldForSpuriousAsyncWork()

    #expect(viewModel.tags.isEmpty)
  }
}
