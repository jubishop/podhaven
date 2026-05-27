// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

// Regression coverage for the constructor / lifecycle churn that produced
// the 2026-05-27 build-507 watchdog kill (issue #357 item 1). SwiftUI
// re-evaluates `PodcastDetailView`'s destination, so transient
// `PodcastDetailViewModel` instances must not start any long-lived async
// work in `init` — observation and share-artwork loading belong to the
// kept (appeared) model only.
@Suite("of PodcastDetailViewModel lifecycle tests", .container)
@MainActor final class LifecycleTests {
  @DynamicInjected(\.fakeDataLoader) private var fakeDataLoader
  @DynamicInjected(\.repo) private var repo

  @Test("init for a saved displayed podcast does not start an observation task")
  func initForSavedDisplayedPodcastDoesNotStartObservation() async throws {
    let savedPodcast = try await Create.podcast(title: "Saved Init")

    let viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(savedPodcast))

    // Yield repeatedly so any spuriously-started Task gets ample chance
    // to assign `observationTask` before we assert the negative.
    for _ in 0..<20 { await Task.yield() }

    #expect(viewModel.observationTask == nil)
  }

  @Test("init for a listed-podcast bridge does not start an observation task")
  func initForListedPodcastDoesNotStartObservation() async throws {
    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(title: "Listed Init")
      )
    )
    let listablePodcast = try await PodcastDetailTestHelpers.fetchListablePodcast(savedSeries.id)

    let viewModel = PodcastDetailViewModel(listedPodcast: ListedPodcast(saved: listablePodcast))

    for _ in 0..<20 { await Task.yield() }

    #expect(viewModel.observationTask == nil)
  }

  @Test("init for an unsaved podcast does not start an observation task")
  func initForUnsavedPodcastDoesNotStartObservation() async throws {
    let viewModel = PodcastDetailViewModel(
      podcast: DisplayedPodcast(try Create.unsavedPodcast(title: "Unsaved Init"))
    )

    for _ in 0..<20 { await Task.yield() }

    #expect(viewModel.observationTask == nil)
  }

  @Test("init for an unsaved podcast series does not start an observation task")
  func initForUnsavedPodcastSeriesDoesNotStartObservation() async throws {
    let viewModel = PodcastDetailViewModel(
      unsavedPodcastSeries: UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(title: "Series Init")
      )
    )

    for _ in 0..<20 { await Task.yield() }

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
    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(
          feedURL: FeedURL(URL(string: "https://example.com/appear-observation.rss")!),
          title: "Appear Observation"
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
          && viewModel.episodeList.allEntries.count == 1
      },
      { @MainActor in
        """
        Expected performAppear to start observation and hydrate one episode.
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

  @Test("performAppear loads share artwork once, idempotent on repeat")
  func performAppearLoadsShareArtworkIdempotently() async throws {
    let imageURL = try #require(URL(string: "https://example.com/appear-artwork-image.png"))
    let imageData = FakeDataLoader.createSolidColor(.red).pngData()!
    let loadCount = ThreadSafe(0)
    fakeDataLoader.respond(to: imageURL) { _ in
      loadCount { $0 += 1 }
      return imageData
    }

    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(
          feedURL: FeedURL(URL(string: "https://example.com/appear-artwork.rss")!),
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
    for _ in 0..<20 { await Task.yield() }

    #expect(loadCount() == 1)
  }
}
