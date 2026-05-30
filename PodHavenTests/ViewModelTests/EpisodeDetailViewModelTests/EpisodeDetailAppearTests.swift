// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of EpisodeDetailViewModel performAppear tests", .container)
@MainActor final class EpisodeDetailAppearTests {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.navigation) private var navigation
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.repo) private var repo

  private var fakeObservatory: FakeObservatory {
    observatory as! FakeObservatory
  }

  // For appear branches whose only correct outcome is "nothing changed"
  // (an unsaved seed staying unsaved), drive performAppear to completion so
  // a regression that dismissed or fabricated state would surface.
  private func yieldForSpuriousAsyncWork() async throws {
    let yields = ThreadSafe(0)
    try await Wait.until(
      { @MainActor in
        await Task.yield()
        yields { $0 += 1 }
        return yields() >= 20
      },
      { "Expected performAppear to run before asserting it left state intact." }
    )
  }

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

    viewModel.appear()

    try await Wait.until(
      { @MainActor in viewModel.episode.episodeID == podcastEpisode.id },
      { @MainActor in
        """
        Expected performAppear to hydrate the saved episode.
        episodeID: \(String(describing: viewModel.episode.episodeID))
        episode: \(viewModel.episode.toString)
        """
      }
    )
    #expect(viewModel.episode.isSaved)

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

  @Test("listed episodes expose a share URL before detail hydration")
  func listedEpisodesExposeShareURLBeforeDetailHydration() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "List Episode Detail"),
        unsavedEpisode: try Create.unsavedEpisode(
          guid: "list-episode-detail",
          title: "List Episode Detail"
        )
      )
    )
    let listableEpisodes =
      try await observatory.listablePodcastEpisodes(
        filter: Episode.Columns.id == podcastEpisode.id
      )
      .get()
    let listedEpisode = try #require(listableEpisodes.first)

    let viewModel = EpisodeDetailViewModel(listedEpisode: ListedEpisode(listedEpisode))

    #expect(
      ShareURL.episode(feedURL: viewModel.episode.feedURL, guid: viewModel.episode.mediaGUID.guid)
        == ShareURL.episode(feedURL: podcastEpisode.feedURL, guid: podcastEpisode.mediaGUID.guid)
    )

    viewModel.appear()

    try await Wait.until(
      { @MainActor in viewModel.episode.episodeID == podcastEpisode.id },
      { @MainActor in
        """
        Expected performAppear to hydrate the listed episode.
        episodeID: \(String(describing: viewModel.episode.episodeID))
        episode: \(viewModel.episode.toString)
        """
      }
    )
  }

  @Test("missing saved listed episodes alert and dismiss instead of fabricating unsaved detail")
  func missingSavedListedEpisodesAlertAndDismiss() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Deleted Episode"),
        unsavedEpisode: try Create.unsavedEpisode(
          guid: "deleted-episode-detail",
          title: "Deleted Episode"
        )
      )
    )
    let listableEpisodes =
      try await observatory.listablePodcastEpisodes(
        filter: Episode.Columns.id == podcastEpisode.id
      )
      .get()
    let listedEpisode = try #require(listableEpisodes.first)
    let listed = ListedEpisode(listedEpisode)

    navigation.currentTab = .episodes
    navigation.episodes.path = [.episodesViewType(.recentEpisodes), .listedEpisode(listed)]

    _ = try await repo.deletePodcast(podcastEpisode.podcast.id)

    let viewModel = EpisodeDetailViewModel(listedEpisode: listed)

    viewModel.appear()

    try await Wait.until(
      { @MainActor in self.alert.config != nil },
      { @MainActor in
        """
        Expected a missing saved listed episode to alert and dismiss.
        alert: \(String(describing: self.alert.config))
        path: \(self.navigation.episodes.path)
        """
      }
    )
    #expect(navigation.episodes.path == [.episodesViewType(.recentEpisodes)])
  }

  @Test("missing listed unsaved episodes revert to unsaved detail without dismissing")
  func missingListedUnsavedEpisodesRevertToUnsavedDetail() async throws {
    let unsavedPodcastEpisode = UnsavedPodcastEpisode(
      unsavedPodcast: try Create.unsavedPodcast(title: "Unsaved Podcast"),
      unsavedEpisode: try Create.unsavedEpisode(
        guid: "listed-unsaved",
        title: "Unsaved Detail",
        description: "Unsaved Description"
      )
    )
    let listed = ListedEpisode(unsavedPodcastEpisode)
    let viewModel = EpisodeDetailViewModel(listedEpisode: listed)

    viewModel.appear()
    try await yieldForSpuriousAsyncWork()

    #expect(viewModel.episode.isSaved == false)
    #expect(viewModel.episode.title == unsavedPodcastEpisode.title)
    #expect(viewModel.episode.description == unsavedPodcastEpisode.description)
    #expect(alert.config == nil)
  }

  @Test("missing unsaved displayed episodes stay on their unsaved detail")
  func missingUnsavedDisplayedEpisodesStayUnsaved() async throws {
    let unsavedPodcastEpisode = UnsavedPodcastEpisode(
      unsavedPodcast: try Create.unsavedPodcast(title: "Displayed Unsaved Podcast"),
      unsavedEpisode: try Create.unsavedEpisode(
        guid: "displayed-unsaved",
        title: "Displayed Unsaved Detail",
        description: "Displayed Unsaved Description"
      )
    )
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(unsavedPodcastEpisode))

    viewModel.appear()
    try await yieldForSpuriousAsyncWork()

    #expect(viewModel.episode.isSaved == false)
    #expect(viewModel.episode.title == unsavedPodcastEpisode.title)
    #expect(viewModel.episode.description == unsavedPodcastEpisode.description)
    #expect(alert.config == nil)
  }

  @Test("observed deleted saved episodes revert to unsaved detail")
  func observedDeletedSavedEpisodesRevertToUnsavedDetail() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Observed Delete"),
        unsavedEpisode: try Create.unsavedEpisode(
          guid: "observed-delete",
          title: "Observed Delete"
        )
      )
    )
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
      { @MainActor in
        viewModel.episode.isSaved == false
          && viewModel.episode.mediaGUID == podcastEpisode.mediaGUID
      },
      { @MainActor in
        """
        Expected deleted saved episode to revert to unsaved detail.
        saved: \(viewModel.episode.isSaved)
        episode: \(viewModel.episode.toString)
        """
      }
    )
  }

  @Test("opening a shared (guid, mediaURL) binds each podcast's list row to its own episode")
  func sharedMediaGUIDBindsToOriginatingPodcast() async throws {
    let sharedGUID = GUID("shared-cross-podcast-guid")
    let sharedMediaURL = MediaURL(URL.valid())

    // Two podcasts carry the same (guid, mediaURL). A global lookup collapses
    // both onto a single row; binding must follow each list row's own
    // Episode.ID so opening from A lands on A and from B lands on B.
    let aEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Podcast A"),
        unsavedEpisode: try Create.unsavedEpisode(
          guid: sharedGUID,
          mediaURL: sharedMediaURL,
          title: "Shared Episode (A)",
          description: "Description A"
        )
      )
    )
    let bEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Podcast B"),
        unsavedEpisode: try Create.unsavedEpisode(
          guid: sharedGUID,
          mediaURL: sharedMediaURL,
          title: "Shared Episode (B)",
          description: "Description B"
        )
      )
    )
    #expect(aEpisode.id != bEpisode.id)

    let aListable = try #require(
      try await observatory.listablePodcastEpisodes(
        filter: Episode.Columns.id == aEpisode.id
      )
      .get().first
    )
    let bListable = try #require(
      try await observatory.listablePodcastEpisodes(
        filter: Episode.Columns.id == bEpisode.id
      )
      .get().first
    )

    let aViewModel = EpisodeDetailViewModel(listedEpisode: ListedEpisode(aListable))
    let bViewModel = EpisodeDetailViewModel(listedEpisode: ListedEpisode(bListable))
    aViewModel.appear()
    bViewModel.appear()

    // `description` is nil on a saved list row and only fills in once
    // performAppear hydrates the detail, so it gates completion and reveals
    // which podcast's row each view model actually bound to.
    try await Wait.until(
      { @MainActor in
        aViewModel.episode.description != nil && bViewModel.episode.description != nil
      },
      { @MainActor in
        """
        Expected both detail view models to finish hydration.
        a.description: \(String(describing: aViewModel.episode.description))
        b.description: \(String(describing: bViewModel.episode.description))
        """
      }
    )

    #expect(aViewModel.episode.episodeID == aEpisode.id)
    #expect(aViewModel.episode.description == "Description A")
    #expect(bViewModel.episode.episodeID == bEpisode.id)
    #expect(bViewModel.episode.description == "Description B")
  }
}
