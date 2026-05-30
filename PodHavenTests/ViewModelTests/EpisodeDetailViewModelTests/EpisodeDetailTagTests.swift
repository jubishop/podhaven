// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of EpisodeDetailViewModel tag tests", .container)
@MainActor final class EpisodeDetailTagTests {
  @DynamicInjected(\.appDB) private var appDB
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.repo) private var repo

  private var fakeObservatory: FakeObservatory {
    observatory as! FakeObservatory
  }

  @Test("tag observation rebinds after saved episode is deleted and re-saved")
  func tagObservationRebindsAfterDeleteAndResave() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Tag Delete Resave"),
        unsavedEpisode: try Create.unsavedEpisode(
          guid: "tag-delete-resave",
          title: "Tag Delete Resave"
        )
      )
    )
    let tag = try await repo.insertTag(UnsavedTag(name: "Recovered"))
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(podcastEpisode))

    viewModel.appear()

    // Observation must be live before the delete, or performAppear's own
    // lookup races the deletion and dismisses instead of reverting.
    try await Wait.until(
      { @MainActor in
        self.fakeObservatory.allCallsInOrder.contains { $0.methodName == "podcastEpisodeWithTags" }
      },
      { @MainActor in
        """
        Expected appear to start observing the saved episode before deletion.
        calls: \(self.fakeObservatory.allCallsInOrder.map(\.toString))
        """
      }
    )

    _ = try await repo.deletePodcast(podcastEpisode.podcast.id)

    try await Wait.until(
      { @MainActor in !viewModel.episode.isSaved },
      { @MainActor in
        "Expected deleted saved episode to revert before re-saving. episode: \(viewModel.episode.toString)"
      }
    )

    viewModel.markFinished()

    try await Wait.until(
      { @MainActor in viewModel.episode.isSaved && viewModel.episode.finished },
      { @MainActor in
        """
        Expected markFinished to re-save the episode.
        saved: \(viewModel.episode.isSaved)
        finished: \(viewModel.episode.finished)
        """
      }
    )

    let resaved = try #require(
      try await repo.podcastEpisode(
        podcastEpisode.episode.mediaGUID,
        feedURL: podcastEpisode.feedURL
      )
    )
    try await repo.addTag(tag.id, to: resaved.id)

    try await Wait.until(
      { @MainActor in viewModel.tags.map(\.id) == [tag.id] },
      { @MainActor in
        """
        Expected tag observation to rebind to the re-saved episode and surface the added tag.
        tags: \(viewModel.tags.map(\.name))
        """
      }
    )
  }

  @Test("observation restarts after a podcastEpisodeWithTags failure")
  func observationRestartsAfterPodcastEpisodeWithTagsFailure() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Recovery"),
        unsavedEpisode: try Create.unsavedEpisode(guid: "recovery", title: "Recovery")
      )
    )
    let tag = try await repo.insertTag(UnsavedTag(name: "Recovered"))
    try await repo.addTag(tag.id, to: podcastEpisode.id)

    let dbReader = appDB.unsafeTestDB
    fakeObservatory.podcastEpisodeWithTagsScript([
      { _ in
        ValueObservation
          .tracking { _ -> PodcastEpisodeWithTags? in
            throw TestError.simulatedFailure
          }
          .values(in: dbReader)
      }
    ])

    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(podcastEpisode))

    // First appear subscribes to the scripted (failing) observation.
    // SwiftUI can deliver multiple .onAppear without an intervening
    // .onDisappear, so simulate that by re-entering appear from the
    // poll loop. With the fix, the failed task self-clears and the next
    // restart subscribes to the real observatory and surfaces the tag.
    // Without the fix, observationTask permanently retains the dead task
    // and every subsequent startObservation() returns early.
    viewModel.appear()

    // Raise priority above the default `.background` so the unstructured
    // `Task {}` that `startObservation()` spawns from inside this poll
    // block doesn't inherit `.background` and get starved long enough
    // that every subsequent rebind short-circuits on the still-running
    // failed task.
    try await Wait.until(
      maxAttempts: 200,
      delay: .milliseconds(50),
      priority: .userInitiated,
      { @MainActor in
        viewModel.appear()
        return viewModel.tags.map(\.id) == [tag.id]
      },
      { @MainActor in
        """
        Expected observation to restart after failure and surface the tag.
        tags: \(viewModel.tags.map(\.name))
        """
      }
    )
  }

  @Test("addTag observes saved episode tags and removeTag clears them")
  func addAndRemoveTagOnSavedEpisode() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Tagged"),
        unsavedEpisode: try Create.unsavedEpisode(guid: "tagged-ep", title: "Tagged")
      )
    )
    let tag = try await repo.insertTag(UnsavedTag(name: "Bookmark"))
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(podcastEpisode))

    viewModel.appear()

    viewModel.addTag(tag.id)

    try await Wait.until(
      { @MainActor in viewModel.tags.map(\.id) == [tag.id] },
      { @MainActor in
        "Expected episode tag observation to surface added tag. tags: \(viewModel.tags.map(\.name))"
      }
    )

    viewModel.removeTag(tag.id)

    try await Wait.until(
      { @MainActor in viewModel.tags.isEmpty },
      { @MainActor in
        "Expected episode tag observation to clear after removeTag. tags: \(viewModel.tags.map(\.name))"
      }
    )
  }

  @Test("addTag writes tag mapping for a saved listed episode before performAppear hydrates")
  func addTagWritesMappingForSavedListedEpisodeBeforePerformAppear() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Pre-Hydration Tag"),
        unsavedEpisode: try Create.unsavedEpisode(
          guid: "pre-hydration-tag",
          title: "Pre-Hydration Tag"
        )
      )
    )
    let listableEpisodes =
      try await observatory.listablePodcastEpisodes(
        filter: Episode.Columns.id == podcastEpisode.id
      )
      .get()
    let listedEpisode = try #require(listableEpisodes.first)
    let tag = try await repo.insertTag(UnsavedTag(name: "Bookmark"))
    let viewModel = EpisodeDetailViewModel(listedEpisode: ListedEpisode(listedEpisode))

    // The view shows TagsView based on viewModel.episode.isSaved, which is
    // already true from the listed snapshot — before performAppear() finishes
    // hydrating podcastEpisode. A tap landing in that window must still write
    // the tag mapping; otherwise it is silently dropped.
    #expect(viewModel.episode.isSaved)

    viewModel.addTag(tag.id)

    try await Wait.until(
      { @MainActor in
        let observed = try await self.observatory.podcastEpisodeWithTags(podcastEpisode.id).get()
        return observed?.tags.map(\.id) == [tag.id]
      },
      { @MainActor in
        "Expected addTag to write the tag mapping before performAppear hydration."
      }
    )
  }

  @Test("addTag is a no-op for unsaved episodes")
  func addTagIsNoOpForUnsavedEpisode() async throws {
    let unsavedPodcastEpisode = UnsavedPodcastEpisode(
      unsavedPodcast: try Create.unsavedPodcast(title: "Unsaved For Tagging"),
      unsavedEpisode: try Create.unsavedEpisode(
        guid: "unsaved-tagging",
        title: "Unsaved For Tagging"
      )
    )
    let tag = try await repo.insertTag(UnsavedTag(name: "Listen Later"))
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(unsavedPodcastEpisode))

    viewModel.addTag(tag.id)

    #expect(viewModel.episode.isSaved == false)
    #expect(viewModel.tags.isEmpty)
    #expect(
      try await repo.podcastEpisode(
        unsavedPodcastEpisode.mediaGUID,
        feedURL: unsavedPodcastEpisode.feedURL
      ) == nil
    )
  }
}
