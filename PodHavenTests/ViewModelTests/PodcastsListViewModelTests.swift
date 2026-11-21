// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Testing

@testable import PodHaven

@Suite("of PodcastsListViewModel tests", .container)
@MainActor final class PodcastsListViewModelTests {
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.repo) private var repo

  @Test("selectedPodcastsTagIntersection collapses to common tags across selection")
  func selectedPodcastsTagIntersectionAcrossSelection() async throws {
    let setup = try await setupFourTaggedPodcasts()

    let viewModel = PodcastsListViewModel(title: "Test")
    try await loadEntries(into: viewModel, podcasts: setup.entries)

    // pod1 = {A, B}, pod2 = {B, C}, pod3 = {A, B, C} → common is {B}.
    select(viewModel, ids: [setup.pod1, setup.pod2, setup.pod3])
    #expect(viewModel.selectedPodcastsTagIntersection == [setup.tagB.id])
    #expect(
      viewModel.selectedPodcastsTagUnion == [setup.tagA.id, setup.tagB.id, setup.tagC.id]
    )
    #expect(viewModel.selectionHasTagData)
  }

  @Test("selectedPodcastsTagIntersection collapses to empty when an untagged podcast is selected")
  func selectedPodcastsTagIntersectionWithUntagged() async throws {
    let setup = try await setupFourTaggedPodcasts()

    let viewModel = PodcastsListViewModel(title: "Test")
    try await loadEntries(into: viewModel, podcasts: setup.entries)

    // Adding pod4 (no tags) drags the intersection to empty even though
    // pod1, pod3 share {A, B}; the union still reports every tag in play.
    select(viewModel, ids: [setup.pod1, setup.pod3, setup.pod4])
    #expect(viewModel.selectedPodcastsTagIntersection == [])
    #expect(
      viewModel.selectedPodcastsTagUnion == [setup.tagA.id, setup.tagB.id, setup.tagC.id]
    )
  }

  @Test(
    "selectedPodcastsTagIntersection and union are empty when only untagged podcasts are selected"
  )
  func selectedPodcastsTagHelpersOnUntaggedOnly() async throws {
    let setup = try await setupFourTaggedPodcasts()

    let viewModel = PodcastsListViewModel(title: "Test")
    try await loadEntries(into: viewModel, podcasts: setup.entries)

    select(viewModel, ids: [setup.pod4])
    #expect(viewModel.selectedPodcastsTagIntersection == [])
    #expect(viewModel.selectedPodcastsTagUnion == [])
    #expect(viewModel.selectionHasTagData)
  }

  @Test("selectedPodcastsTagIntersection and union are empty when no podcasts are selected")
  func selectedPodcastsTagHelpersOnEmptySelection() async throws {
    let setup = try await setupFourTaggedPodcasts()

    let viewModel = PodcastsListViewModel(title: "Test")
    try await loadEntries(into: viewModel, podcasts: setup.entries)

    #expect(viewModel.selectedPodcastsTagIntersection == [])
    #expect(viewModel.selectedPodcastsTagUnion == [])
    #expect(!viewModel.selectionHasTagData)
  }

  @Test("selectedPodcastsTagIntersection equals selected podcast's tags for a single selection")
  func selectedPodcastsTagIntersectionForSingleSelection() async throws {
    let setup = try await setupFourTaggedPodcasts()

    let viewModel = PodcastsListViewModel(title: "Test")
    try await loadEntries(into: viewModel, podcasts: setup.entries)

    select(viewModel, ids: [setup.pod2])
    #expect(viewModel.selectedPodcastsTagIntersection == [setup.tagB.id, setup.tagC.id])
    #expect(viewModel.selectedPodcastsTagUnion == [setup.tagB.id, setup.tagC.id])
  }

  // MARK: - Sort modes keep nil-metadata podcasts visible

  @Test("byMostRecentEpisode keeps a zero-episode podcast visible, sorted last")
  func byMostRecentEpisodeKeepsNilEpisodeDateVisible() async throws {
    let withEpisodes =
      try await repo.insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast: try Create.unsavedPodcast(
            feedURL: FeedURL(URL(string: "https://example.com/has-episodes.rss")!),
            title: "Has Episodes"
          ),
          unsavedEpisodes: [try Create.unsavedEpisode(pubDate: 5.minutesAgo)]
        )
      )
      .id
    let zeroEpisodes =
      try await repo.insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast: try Create.unsavedPodcast(
            feedURL: FeedURL(URL(string: "https://example.com/zero-episodes.rss")!),
            title: "Zero Episodes"
          )
        )
      )
      .id
    let entries = try await observatory.listablePodcastsWithEpisodeMetadata().get()

    let viewModel = PodcastsListViewModel(title: "SortNilEpisode")
    viewModel.currentSortMethod = .byMostRecentEpisode
    viewModel.podcastList.allEntries = IdentifiedArray(uniqueElements: entries)
    try await Wait.until(
      { @MainActor in viewModel.podcastList.filteredEntryIDs.contains(withEpisodes) },
      { @MainActor in "list never settled; got \(viewModel.podcastList.filteredEntryIDs)" }
    )

    #expect(viewModel.podcastList.filteredEntryIDs == [withEpisodes, zeroEpisodes])
  }

  @Test("byMostRecentlySubscribed keeps an unsubscribed podcast visible, sorted last")
  func byMostRecentlySubscribedKeepsNilSubscriptionDateVisible() async throws {
    let subscribed =
      try await repo.insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast: try Create.unsavedPodcast(
            feedURL: FeedURL(URL(string: "https://example.com/subscribed.rss")!),
            title: "Subscribed",
            subscriptionDate: 5.minutesAgo
          )
        )
      )
      .id
    let unsubscribed =
      try await repo.insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast: try Create.unsavedPodcast(
            feedURL: FeedURL(URL(string: "https://example.com/unsubscribed.rss")!),
            title: "Unsubscribed",
            subscriptionDate: nil
          )
        )
      )
      .id
    let entries = try await observatory.listablePodcastsWithEpisodeMetadata().get()

    let viewModel = PodcastsListViewModel(title: "SortNilSubscribed")
    viewModel.currentSortMethod = .byMostRecentlySubscribed
    viewModel.podcastList.allEntries = IdentifiedArray(uniqueElements: entries)
    try await Wait.until(
      { @MainActor in viewModel.podcastList.filteredEntryIDs.contains(subscribed) },
      { @MainActor in "list never settled; got \(viewModel.podcastList.filteredEntryIDs)" }
    )

    #expect(viewModel.podcastList.filteredEntryIDs == [subscribed, unsubscribed])
  }

  @Test("deleteSelectedPodcasts logs a notice when nothing is selected")
  func deleteSelectedLogsNoticeWhenNothingSelected() async throws {
    try await LogCapture.withSink { sink in
      let setup = try await setupFourTaggedPodcasts()

      let viewModel = PodcastsListViewModel(title: "Test")
      try await loadEntries(into: viewModel, podcasts: setup.entries)

      // No selection: simulates a menu tap that raced a selection change.
      viewModel.deleteSelectedPodcasts()

      let bailNotices = sink.captured()
        .filter {
          $0.level == .notice && $0.message.contains("deleteSelectedPodcasts")
        }
      #expect(bailNotices.count == 1)

      let fakeRepo = try #require(repo as? FakeRepo)
      try fakeRepo.expectNoCall(methodName: "delete")
    }
  }

  // MARK: - Subscribing a selection

  @Test("subscribeSelectedPodcasts logs a count, not a line per podcast")
  func subscribeSelectedLogsSummary() async throws {
    let podcastCount = 50
    for index in 0..<podcastCount {
      _ = try await Create.podcast(
        feedURL: FeedURL(SyntheticFeed.url(index)),
        title: SyntheticFeed.title(index)
      )
    }
    let viewModel = PodcastsListViewModel(title: "Test")
    try await loadEntries(
      into: viewModel,
      podcasts: try await observatory.listablePodcastsWithEpisodeMetadata().get()
    )
    viewModel.podcastList.selectAllEntries()

    let captured = try await LogCapture.withSink { sink in
      viewModel.subscribeSelectedPodcasts()
      try await Wait.until(
        {
          sink.captured()
            .contains { $0.message.contains("subscribed \(podcastCount) of \(podcastCount)") }
        },
        { "no subscribe summary among \(sink.captured().count) lines" }
      )
      return sink.captured()
    }

    let podcasts = try await repo.allPodcasts(AppDB.noOp)
    #expect(podcasts.count == podcastCount)
    #expect(podcasts.allSatisfy { $0.subscribed })
    #expect(captured.count < 10, "\(captured.map { "\($0.file): \($0.message)" })")
    #expect(captured.allSatisfy { $0.message.count < 500 })
  }

  @Test("subscribeSelectedPodcasts keeps an already-subscribed podcast's subscription date")
  func subscribeSelectedKeepsExistingSubscriptionDate() async throws {
    let originalSubscriptionDate = 30.daysAgo
    let alreadySubscribed = try await Create.podcast(
      feedURL: FeedURL(URL(string: "https://example.com/already-subscribed.rss")!),
      title: "Already Subscribed",
      subscriptionDate: originalSubscriptionDate
    )
    let unsubscribed = try await Create.podcast(
      feedURL: FeedURL(URL(string: "https://example.com/unsubscribed.rss")!),
      title: "Unsubscribed"
    )
    let viewModel = PodcastsListViewModel(title: "Test")
    try await loadEntries(
      into: viewModel,
      podcasts: try await observatory.listablePodcastsWithEpisodeMetadata().get()
    )
    viewModel.podcastList.selectAllEntries()

    let subscriptionTime = Date()
    viewModel.subscribeSelectedPodcasts()
    try await Wait.until(
      { [repo] in try await repo.podcastSeries(unsubscribed.id)?.podcast.subscribed == true },
      { "\(unsubscribed.title) was never subscribed" }
    )

    let newlySubscribed = try #require(await repo.podcastSeries(unsubscribed.id)?.podcast)
    let newDate = try #require(newlySubscribed.subscriptionDate)
    #expect(newDate.approximatelyEquals(subscriptionTime))
    let kept = try #require(await repo.podcastSeries(alreadySubscribed.id)?.podcast)
    let keptDate = try #require(kept.subscriptionDate)
    #expect(keptDate.approximatelyEquals(originalSubscriptionDate))
  }

  @Test("subscribeSelectedPodcasts logs and alerts a failed subscribe")
  func subscribeSelectedLogsFailure() async throws {
    let setup = try await setupFourTaggedPodcasts()
    let viewModel = PodcastsListViewModel(title: "Test")
    try await loadEntries(into: viewModel, podcasts: setup.entries)
    viewModel.podcastList.selectAllEntries()
    let fakeRepo = try #require(repo as? FakeRepo)
    fakeRepo.markSubscribedBulkError(InjectedRepoError())

    let captured = try await LogCapture.withSink { sink in
      viewModel.subscribeSelectedPodcasts()
      try await Wait.until(
        { sink.captured().contains { $0.level == .error } },
        { "no error logged among \(sink.captured().map(\.message))" }
      )
      return sink.captured()
    }

    let failures = captured.filter {
      $0.level == .error && $0.message.contains("subscribeSelectedPodcasts")
    }
    #expect(failures.count == 1, "\(captured.map(\.message))")
    #expect(Container.shared.alert().config?.title == "Error")
    let podcasts = try await repo.allPodcasts(AppDB.noOp)
    #expect(podcasts.allSatisfy { !$0.subscribed })
  }

  @Test("subscribeSelectedPodcasts does not alert when the subscribe is cancelled")
  func subscribeSelectedSkipsAlertOnCancellation() async throws {
    let setup = try await setupFourTaggedPodcasts()
    let viewModel = PodcastsListViewModel(title: "Test")
    try await loadEntries(into: viewModel, podcasts: setup.entries)
    viewModel.podcastList.selectAllEntries()
    let fakeRepo = try #require(repo as? FakeRepo)
    fakeRepo.markSubscribedBulkError(CancellationError())

    try await LogCapture.withSink { sink in
      viewModel.subscribeSelectedPodcasts()
      try await Wait.until(
        { sink.captured().contains { $0.message.contains("subscribeSelectedPodcasts: failed") } },
        { "no failure logged among \(sink.captured().map(\.message))" }
      )
    }

    #expect(Container.shared.alert().config == nil)
  }

  @Test("applyTagToSelectedPodcasts alerts when tagging fails")
  func applyTagToSelectedAlertsOnFailure() async throws {
    let setup = try await setupFourTaggedPodcasts()
    let viewModel = PodcastsListViewModel(title: "Test")
    try await loadEntries(into: viewModel, podcasts: setup.entries)
    viewModel.podcastList.selectAllEntries()
    let deletedTag = try await repo.insertTag(UnsavedTag(name: "Deleted"))
    try await repo.deleteTag(deletedTag.id)

    viewModel.applyTagToSelectedPodcasts(deletedTag.id)

    let alert = Container.shared.alert()
    try await Wait.until(
      { @MainActor in alert.config?.title == "Error" },
      { "applyTagToSelectedPodcasts never alerted on the failed tag write" }
    )
  }

  // MARK: - Helpers

  private struct InjectedRepoError: Error, Sendable {}

  private struct Setup {
    let pod1: Podcast.ID
    let pod2: Podcast.ID
    let pod3: Podcast.ID
    let pod4: Podcast.ID
    let tagA: PodHaven.Tag
    let tagB: PodHaven.Tag
    let tagC: PodHaven.Tag
    let entries: [PodcastWithEpisodeMetadata<ListablePodcast>]
  }

  private func setupFourTaggedPodcasts() async throws -> Setup {
    let p1 =
      try await repo.insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast: try Create.unsavedPodcast(
            feedURL: FeedURL(URL(string: "https://example.com/p1.rss")!),
            title: "P1"
          )
        )
      )
      .id
    let p2 =
      try await repo.insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast: try Create.unsavedPodcast(
            feedURL: FeedURL(URL(string: "https://example.com/p2.rss")!),
            title: "P2"
          )
        )
      )
      .id
    let p3 =
      try await repo.insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast: try Create.unsavedPodcast(
            feedURL: FeedURL(URL(string: "https://example.com/p3.rss")!),
            title: "P3"
          )
        )
      )
      .id
    let p4 =
      try await repo.insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast: try Create.unsavedPodcast(
            feedURL: FeedURL(URL(string: "https://example.com/p4.rss")!),
            title: "P4"
          )
        )
      )
      .id

    let tagA = try await repo.insertTag(UnsavedTag(name: "Alpha"))
    let tagB = try await repo.insertTag(UnsavedTag(name: "Beta"))
    let tagC = try await repo.insertTag(UnsavedTag(name: "Cherry"))

    try await repo.addTag(tagA.id, to: p1)
    try await repo.addTag(tagB.id, to: p1)
    try await repo.addTag(tagB.id, to: p2)
    try await repo.addTag(tagC.id, to: p2)
    try await repo.addTag(tagA.id, to: p3)
    try await repo.addTag(tagB.id, to: p3)
    try await repo.addTag(tagC.id, to: p3)

    let entries = try await observatory.listablePodcastsWithEpisodeMetadata().get()

    return Setup(
      pod1: p1,
      pod2: p2,
      pod3: p3,
      pod4: p4,
      tagA: tagA,
      tagB: tagB,
      tagC: tagC,
      entries: entries
    )
  }

  private func loadEntries(
    into viewModel: PodcastsListViewModel,
    podcasts: [PodcastWithEpisodeMetadata<ListablePodcast>]
  ) async throws {
    viewModel.podcastList.allEntries = IdentifiedArray(uniqueElements: podcasts)
    try await Wait.until(
      { @MainActor in viewModel.podcastList.filteredEntries.count == podcasts.count },
      { @MainActor in
        "filteredEntries didn't populate; got \(viewModel.podcastList.filteredEntries.count)"
      }
    )
  }

  private func select(_ viewModel: PodcastsListViewModel, ids: [Podcast.ID]) {
    for id in ids {
      viewModel.podcastList.isSelected[id] = true
    }
  }
}
