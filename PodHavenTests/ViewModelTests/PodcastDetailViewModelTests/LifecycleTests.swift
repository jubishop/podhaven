// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Semaphore
import Testing

@testable import PodHaven

// Regression coverage for SwiftUI destination-builder churn: transient
// PodcastDetailViewModel instances must not start any long-lived async
// work in `init` — observation and share-artwork loading belong to the
// kept (appeared) model only.
enum NonSavedSeed: Sendable, CaseIterable, CustomTestStringConvertible {
  case listed
  case unsavedDisplayed
  case unsavedSeries

  var testDescription: String {
    switch self {
    case .listed: return "listed-podcast bridge"
    case .unsavedDisplayed: return "unsaved displayed podcast"
    case .unsavedSeries: return "unsaved podcast series"
    }
  }

  @MainActor
  func makeViewModel(repo: any Databasing) async throws -> PodcastDetailViewModel {
    switch self {
    case .listed:
      let savedSeries = try await repo.insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast: try Create.unsavedPodcast(title: "Listed Init")
        )
      )
      let listablePodcast = try await PodcastDetailTestHelpers.fetchListablePodcast(savedSeries.id)
      return PodcastDetailViewModel(listedPodcast: ListedPodcast(saved: listablePodcast))
    case .unsavedDisplayed:
      return PodcastDetailViewModel(
        podcast: DisplayedPodcast(try Create.unsavedPodcast(title: "Unsaved Init"))
      )
    case .unsavedSeries:
      return PodcastDetailViewModel(
        unsavedPodcastSeries: UnsavedPodcastSeries(
          unsavedPodcast: try Create.unsavedPodcast(title: "Series Init")
        )
      )
    }
  }
}

@Suite("of PodcastDetailViewModel lifecycle tests", .container)
@MainActor final class LifecycleTests {
  @DynamicInjected(\.fakeDataLoader) private var fakeDataLoader
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.podcastFeedSession) private var podcastFeedSession
  @DynamicInjected(\.recommendationRepo) private var recommendationRepo
  @DynamicInjected(\.repo) private var repo

  private var feedSession: FakeDataFetchable { podcastFeedSession as! FakeDataFetchable }

  private var fakeObservatory: FakeObservatory {
    observatory as! FakeObservatory
  }

  private var fakeRecommendationRepo: FakeRecommendationRepo {
    recommendationRepo as! FakeRecommendationRepo
  }

  @Test("init for a saved displayed podcast does not start an observation task")
  func initForSavedDisplayedPodcastDoesNotStartObservation() async throws {
    let savedPodcast = try await Create.podcast(title: "Saved Init")

    _ = PodcastDetailViewModel(podcast: DisplayedPodcast(savedPodcast))

    fakeObservatory.clearAllCalls()
    try await yieldForSpuriousAsyncWork()

    _ = try fakeObservatory.expectCalls(methodName: "podcastSeriesDetail", count: 0)
  }

  // Scope-coverage: the listed/unsaved seeds have no `savedSeries.id`,
  // so the pre-fix `startObservation(state.savedSeries?.id)` no-op'd and
  // these would have passed before the fix. Pin them so a future
  // regression that learns to start observation for non-saved states
  // can't sneak in.
  @Test(
    "init for a non-saved seed does not start an observation task",
    arguments: NonSavedSeed.allCases
  )
  func initForNonSavedSeedDoesNotStartObservation(seed: NonSavedSeed) async throws {
    _ = try await seed.makeViewModel(repo: repo)

    fakeObservatory.clearAllCalls()
    try await yieldForSpuriousAsyncWork()

    _ = try fakeObservatory.expectCalls(methodName: "podcastSeriesDetail", count: 0)
  }

  @Test("many transient inits do not start observation until a single appear")
  func manyTransientInitsDoNotStartObservationUntilAppear() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/storm-init.rss")!)
    let imageURL = try #require(URL(string: "https://example.com/storm-artwork.png"))
    await feedSession.respond(
      to: feedURL.rawValue,
      data: PreviewBundle.loadAsset(named: "hardfork_short", in: .FeedRSS)
    )
    let imageData = FakeDataLoader.createSolidColor(.purple).pngData()!
    let initLoadCount = ThreadSafe(0)
    fakeDataLoader.respond(to: imageURL) { _ in
      initLoadCount { $0 += 1 }
      return imageData
    }

    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(
          feedURL: feedURL,
          title: "Storm Init",
          image: imageURL
        ),
        unsavedEpisodes: [try Create.unsavedEpisode(title: "Storm Episode")]
      )
    )
    let displayedPodcast = DisplayedPodcast(savedSeries.podcast)

    fakeObservatory.clearAllCalls()

    var transientViewModels: [PodcastDetailViewModel] = []
    transientViewModels.reserveCapacity(8)
    for _ in 0..<8 {
      transientViewModels.append(PodcastDetailViewModel(podcast: displayedPodcast))
    }

    try await yieldForSpuriousAsyncWork()

    #expect(initLoadCount() == 0)
    _ = try fakeObservatory.expectCalls(methodName: "podcastSeriesDetail", count: 0)

    let keeper = PodcastDetailViewModel(podcast: displayedPodcast)
    keeper.appear()

    try await Wait.until(
      { @MainActor in keeper.episodeList.allEntries.count >= 1 },
      { @MainActor in
        """
        Expected the kept model to hydrate after appear.
        entries: \(keeper.episodeList.allEntries.count)
        """
      }
    )

    _ = try fakeObservatory.expectCalls(methodName: "podcastSeriesDetail", count: 1)
    _ = transientViewModels
  }

  @Test("init does not request share artwork before performAppear")
  func initDoesNotRequestShareArtwork() async throws {
    let initImageURL = try #require(URL(string: "https://example.com/init-artwork-image.png"))
    let drainImageURL = try #require(URL(string: "https://example.com/init-artwork-drain.png"))
    let imageData = FakeDataLoader.createSolidColor(.blue).pngData()!
    let initLoadCount = ThreadSafe(0)
    let drainLoadCount = ThreadSafe(0)
    fakeDataLoader.respond(to: initImageURL) { _ in
      initLoadCount { $0 += 1 }
      return imageData
    }
    fakeDataLoader.respond(to: drainImageURL) { _ in
      drainLoadCount { $0 += 1 }
      return imageData
    }

    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(
          feedURL: FeedURL(URL(string: "https://example.com/init-artwork.rss")!),
          title: "Init Artwork",
          image: initImageURL
        )
      )
    )

    // Hold a strong reference for the lifetime of the test so that any
    // spuriously-spawned `Task { [weak self] in ... }` started in init
    // doesn't get short-circuited by VM deallocation — that's exactly
    // the scenario this regression covers, where SwiftUI does keep the
    // (transient) instance alive long enough to start work.
    let viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(savedSeries.podcast))

    fakeObservatory.clearAllCalls()

    // Race: kick off a deliberate load via the same image pipeline and
    // wait for it to complete. If Nuke had time to handle this request,
    // it had time to handle any spurious init-spawned request too — so
    // a still-zero `initLoadCount` afterward is a real negative, not a
    // timing artifact.
    Task {
      do {
        _ = try await Container.shared.imagePipeline().image(for: drainImageURL)
      } catch {
        Issue.record("Drain image load failed: \(error)")
      }
    }
    try await Wait.until(
      { drainLoadCount() == 1 },
      { "Expected drain image to be loaded; drainLoadCount=\(drainLoadCount())" }
    )

    #expect(!fakeDataLoader.loadedURLs().contains(initImageURL))
    #expect(initLoadCount() == 0)
    _ = try fakeObservatory.expectCalls(methodName: "podcastSeriesDetail", count: 0)
    _ = viewModel  // keep alive until the assertions run
  }

  @Test("appear starts observation for a saved displayed podcast")
  func appearStartsObservationForSavedDisplayedPodcast() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/appear-observation.rss")!)
    let imageURL = try #require(URL(string: "https://example.com/appear-observation-image.png"))
    await feedSession.respond(
      to: feedURL.rawValue,
      data: PreviewBundle.loadAsset(named: "hardfork_short", in: .FeedRSS)
    )
    fakeDataLoader.respond(
      to: imageURL,
      data: FakeDataLoader.createSolidColor(.green).pngData()!
    )

    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(
          feedURL: feedURL,
          title: "Appear Observation",
          image: imageURL
        ),
        unsavedEpisodes: [try Create.unsavedEpisode(title: "Episode 1")]
      )
    )
    let viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(savedSeries.podcast))

    fakeObservatory.clearAllCalls()

    try await PodcastDetailTestHelpers.appear(viewModel)

    let entryCountAfterFirstAppear = viewModel.episodeList.allEntries.count
    let entryIDsAfterFirstAppear = viewModel.episodeList.allEntries.map(\.id)
    _ = try fakeObservatory.expectCalls(methodName: "podcastSeriesDetail", count: 1)

    // A second appear must not start another observatory subscription.
    viewModel.appear()
    try await yieldForSpuriousAsyncWork()

    _ = try fakeObservatory.expectCalls(methodName: "podcastSeriesDetail", count: 1)
    #expect(viewModel.episodeList.allEntries.count == entryCountAfterFirstAppear)
    #expect(viewModel.episodeList.allEntries.map(\.id) == entryIDsAfterFirstAppear)
  }

  @Test("subscribe after disappear does not restart observation")
  func subscribeAfterDisappearDoesNotRestartObservation() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/disappear-subscribe.rss")!)
    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(feedURL: feedURL, title: "Disappear Subscribe"),
        unsavedEpisodes: [try Create.unsavedEpisode(title: "Episode 1")]
      )
    )
    let viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(savedSeries.podcast))

    viewModel.appear()

    try await Wait.until(
      { @MainActor in viewModel.episodeList.allEntries.count >= 1 },
      { @MainActor in
        "Expected hydration before disappear; entries=\(viewModel.episodeList.allEntries.count)"
      }
    )

    fakeObservatory.clearAllCalls()
    viewModel.disappear()

    viewModel.subscribe()

    try await Wait.until(
      { @MainActor in
        let series = try await self.repo.podcastSeries(savedSeries.id)
        return series?.podcast.subscribed == true
      },
      { @MainActor in
        let series = try await self.repo.podcastSeries(savedSeries.id)
        return """
          Expected subscribe to finish after disappear.
          repo subscribed: \(series?.podcast.subscribed ?? false)
          """
      }
    )

    try await yieldForSpuriousAsyncWork()

    _ = try fakeObservatory.expectCalls(methodName: "podcastSeriesDetail", count: 0)
  }

  @Test("subscribe without appear does not start observation")
  func subscribeWithoutAppearDoesNotStartObservation() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/offscreen-subscribe.rss")!)
    let unsavedSeries = UnsavedPodcastSeries(
      unsavedPodcast: try Create.unsavedPodcast(feedURL: feedURL, title: "Offscreen Subscribe"),
      unsavedEpisodes: [try Create.unsavedEpisode(title: "Episode 1")]
    )
    let viewModel = PodcastDetailViewModel(unsavedPodcastSeries: unsavedSeries)

    fakeObservatory.clearAllCalls()

    viewModel.subscribe()

    try await Wait.until(
      { @MainActor in viewModel.saved },
      { @MainActor in "Expected subscribe to persist series; saved=\(viewModel.saved)" }
    )

    try await yieldForSpuriousAsyncWork()

    _ = try fakeObservatory.expectCalls(methodName: "podcastSeriesDetail", count: 0)
  }

  @Test("disappear cancels observation after appear")
  func disappearCancelsObservationAfterAppear() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/disappear-observation.rss")!)
    let imageURL = try #require(URL(string: "https://example.com/disappear-observation-image.png"))
    await feedSession.respond(
      to: feedURL.rawValue,
      data: PreviewBundle.loadAsset(named: "hardfork_short", in: .FeedRSS)
    )
    fakeDataLoader.respond(
      to: imageURL,
      data: FakeDataLoader.createSolidColor(.green).pngData()!
    )

    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(
          feedURL: feedURL,
          title: "Disappear Observation",
          image: imageURL
        ),
        unsavedEpisodes: [try Create.unsavedEpisode(title: "Episode 1")]
      )
    )
    let viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(savedSeries.podcast))

    viewModel.appear()

    try await Wait.until(
      { @MainActor in viewModel.episodeList.allEntries.count >= 1 },
      { @MainActor in
        "Expected hydration before disappear; entries=\(viewModel.episodeList.allEntries.count)"
      }
    )

    let entryCountBeforeDisappear = viewModel.episodeList.allEntries.count
    let titleBeforeDisappear = viewModel.podcast.title

    viewModel.disappear()

    _ = try await RecommendationHelpers.addEpisodes(to: savedSeries.podcast, count: 1)

    try await yieldForSpuriousAsyncWork()

    #expect(viewModel.episodeList.allEntries.count == entryCountBeforeDisappear)
    #expect(viewModel.podcast.title == titleBeforeDisappear)
  }

  @Test("disappear cancels an in-flight share-artwork load")
  func disappearCancelsInFlightShareArtworkLoad() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/disappear-artwork.rss")!)
    let imageURL = try #require(URL(string: "https://example.com/disappear-artwork-image.png"))
    await feedSession.respond(
      to: feedURL.rawValue,
      data: PreviewBundle.loadAsset(named: "hardfork_short", in: .FeedRSS)
    )
    let fetchStarted = AsyncSemaphore(value: 0)
    let fetchHang = AsyncSemaphore(value: 0)
    let cancelObserved = ThreadSafe(false)
    fakeDataLoader.respond(to: imageURL) { _ in
      fetchStarted.signal()
      do {
        try await fetchHang.waitUnlessCancelled()
      } catch {
        cancelObserved(true)
        throw error
      }
      return Data()
    }

    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(
          feedURL: feedURL,
          title: "Disappear Artwork",
          image: imageURL
        )
      )
    )
    let viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(savedSeries.podcast))

    viewModel.appear()
    await fetchStarted.wait()

    viewModel.disappear()

    try await Wait.until(
      { cancelObserved() },
      { "Expected disappear() to cancel the in-flight share-artwork load." }
    )
  }

  @Test("appear loads share artwork once, idempotent on repeat")
  func appearLoadsShareArtworkIdempotently() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/appear-artwork.rss")!)
    let imageURL = try #require(URL(string: "https://example.com/appear-artwork-image.png"))
    await feedSession.respond(
      to: feedURL.rawValue,
      data: PreviewBundle.loadAsset(named: "hardfork_short", in: .FeedRSS)
    )
    let imageData = FakeDataLoader.createSolidColor(.red).pngData()!
    let loadCount = ThreadSafe(0)
    fakeDataLoader.respond(to: imageURL) { _ in
      loadCount { $0 += 1 }
      return imageData
    }

    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(
          feedURL: feedURL,
          title: "Appear Artwork",
          image: imageURL
        )
      )
    )
    let viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(savedSeries.podcast))

    viewModel.appear()

    try await Wait.until(
      { loadCount() >= 1 },
      { "Expected appear to load share artwork; loadCount=\(loadCount())" }
    )
    // loadCount increments when the fetch completes; yield so the appear task
    // can set loadedShareArtworkURL before a repeat appear is allowed to run.
    try await yieldForSpuriousAsyncWork()
    #expect(loadCount() == 1)
    #expect(fakeDataLoader.loadedURLs().contains(imageURL))

    // A second appear must short-circuit on the now-populated shareArtwork.
    viewModel.appear()
    try await yieldForSpuriousAsyncWork()

    #expect(loadCount() == 1)
  }

  @Test("appear-time transition does not cancel the in-flight share-artwork load")
  func appearTransitionDoesNotCancelShareArtworkLoad() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/appear-episodes-artwork.rss")!)
    let imageURL = try #require(
      URL(string: "https://example.com/appear-episodes-artwork-image.png")
    )
    await feedSession.respond(
      to: feedURL.rawValue,
      data: PreviewBundle.loadAsset(named: "hardfork_short", in: .FeedRSS)
    )
    let fetchStarted = AsyncSemaphore(value: 0)
    let fetchHang = AsyncSemaphore(value: 0)
    let cancelObserved = ThreadSafe(false)
    fakeDataLoader.respond(to: imageURL) { _ in
      fetchStarted.signal()
      do {
        try await fetchHang.waitUnlessCancelled()
      } catch {
        cancelObserved(true)
        throw error
      }
      return Data()
    }

    // init seeds `.saved(podcast)` with no episodes; the appear-time observation
    // transition swaps in the episode-bearing series and re-enters
    // loadShareArtworkIfNeeded() while the first artwork load is still in flight.
    // That re-entry must reuse the in-flight load, not cancel and restart it.
    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(
          feedURL: feedURL,
          title: "Appear Episodes Artwork",
          image: imageURL
        ),
        unsavedEpisodes: [try Create.unsavedEpisode(title: "Episode 1")]
      )
    )
    let viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(savedSeries.podcast))

    viewModel.appear()
    await fetchStarted.wait()

    try await Wait.until(
      { @MainActor in viewModel.episodeList.allEntries.count >= 1 },
      { @MainActor in
        """
        Expected the appear-time transition to hydrate episodes.
        entries: \(viewModel.episodeList.allEntries.count)
        """
      }
    )
    try await yieldForSpuriousAsyncWork()

    #expect(cancelObserved() == false)

    viewModel.disappear()
  }

  @Test("subscribe off-screen then appear resyncs saved episode rows")
  func subscribeOffScreenThenAppearResyncsSavedEpisodeRows() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/resync-subscribe.rss")!)
    let unsavedSeries = UnsavedPodcastSeries(
      unsavedPodcast: try Create.unsavedPodcast(feedURL: feedURL, title: "Resync Subscribe"),
      unsavedEpisodes: [try Create.unsavedEpisode(title: "Episode 1")]
    )
    let viewModel = PodcastDetailViewModel(unsavedPodcastSeries: unsavedSeries)

    #expect(viewModel.episodeList.allEntries.allSatisfy { $0.episodeID == nil })

    viewModel.subscribe()

    try await Wait.until(
      { @MainActor in viewModel.saved },
      { @MainActor in "Expected subscribe to persist series; saved=\(viewModel.saved)" }
    )

    #expect(viewModel.episodeList.allEntries.allSatisfy { $0.episodeID == nil })

    try await PodcastDetailTestHelpers.appear(viewModel)

    #expect(viewModel.episodeList.allEntries.allSatisfy { $0.episodeID != nil })
  }

  @Test("appear does not auto-refresh a saved series from RSS")
  func appearDoesNotAutoRefreshSavedSeries() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/no-auto-refresh.rss")!)
    await feedSession.respond(
      to: feedURL.rawValue,
      data: PreviewBundle.loadAsset(named: "hardfork_short", in: .FeedRSS)
    )

    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(feedURL: feedURL, title: "No Auto Refresh"),
        unsavedEpisodes: [try Create.unsavedEpisode(title: "Episode 1")]
      )
    )

    let viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(savedSeries.podcast))

    try await PodcastDetailTestHelpers.appear(viewModel)

    let requestsAfterAppear = await feedSession.requests.filter { $0 == feedURL.rawValue }.count
    #expect(requestsAfterAppear == 0)

    viewModel.disappear()
    try await PodcastDetailTestHelpers.appear(viewModel)

    let requestsAfterReappear = await feedSession.requests.filter { $0 == feedURL.rawValue }.count
    #expect(requestsAfterReappear == 0)
  }

  @Test("saved refresh does not fetch the full podcast series")
  func savedRefreshDoesNotFetchFullPodcastSeries() async throws {
    let data = PreviewBundle.loadAsset(named: "hardfork_short", in: .FeedRSS)
    let feed = try await PodcastFeed.parse(
      data,
      from: FeedURL(URL(string: "https://example.com/lazy-manual-refresh.rss")!)
    )
    let savedSeries = try await repo.insertSeries(feed.toUnsavedSeries())
    await feedSession.respond(to: savedSeries.podcast.feedURL.rawValue, data: data)

    let viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(savedSeries.podcast))
    try await PodcastDetailTestHelpers.appear(viewModel)

    let fakeRepo = repo as! FakeRepo
    fakeRepo.clearAllCalls()

    await viewModel.refreshSeries()

    let podcastRead = try fakeRepo.expectCall(
      methodName: "podcast",
      parameters: Podcast.ID.self
    )
    #expect(podcastRead.parameters == savedSeries.id)
    try fakeRepo.expectNoCall(methodName: "podcastSeries")
  }

  @Test("getOrCreatePodcastEpisode after disappear does not start observation")
  func getOrCreateAfterDisappearDoesNotStartObservation() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/get-or-create-offscreen.rss")!)
    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(feedURL: feedURL, title: "Get Or Create"),
        unsavedEpisodes: [try Create.unsavedEpisode(title: "Episode 1")]
      )
    )
    let viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(savedSeries.podcast))

    try await PodcastDetailTestHelpers.appear(viewModel)

    try await Wait.until(
      { @MainActor in viewModel.episodeList.allEntries.count >= 1 },
      { @MainActor in
        "Expected hydration before disappear; entries=\(viewModel.episodeList.allEntries.count)"
      }
    )

    fakeObservatory.clearAllCalls()
    viewModel.disappear()

    let listedEpisode = try #require(viewModel.episodeList.allEntries.first)
    _ = try await viewModel.getOrCreatePodcastEpisode(listedEpisode)

    try await yieldForSpuriousAsyncWork()

    _ = try fakeObservatory.expectCalls(methodName: "podcastSeriesDetail", count: 0)
  }

  @Test("post-deletion feed recovery skips when off-screen")
  func postDeletionFeedRecoverySkipsWhenOffScreen() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/deletion-offscreen.rss")!)
    await feedSession.respond(
      to: feedURL.rawValue,
      data: PreviewBundle.loadAsset(named: "hardfork_short", in: .FeedRSS)
    )

    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(feedURL: feedURL, title: "Deletion Offscreen"),
        unsavedEpisodes: [try Create.unsavedEpisode(title: "Episode 1")]
      )
    )
    let viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(savedSeries.podcast))

    try await PodcastDetailTestHelpers.appear(viewModel)

    let requestsBeforeDisappear = await feedSession.requests.filter { $0 == feedURL.rawValue }.count

    viewModel.disappear()
    try await repo.deletePodcast(savedSeries.id)

    try await yieldForSpuriousAsyncWork()

    let requestsAfterDeletion = await feedSession.requests.filter { $0 == feedURL.rawValue }.count
    #expect(requestsAfterDeletion == requestsBeforeDisappear)
  }

  @Test("reappear after off-screen delete reparses feed into unsaved detail")
  func reappearAfterOffScreenDeleteReparsesFeed() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/reappear-after-delete.rss")!)
    await feedSession.respond(
      to: feedURL.rawValue,
      data: PreviewBundle.loadAsset(named: "hardfork_short", in: .FeedRSS)
    )

    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(feedURL: feedURL, title: "Reappear After Delete"),
        unsavedEpisodes: [try Create.unsavedEpisode(title: "Episode 1")]
      )
    )
    let viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(savedSeries.podcast))

    try await PodcastDetailTestHelpers.appear(viewModel)

    let requestsAfterFirstAppear = await feedSession.requests.filter { $0 == feedURL.rawValue }
      .count

    viewModel.disappear()
    try await repo.deletePodcast(savedSeries.id)
    try await yieldForSpuriousAsyncWork()

    try await PodcastDetailTestHelpers.appear(viewModel)

    try await Wait.until(
      { @MainActor in
        viewModel.saved == false
          && viewModel.podcast.loaded != nil
          && viewModel.episodeList.allEntries.isEmpty == false
      },
      { @MainActor in
        """
        Expected reappear after off-screen delete to reparse into unsaved detail.
        saved: \(viewModel.saved)
        podcast: \(viewModel.podcast.toString)
        episode count: \(viewModel.episodeList.allEntries.count)
        """
      }
    )

    let requestsAfterReappear = await feedSession.requests.filter { $0 == feedURL.rawValue }.count
    #expect(requestsAfterReappear > requestsAfterFirstAppear)
  }

  @Test("recommendation sort off-screen does not start scoring")
  func recommendationSortOffScreenDoesNotStartScoring() async throws {
    let embeddable = RecommendationScoringTestHelpers.scoringEmbeddable()
    try await RecommendationScoringTestHelpers.primeEngine(with: embeddable)

    let (targetPodcast, candidateEpisodes) =
      try await RecommendationHelpers
      .createPodcastWithEpisodes(
        count: 4,
        podcastTitle: "Rec Sort Offscreen",
        podcastDescription: "Rec Sort Offscreen",
        episodeDescriptions: ["Episode 0", "Episode 1", "Episode 2", "Episode 3"]
      )
    try await RecommendationHelpers.embedEpisodes(candidateEpisodes, embeddable: embeddable)
    _ = try await RecommendationHelpers.startAndWaitForScores(for: candidateEpisodes)

    let targetIDs = Set(candidateEpisodes.map(\.id))
    try await RecommendationScoringTestHelpers.settleRecommendationEngine()
    fakeRecommendationRepo.clearAllCalls()

    let viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(targetPodcast))

    viewModel.currentSortMethod = .recommendationScore

    await RecommendationScoringTestHelpers.expectNoScopedEmbeddings(
      matching: targetIDs,
      regression: """
        regression: setting the recommendation sort off-screen started a scoring \
        pass. Scoring must only run on demand while the surface is on-screen.
        """
    )
  }

  @Test("overlapping appear does not double feed parse")
  func overlappingAppearDoesNotDoubleFeedParse() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/overlap-appear.rss")!)
    let feedData = PreviewBundle.loadAsset(named: "hardfork_short", in: .FeedRSS)
    let parseStarted = AsyncSemaphore(value: 0)
    let parseFinish = AsyncSemaphore(value: 0)
    await feedSession.respond(to: feedURL.rawValue) { _ in
      parseStarted.signal()
      try await parseFinish.waitUnlessCancelled()
      return (feedData, URL.response(feedURL.rawValue))
    }

    let viewModel = PodcastDetailViewModel(
      podcast: DisplayedPodcast(
        try Create.unsavedPodcast(feedURL: feedURL, title: "Overlap Appear")
      )
    )

    viewModel.appear()
    await parseStarted.wait()
    viewModel.appear()

    parseFinish.signal()

    try await Wait.until(
      { @MainActor in !viewModel.episodeList.allEntries.isEmpty },
      { @MainActor in
        "Expected overlapping appear passes to finish feed hydration; entries=\(viewModel.episodeList.allEntries.count)"
      }
    )

    let parseCount = await feedSession.requests.filter { $0 == feedURL.rawValue }.count
    #expect(parseCount == 1)
  }

  @Test("saved displayed init with empty episodes does not populate episodeList")
  func savedDisplayedInitDoesNotPopulateEmptyEpisodeList() async throws {
    let savedPodcast = try await Create.podcast(title: "Empty Saved Init")
    let viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(savedPodcast))

    #expect(viewModel.episodeList.allEntries.isEmpty)
  }

  @Test("stale on-screen deletion feed parse does not apply after reappear")
  func staleDeletionFeedParseDoesNotApplyAfterReappear() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/stale-deletion-parse.rss")!)
    let feedData = PreviewBundle.loadAsset(named: "hardfork_short", in: .FeedRSS)
    let parseStarted = AsyncSemaphore(value: 0)
    let parseFinish = AsyncSemaphore(value: 0)
    await feedSession.respond(to: feedURL.rawValue) { _ in
      parseStarted.signal()
      try await parseFinish.waitUnlessCancelled()
      return (feedData, URL.response(feedURL.rawValue))
    }

    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(feedURL: feedURL, title: "Stale Deletion Parse"),
        unsavedEpisodes: [try Create.unsavedEpisode(title: "Episode 1")]
      )
    )
    let viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(savedSeries.podcast))

    try await PodcastDetailTestHelpers.appear(viewModel)
    try await Wait.until(
      { @MainActor in viewModel.episodeList.allEntries.count >= 1 },
      { @MainActor in "Expected hydration before deletion recovery" }
    )

    let requestsBeforeDelete = await feedSession.requests.filter { $0 == feedURL.rawValue }.count
    try await repo.deletePodcast(savedSeries.id)
    await parseStarted.wait()

    viewModel.disappear()
    viewModel.appear()
    parseFinish.signal()

    try await Wait.until(
      { @MainActor in
        viewModel.saved == false
          && viewModel.episodeList.allEntries.isEmpty == false
      },
      { @MainActor in
        """
        Expected reappear to own feed hydration after a stale deletion parse.
        saved: \(viewModel.saved)
        entries: \(viewModel.episodeList.allEntries.count)
        """
      }
    )

    let requestsAfterReappear = await feedSession.requests.filter { $0 == feedURL.rawValue }.count
    // The hung deletion-recovery parse may still hit the network once; reappear may
    // parse again. The regression guard is the hydrated unsaved detail above, not
    // request count alone.
    #expect(requestsAfterReappear >= requestsBeforeDelete + 1)
  }

  @Test("delete after disappear removes the podcast from the repo")
  func deleteAfterDisappearRemovesPodcast() async throws {
    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(title: "Delete Offscreen"),
        unsavedEpisodes: [try Create.unsavedEpisode(title: "Episode 1")]
      )
    )
    let viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(savedSeries.podcast))
    try await PodcastDetailTestHelpers.appear(viewModel)

    viewModel.disappear()
    viewModel.delete()

    try await Wait.until(
      { @MainActor in
        let series = try await self.repo.podcastSeries(savedSeries.id)
        return series == nil
      },
      { @MainActor in "Expected off-screen delete to remove the podcast." }
    )
  }

  @Test("updateSettings after disappear persists off-screen")
  func updateSettingsAfterDisappearPersists() async throws {
    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(title: "Settings Offscreen"),
        unsavedEpisodes: [try Create.unsavedEpisode(title: "Episode 1")]
      )
    )
    let viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(savedSeries.podcast))
    try await PodcastDetailTestHelpers.appear(viewModel)

    viewModel.disappear()
    var newSettings = viewModel.settings ?? .defaults
    newSettings.notifyNewEpisodes = true
    viewModel.updateSettings(newSettings)

    try await Wait.until(
      { @MainActor in
        let series = try await self.repo.podcastSeries(savedSeries.id)
        return series?.podcast.notifyNewEpisodes == true
      },
      { @MainActor in
        let series = try await self.repo.podcastSeries(savedSeries.id)
        return """
          Expected off-screen updateSettings to persist.
          notifyNewEpisodes: \(series?.podcast.notifyNewEpisodes ?? false)
          """
      }
    )
  }
}
