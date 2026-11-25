// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("of EpisodeDetailViewModel action tests", .container)
@MainActor final class EpisodeDetailActionTests {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.fakeAudioSession) private var audioSession
  @DynamicInjected(\.fakeEpisodeAssetLoader) private var episodeAssetLoader
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.stateManager) private var stateManager

  private var avPlayer: FakeAVPlayer { Container.shared.avPlayer() as! FakeAVPlayer }
  private var fakeObservatory: FakeObservatory { observatory as! FakeObservatory }
  private var fakeQueue: FakeQueue { queue as! FakeQueue }

  @Test("a shared start time seeks and plays only on the first appear")
  func sharedStartTimeSeeksAndPlaysOnlyOnFirstAppear() async throws {
    stateManager.start()
    PlayHelpers.setupCommandHandling()
    await playManager.start()

    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Shared Start Time"),
        unsavedEpisode: try Create.unsavedEpisode(
          guid: "shared-start-time",
          title: "Shared Start Time"
        )
      )
    )
    let startTime = 120
    let startCMTime = CMTime.seconds(Double(startTime))
    let viewModel = EpisodeDetailViewModel(
      episode: DisplayedEpisode(podcastEpisode),
      startTime: startTime
    )

    viewModel.appear()

    try await PlayHelpers.waitForOnDeck(podcastEpisode)
    try await PlayHelpers.waitFor(.playing)
    #expect(avPlayer.seekRequests.filter { $0 == startCMTime }.count == 1)
    try await PlayHelpers.pause()

    viewModel.disappear()
    fakeObservatory.clearAllCalls()
    viewModel.appear()

    try await Wait.until(
      { @MainActor in
        self.fakeObservatory.allCallsInOrder.contains { $0.methodName == "podcastEpisodeWithTags" }
      },
      { @MainActor in
        """
        Expected the second appear to restart observation.
        calls: \(self.fakeObservatory.allCallsInOrder.map(\.toString))
        """
      }
    )
    try await yieldForSpuriousAsyncWork()

    #expect(avPlayer.seekRequests.filter { $0 == startCMTime }.count == 1)
    #expect(sharedState.playbackStatus == .paused)
  }

  @Test("a shared start time whose playback fails retries on the next appear")
  func sharedStartTimeRetriesOnNextAppearAfterPlaybackFails() async throws {
    stateManager.start()
    PlayHelpers.setupCommandHandling()
    await playManager.start()

    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Shared Start Time Retry"),
        unsavedEpisode: try Create.unsavedEpisode(
          guid: "shared-start-time-retry",
          title: "Shared Start Time Retry"
        )
      )
    )
    let startTime = 120
    let startCMTime = CMTime.seconds(Double(startTime))
    let viewModel = EpisodeDetailViewModel(
      episode: DisplayedEpisode(podcastEpisode),
      startTime: startTime
    )

    await episodeAssetLoader.respond(
      to: podcastEpisode.episode.mediaURL,
      error: TestError.assetLoadFailure(podcastEpisode)
    )
    viewModel.appear()

    try await Wait.until(
      { @MainActor in self.alert.config != nil },
      { @MainActor in "Expected alert after the start-time playback failed" }
    )
    #expect(avPlayer.seekRequests.filter { $0 == startCMTime }.isEmpty)

    await episodeAssetLoader.clearCustomHandler(for: podcastEpisode.episode)
    viewModel.disappear()
    viewModel.appear()

    try await PlayHelpers.waitForOnDeck(podcastEpisode)
    try await PlayHelpers.waitFor(.playing)
    #expect(avPlayer.seekRequests.filter { $0 == startCMTime }.count == 1)
  }

  @Test("a shared start time superseded by other playback does not seek on the next appear")
  func sharedStartTimeSupersededByOtherPlaybackDoesNotSeekOnNextAppear() async throws {
    stateManager.start()
    PlayHelpers.setupCommandHandling()
    await playManager.start()

    let (sharedEpisode, otherEpisode) = try await Create.twoPodcastEpisodes()
    let startTime = 120
    let startCMTime = CMTime.seconds(Double(startTime))
    let viewModel = EpisodeDetailViewModel(
      episode: DisplayedEpisode(sharedEpisode),
      startTime: startTime
    )

    let sharedRelease = await episodeAssetLoader.waitRespond(
      to: sharedEpisode.episode.mediaURL
    )
    defer { sharedRelease.signal() }

    try await LogCapture.withSink { sink in
      viewModel.appear()
      try await PlayHelpers.waitFor(.loading(sharedEpisode.episode.title))

      try await playManager.load(otherEpisode)
      try await Wait.until(
        { @MainActor in sink.captured().contains { $0.message.contains("appear: failed") } },
        { @MainActor in "Expected the superseded start-time appear to finish" }
      )
    }
    try await PlayHelpers.waitForOnDeck(otherEpisode)

    await episodeAssetLoader.clearCustomHandler(for: sharedEpisode.episode)
    viewModel.disappear()
    fakeObservatory.clearAllCalls()
    viewModel.appear()

    try await Wait.until(
      { @MainActor in
        self.fakeObservatory.allCallsInOrder.contains { $0.methodName == "podcastEpisodeWithTags" }
      },
      { @MainActor in
        """
        Expected the second appear to restart observation.
        calls: \(self.fakeObservatory.allCallsInOrder.map(\.toString))
        """
      }
    )
    try await yieldForSpuriousAsyncWork()

    #expect(avPlayer.seekRequests.filter { $0 == startCMTime }.isEmpty)
    #expect(sharedState.onDeck?.id == otherEpisode.id)
  }

  @Test("timestamp playback leaves the prior episode untouched when the target load fails")
  func timestampPlaybackLeavesPriorEpisodeUntouchedWhenTargetLoadFails() async throws {
    stateManager.start()
    PlayHelpers.setupCommandHandling()
    await playManager.start()

    let (priorEpisode, requestedEpisode) = try await Create.twoPodcastEpisodes()
    try await playManager.load(priorEpisode)
    try await PlayHelpers.waitForOnDeck(priorEpisode)
    try await PlayHelpers.waitFor(.paused)

    PlayHelpers.failAudioSessionConfiguration()

    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(requestedEpisode))
    viewModel.playAt(timestamp: "0:10")
    try await PlayHelpers.advanceAudioSessionRetryBackoff()

    try await Wait.until(
      { @MainActor in self.alert.config != nil },
      { @MainActor in "Expected alert after target audio-session configuration failure" }
    )
    try await yieldForSpuriousAsyncWork()

    #expect(sharedState.onDeck?.id == priorEpisode.id)
    #expect(sharedState.playbackStatus == .paused)
    #expect(avPlayer.currentTimeValue == .zero)
    #expect(avPlayer.timeControlStatus == .paused)
  }

  @Test("unsaveEpisodeFromCache clears the saved flag but keeps the cached file")
  func unsaveEpisodeFromCacheKeepsCachedFile() async throws {
    let cachedEpisode = try await CacheHelpers.createCachedEpisode(
      title: "Saved Episode",
      cachedFilename: "saved-episode.mp3",
      saveInCache: true
    )
    let cachedURL = try #require(cachedEpisode.cachedURL)
    let fileManager = try #require(Container.shared.fileManager() as? FakeFileManager)
    #expect(fileManager.fileExists(at: cachedURL.rawValue))

    let podcastEpisode = try #require(try await repo.podcastEpisode(cachedEpisode.id))
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(podcastEpisode))

    viewModel.appear()
    viewModel.unsaveEpisodeFromCache()

    try await Wait.until(
      { @MainActor in viewModel.episode.saveInCache == false },
      { @MainActor in
        "Expected unsaveEpisodeFromCache to clear saveInCache, got \(viewModel.episode.saveInCache)"
      }
    )

    let final = try #require(try await repo.episode(cachedEpisode.id))
    #expect(!final.saveInCache)
    #expect(final.cacheStatus == .cached)
    #expect(fileManager.fileExists(at: cachedURL.rawValue))
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

    viewModel.appear()
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

    let savedEpisode = try await repo.podcastEpisode(
      unsavedPodcastEpisode.mediaGUID,
      feedURL: unsavedPodcastEpisode.feedURL
    )
    #expect(savedEpisode != nil)
    #expect(savedEpisode?.episode.finishDate != nil)
    #expect(savedEpisode?.episode.currentTime == .zero)
  }
}
