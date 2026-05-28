// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Semaphore
import Testing

@testable import PodHaven

// Regression coverage for the constructor / lifecycle churn that produced
// the 2026-05-27 build-507 watchdog kill (issue #357 item 1). SwiftUI
// re-evaluates `PodcastDetailView`'s destination, so transient
// `PodcastDetailViewModel` instances must not start any long-lived async
// work in `init` — observation and share-artwork loading belong to the
// kept (appeared) model only.
//
// Regression-proof tests (would fail against pre-fix code): the saved-arm
// observation test and the share-artwork test. The parameterized
// `init(_:) does not start observation` test covers the .initial /
// .unsaved seed shapes — those passed before the fix too (their seed
// has no `savedSeries.id`, so the pre-fix `startObservation(nil)`
// no-op'd) but pinning them keeps the contract honest going forward.
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
  @DynamicInjected(\.podcastFeedSession) private var podcastFeedSession
  @DynamicInjected(\.repo) private var repo

  private var feedSession: FakeDataFetchable { podcastFeedSession as! FakeDataFetchable }

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

  @Test("init for a saved displayed podcast does not start an observation task")
  func initForSavedDisplayedPodcastDoesNotStartObservation() async throws {
    let savedPodcast = try await Create.podcast(title: "Saved Init")

    let viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(savedPodcast))

    try await yieldForSpuriousAsyncWork()

    #expect(viewModel.observationTask == nil)
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
    let viewModel = try await seed.makeViewModel(repo: repo)

    try await yieldForSpuriousAsyncWork()

    #expect(viewModel.observationTask == nil)
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

    // Race: kick off a deliberate load via the same image pipeline and
    // wait for it to complete. If Nuke had time to handle this request,
    // it had time to handle any spurious init-spawned request too — so
    // a still-zero `initLoadCount` afterward is a real negative, not a
    // timing artifact.
    Task {
      _ = try? await Container.shared.imagePipeline().image(for: drainImageURL)
    }
    try await Wait.until(
      { drainLoadCount() == 1 },
      { "Expected drain image to be loaded; drainLoadCount=\(drainLoadCount())" }
    )

    #expect(!fakeDataLoader.loadedURLs().contains(initImageURL))
    #expect(initLoadCount() == 0)
    _ = viewModel  // keep alive until the assertions run
    #expect(viewModel.observationTask == nil)
  }

  @Test("performAppear starts observation for a saved displayed podcast")
  func performAppearStartsObservationForSavedDisplayedPodcast() async throws {
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

    #expect(viewModel.observationTask == nil)

    try await viewModel.performAppear()

    try await Wait.until(
      { @MainActor in
        viewModel.observationTask != nil
          && viewModel.episodeList.allEntries.count >= 1
      },
      { @MainActor in
        """
        Expected performAppear to start observation and hydrate the seeded episode.
        observationTask: \(String(describing: viewModel.observationTask))
        entries: \(viewModel.episodeList.allEntries.count)
        """
      }
    )

    let firstTask = try #require(viewModel.observationTask)
    #expect(!firstTask.isCancelled)

    // A second performAppear must not replace the active observation task.
    try await viewModel.performAppear()

    let secondTask = try #require(viewModel.observationTask)
    #expect(firstTask == secondTask)
  }

  @Test("disappear cancels observation after performAppear")
  func disappearCancelsObservationAfterPerformAppear() async throws {
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

    try await viewModel.performAppear()

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

    try await viewModel.performAppear()
    await fetchStarted.wait()

    viewModel.disappear()

    try await Wait.until(
      { cancelObserved() },
      { "Expected disappear() to cancel the in-flight share-artwork load." }
    )
    #expect(viewModel.auxiliaryTasks.isEmpty)
  }

  @Test("performAppear loads share artwork once, idempotent on repeat")
  func performAppearLoadsShareArtworkIdempotently() async throws {
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

    try await viewModel.performAppear()

    try await Wait.until(
      { loadCount() == 1 },
      { "Expected performAppear to load share artwork once; loadCount=\(loadCount())" }
    )
    #expect(fakeDataLoader.loadedURLs().contains(imageURL))

    // A second performAppear must short-circuit on the now-populated
    // shareArtwork rather than re-issuing the load.
    try await viewModel.performAppear()
    try await yieldForSpuriousAsyncWork()

    #expect(loadCount() == 1)
  }
}
