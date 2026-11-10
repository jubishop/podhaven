// Copyright Justin Bishop, 2026

import FactoryKit
import GRDB
import Testing

@testable import PodHaven

@Suite("of EpisodesListViewModel cache tests", .container)
@MainActor final class EpisodesListCacheTests {
  @DynamicInjected(\.repo) private var repo

  private struct InjectedRepoError: Error, Sendable {}

  @Test("uncacheSelectedEpisodes leaves cache files alone when bulk unsave throws")
  func uncacheSelectedEpisodesPreservesCacheOnUnsaveFailure() async throws {
    let cachedEpisode = try await CacheHelpers.createCachedEpisode(
      title: "ep1",
      cachedFilename: "ep1.mp3",
      saveInCache: true
    )
    let cachedURL = try #require(cachedEpisode.cachedURL)
    let fileManager = try #require(Container.shared.fileManager() as? FakeFileManager)
    #expect(fileManager.fileExists(at: cachedURL.rawValue))

    let listables = try await repo.db.read { db in
      try ListablePodcastEpisode
        .request(filter: AppDB.noOp, order: Episode.Columns.id.asc)
        .fetchAll(db)
    }
    let viewModel = try await EpisodesListTestHelpers.makeViewModel(title: "Test")
    try await EpisodesListTestHelpers.loadEntries(into: viewModel, episodes: listables)
    EpisodesListTestHelpers.select(viewModel, ids: [cachedEpisode.id])

    let fakeRepo = try #require(repo as? FakeRepo)
    fakeRepo.updateSaveInCacheBulkError(InjectedRepoError())
    fakeRepo.clearAllCalls()

    viewModel.uncacheSelectedEpisodes()

    try await Wait.until(
      { (try? fakeRepo.expectCalls(methodName: "updateSaveInCache")) != nil },
      { "uncacheSelectedEpisodes never invoked updateSaveInCache" }
    )

    // The buggy path keeps going after the throw and runs clearCache, which
    // records updateCachedFilename on its way to clearing the file. Poll for
    // that side effect; a timeout means the early-return fix held.
    do {
      try await Wait.until(
        maxAttempts: 50,
        delay: .milliseconds(20),
        priority: .userInitiated,
        { (try? fakeRepo.expectCalls(methodName: "updateCachedFilename")) != nil },
        { "regression: clearCache ran despite updateSaveInCache throwing" }
      )
      Issue.record("regression: clearCache ran despite updateSaveInCache throwing")
    } catch {
      // Expected timeout under the fixed implementation.
    }

    try fakeRepo.expectNoCall(methodName: "updateCachedFilename")
    #expect(fileManager.fileExists(at: cachedURL.rawValue))

    let final = try #require(try await repo.episode(cachedEpisode.id))
    #expect(final.cachedURL == cachedEpisode.cachedURL)
    #expect(final.cacheStatus == .cached)
    #expect(final.saveInCache)
    #expect(Container.shared.alert().config?.title == "Error")
  }

  @Test("unsaveSelectedEpisodesFromCache alerts when bulk unsave throws")
  func unsaveSelectedEpisodesFromCacheAlertsOnFailure() async throws {
    let cachedEpisode = try await CacheHelpers.createCachedEpisode(
      title: "ep1",
      cachedFilename: "ep1.mp3",
      saveInCache: true
    )
    let viewModel = try await makeViewModelSelecting(cachedEpisode.id)
    let fakeRepo = try #require(repo as? FakeRepo)
    fakeRepo.updateSaveInCacheBulkError(InjectedRepoError())

    viewModel.unsaveSelectedEpisodesFromCache()

    let alert = Container.shared.alert()
    try await Wait.until(
      { @MainActor in alert.config?.title == "Error" },
      { "unsaveSelectedEpisodesFromCache never alerted on the failed unsave" }
    )
    let final = try #require(try await repo.episode(cachedEpisode.id))
    #expect(final.saveInCache)
  }

  @Test("uncacheSelectedEpisodes alerts when clearing a cached file fails")
  func uncacheSelectedEpisodesAlertsOnClearFailure() async throws {
    let cachedEpisode = try await CacheHelpers.createCachedEpisode(
      title: "ep1",
      cachedFilename: "ep1.mp3",
      saveInCache: true
    )
    let cachedURL = try #require(cachedEpisode.cachedURL)
    let fileManager = try #require(Container.shared.fileManager() as? FakeFileManager)
    fileManager.setRemoveItemError(InjectedRepoError(), for: cachedURL.rawValue)
    let viewModel = try await makeViewModelSelecting(cachedEpisode.id)

    viewModel.uncacheSelectedEpisodes()

    let alert = Container.shared.alert()
    try await Wait.until(
      { @MainActor in alert.config?.title == "Error" },
      { "uncacheSelectedEpisodes never alerted on the failed cache clear" }
    )
    #expect(fileManager.fileExists(at: cachedURL.rawValue))
  }

  // MARK: - Helpers

  private func makeViewModelSelecting(_ episodeID: Episode.ID) async throws
    -> EpisodesListViewModel
  {
    let listables = try await repo.db.read { db in
      try ListablePodcastEpisode
        .request(filter: AppDB.noOp, order: Episode.Columns.id.asc)
        .fetchAll(db)
    }
    let viewModel = try await EpisodesListTestHelpers.makeViewModel(title: "Test")
    try await EpisodesListTestHelpers.loadEntries(into: viewModel, episodes: listables)
    EpisodesListTestHelpers.select(viewModel, ids: [episodeID])
    return viewModel
  }
}
