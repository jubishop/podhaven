// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of EpisodeDetailViewModel tests", .container)
@MainActor final class EpisodeDetailViewModelTests {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.navigation) private var navigation
  @DynamicInjected(\.observatory) private var observatory
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

    try await viewModel.performAppear()

    #expect(viewModel.episode.episodeID == podcastEpisode.id)
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

    try await viewModel.performAppear()

    #expect(alert.config != nil)
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

    try await viewModel.performAppear()

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

    try await viewModel.performAppear()

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

    try await viewModel.performAppear()
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

    try await viewModel.performAppear()

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

  @Test("addTag saves an unsaved episode before tagging it")
  func addTagSavesUnsavedEpisodeBeforeTagging() async throws {
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

    try await Wait.until(
      { @MainActor in
        viewModel.episode.isSaved && viewModel.tags.map(\.id) == [tag.id]
      },
      { @MainActor in
        """
        Expected addTag to save and tag the unsaved episode.
        saved: \(viewModel.episode.isSaved)
        tags: \(viewModel.tags.map(\.name))
        """
      }
    )
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
