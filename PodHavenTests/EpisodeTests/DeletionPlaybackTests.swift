// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Semaphore
import Testing

@testable import PodHaven

@Suite("of Episode deletion playback ownership", .container)
@MainActor struct EpisodeDeletionPlaybackTests {
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.sharedState) private var sharedState

  init() {
    PlayHelpers.setupCommandHandling()
  }

  @Test("deletion owns cleanup of a suspended target playback load")
  func deletionOwnsCleanupOfSuspendedTargetPlaybackLoad() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode()]
      )
    )
    let episode = try #require(series.episodes.first)
    let podcastEpisode = PodcastEpisode(podcast: series.podcast, episode: episode)
    let queuedEpisode = try await Create.podcastEpisode()
    try await queue.unshift(queuedEpisode.id)
    #expect(try await queue.nextEpisode?.id == queuedEpisode.id)
    let fakeRepo = try #require(repo as? FakeRepo)
    fakeRepo.pendingPodcastEpisodeFetchSuspend(true)

    let playManager = self.playManager
    let pendingPlay = Task { try await playManager.play(podcastEpisode) }
    defer { pendingPlay.cancel() }
    try await fakeRepo.waitForPodcastEpisodeFetchSuspended()
    #expect(sharedState.onDeck == nil)

    #expect(try await repo.deletePodcast(series.podcast.id))
    await fakeRepo.resumeAllPodcastEpisodeFetchSuspensions()
    await #expect(throws: CancellationError.self) {
      try await pendingPlay.value
    }

    #expect(try await queue.nextEpisode?.id == queuedEpisode.id)
    #expect(sharedState.onDeck == nil)
    #expect(sharedState.currentEpisodeID == nil)
    #expect(sharedState.playbackStatus == .stopped)
    try await PlayHelpers.waitForNoCurrentItem()
  }

  @Test("deletion preserves a newer unrelated play already in preflight")
  func deletionPreservesNewerUnrelatedPlayInPreflight() async throws {
    let targetSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode()]
      )
    )
    let targetEpisode = try #require(targetSeries.episodes.first)
    let target = PodcastEpisode(podcast: targetSeries.podcast, episode: targetEpisode)
    let replacement = try await Create.podcastEpisode()
    let avPlayer = try #require(Container.shared.avPlayer() as? FakeAVPlayer)
    try await playManager.play(target)
    try await PlayHelpers.waitFor(.playing)

    PlayHelpers.failAudioSessionConfiguration()

    let playManager = self.playManager
    let replacementPlay = Task { try await playManager.play(replacement) }
    defer { replacementPlay.cancel() }
    try await PlayHelpers.waitForFailedAudioSessionConfigurationAttempt()
    #expect(sharedState.currentEpisodeID == target.id)

    #expect(try await repo.deletePodcast(targetSeries.podcast.id))
    try await PlayHelpers.recoverAudioSessionConfiguration()
    _ = try await replacementPlay.value

    try await PlayHelpers.waitForOnDeck(replacement)
    try await PlayHelpers.waitForCurrentItem(replacement.episode.mediaURL)
    #expect(avPlayer.timeControlStatus == .playing)
    try await PlayHelpers.waitFor(.playing)
  }
}
