// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import Semaphore
import Testing

@testable import PodHaven

@Suite("of Seeking tests", .container)
@MainActor struct SeekingTests {
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.fakeEpisodeAssetLoader) private var episodeAssetLoader
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.stateManager) private var stateManager

  private var avPlayer: FakeAVPlayer {
    Container.shared.avPlayer() as! FakeAVPlayer
  }

  init() async throws {
    stateManager.start()
    cacheManager.start()
    PlayHelpers.setupCommandHandling()
  }

  // MARK: - Seeking

  @Test("seeking updates current time")
  func seekingUpdatesCurrentTime() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    let duration = CMTime.seconds(240)
    await episodeAssetLoader.respond(
      to: podcastEpisode.episode.mediaURL,
      data: (true, duration)
    )
    try await playManager.load(podcastEpisode)

    let originalTime = CMTime.seconds(120)
    await playManager.seek(to: originalTime)
    try await PlayHelpers.waitFor(originalTime)
    #expect(PlayHelpers.nowPlayingCurrentTime == originalTime)
    #expect(PlayHelpers.nowPlayingProgress == originalTime.seconds / duration.seconds)

    let skipAmount = Double(30)
    let skipTime = CMTimeAdd(originalTime, CMTime.seconds(skipAmount))
    await playManager.seekForward(skipAmount)
    try await PlayHelpers.waitFor(skipTime)
    #expect(PlayHelpers.nowPlayingCurrentTime == skipTime)
    #expect(PlayHelpers.nowPlayingProgress == skipTime.seconds / duration.seconds)

    let rewindAmount = Double(15)
    let rewindTime = CMTimeSubtract(skipTime, CMTime.seconds(rewindAmount))
    await playManager.seekBackward(rewindAmount)
    try await PlayHelpers.waitFor(rewindTime)
    #expect(PlayHelpers.nowPlayingCurrentTime == rewindTime)
    #expect(PlayHelpers.nowPlayingProgress == rewindTime.seconds / duration.seconds)
  }

  @Test("time update events are ignored while seeking")
  func timeUpdateEventsAreIgnoredWhileSeeking() async throws {
    await playManager.start()
    let (failedEpisode, successfulEpisode) = try await Create.twoPodcastEpisodes()

    try await playManager.load(failedEpisode)

    // After this failed seek, all time advancement is being ignored
    avPlayer.seekHandler = { _ in false }
    let failedSeekTime = CMTime.seconds(60)
    await playManager.seek(to: failedSeekTime)
    #expect(!PlayHelpers.hasPeriodicTimeObservation())

    await episodeAssetLoader.respond(
      to: successfulEpisode.episode.mediaURL,
      data: (true, CMTime.seconds(120))
    )
    try await playManager.load(successfulEpisode)

    // While a seek is in progress, we will ignore time advancement until its success
    let seekSemaphore = AsyncSemaphore(value: 0)
    avPlayer.seekHandler = { _ in
      await seekSemaphore.wait()
      return true
    }
    let successfulSeekTime = CMTimeAdd(failedSeekTime, CMTime.seconds(30))
    await playManager.seek(to: successfulSeekTime)
    #expect(!PlayHelpers.hasPeriodicTimeObservation())

    // Our seek finishes successfully so time advancement observation is back
    seekSemaphore.signal()
    try await PlayHelpers.waitForPeriodicTimeObserver()
    let advancedTime = CMTimeAdd(successfulSeekTime, CMTime.seconds(10))
    avPlayer.advanceTime(to: advancedTime)  // Actually Triggers
    try await PlayHelpers.waitFor(advancedTime)
  }

  @Test("seeking saves current time to database")
  func seekingSavesCurrentTimeToDatabase() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    let duration = CMTime.seconds(240)
    await episodeAssetLoader.respond(
      to: podcastEpisode.episode.mediaURL,
      data: (true, duration)
    )
    try await playManager.load(podcastEpisode)

    var seekTime = CMTime.seconds(120)
    await playManager.seek(to: seekTime)
    try await PlayHelpers.waitFor(seekTime)
    try await PlayHelpers.waitForEpisode(
      podcastEpisode.id,
      attribute: \.currentTime,
      toBe: seekTime
    )

    seekTime = CMTime.seconds(60)
    await playManager.seek(to: seekTime)
    try await PlayHelpers.waitFor(seekTime)
    try await PlayHelpers.waitForEpisode(
      podcastEpisode.id,
      attribute: \.currentTime,
      toBe: seekTime
    )
  }

  @Test("seek cache swap cannot replace a newer episode")
  func seekCacheSwapCannotReplaceNewerEpisode() async throws {
    await playManager.start()
    let (seekingEpisode, incomingEpisode) = try await Create.twoPodcastEpisodes()

    try await playManager.load(seekingEpisode)
    try await repo.updateCachedFilename(
      seekingEpisode.id,
      cachedFilename: "cached-seeking-episode.mp3"
    )
    let updatedSeekingEpisode = try #require(
      try await repo.podcastEpisode(seekingEpisode.id)
    )
    let cachedURL = try #require(updatedSeekingEpisode.episode.cachedURL)
    let swapStarted = AsyncSemaphore(value: 0)
    let finishSwap = AsyncSemaphore(value: 0)
    await episodeAssetLoader.respond(to: cachedURL) { _ in
      swapStarted.signal()
      await finishSwap.wait()
      return (true, .seconds(60))
    }

    let staleSeek = Task { await playManager.seek(to: .seconds(20)) }
    defer {
      staleSeek.cancel()
      finishSwap.signal()
    }
    await swapStarted.wait()

    try await playManager.load(incomingEpisode)
    finishSwap.signal()
    await staleSeek.value

    #expect(PlayHelpers.currentAssetURL == incomingEpisode.episode.mediaURL.rawValue)
    #expect(sharedState.onDeck?.id == incomingEpisode.id)
  }

  @Test("newer seek owns overlapping same-episode cache swap")
  func newerSeekOwnsOverlappingSameEpisodeCacheSwap() async throws {
    try await LogCapture.withSink { sink in
      await playManager.start()
      let podcastEpisode = try await Create.podcastEpisode()
      let originalTime = CMTime.seconds(20)
      let soughtTime = CMTime.seconds(50)

      try await playManager.load(podcastEpisode)
      try await PlayHelpers.play()
      avPlayer.advanceTime(to: originalTime)
      try await PlayHelpers.waitFor(originalTime)
      try await repo.updateCachedFilename(
        podcastEpisode.id,
        cachedFilename: "cached-overlapping-swap.mp3"
      )
      let updatedEpisode = try #require(try await repo.podcastEpisode(podcastEpisode.id))
      let cachedURL = try #require(updatedEpisode.episode.cachedURL)

      let cachedLoadCount = ThreadSafe(0)
      let firstLoadStarted = AsyncSemaphore(value: 0)
      let secondLoadStarted = AsyncSemaphore(value: 0)
      let finishFirstLoad = AsyncSemaphore(value: 0)
      let finishSecondLoad = AsyncSemaphore(value: 0)
      await episodeAssetLoader.respond(to: cachedURL) { _ in
        let loadNumber = cachedLoadCount { count in
          count += 1
          return count
        }
        if loadNumber == 1 {
          firstLoadStarted.signal()
          await finishFirstLoad.wait()
        } else {
          secondLoadStarted.signal()
          await finishSecondLoad.wait()
        }
        return (true, .seconds(60))
      }

      let seekTimes = ThreadSafe<[CMTime]>([])
      avPlayer.seekHandler = { time in
        seekTimes { $0.append(time) }
        return true
      }

      avPlayer.waitingToPlay()
      await firstLoadStarted.wait()
      let seekTask = Task { await playManager.seek(to: soughtTime) }
      defer {
        seekTask.cancel()
        finishFirstLoad.signal()
        finishSecondLoad.signal()
      }
      await secondLoadStarted.wait()

      finishSecondLoad.signal()
      await seekTask.value
      try await Wait.until(
        { @MainActor in avPlayer.currentTimeValue == soughtTime },
        { @MainActor in
          "Expected newer seek at \(soughtTime), got \(avPlayer.currentTimeValue)"
        }
      )
      let soughtItem = try #require(avPlayer.current as? FakeAVPlayerItem)

      finishFirstLoad.signal()
      try await Wait.until(
        {
          let swapLogs = sink.captured()
            .filter {
              $0.label == "Play/avPlayer" && $0.message.contains("swapToCached:")
            }
          let staleSourceRejected = swapLogs.contains {
            $0.message.contains("source retired")
          }
          return swapLogs.count >= 2 && (staleSourceRejected || seekTimes().count >= 2)
        },
        { "Expected both overlapping swaps to finish" }
      )

      #expect((avPlayer.current as? FakeAVPlayerItem) === soughtItem)
      #expect(avPlayer.currentTimeValue == soughtTime)
      #expect(seekTimes() == [soughtTime])
    }
  }

  @Test("newer seek owns overlapping same-episode requests")
  func newerSeekOwnsOverlappingSameEpisodeRequests() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()
    let olderTime = CMTime.seconds(20)
    let newerTime = CMTime.seconds(50)

    try await playManager.load(podcastEpisode)
    try await PlayHelpers.play()
    try await repo.updateCachedFilename(
      podcastEpisode.id,
      cachedFilename: "cached-overlapping-seeks.mp3"
    )
    let updatedEpisode = try #require(try await repo.podcastEpisode(podcastEpisode.id))
    let cachedURL = try #require(updatedEpisode.episode.cachedURL)

    let cachedLoadCount = ThreadSafe(0)
    let olderLoadStarted = AsyncSemaphore(value: 0)
    let newerLoadStarted = AsyncSemaphore(value: 0)
    let finishOlderLoad = AsyncSemaphore(value: 0)
    let finishNewerLoad = AsyncSemaphore(value: 0)
    await episodeAssetLoader.respond(to: cachedURL) { _ in
      let loadNumber = cachedLoadCount { count in
        count += 1
        return count
      }
      if loadNumber == 1 {
        olderLoadStarted.signal()
        await finishOlderLoad.wait()
      } else {
        newerLoadStarted.signal()
        await finishNewerLoad.wait()
      }
      return (true, .seconds(60))
    }

    let olderSeek = Task { await playManager.seek(to: olderTime) }
    defer {
      olderSeek.cancel()
      finishOlderLoad.signal()
      finishNewerLoad.signal()
    }
    await olderLoadStarted.wait()

    let newerSeek = Task { await playManager.seek(to: newerTime) }
    defer { newerSeek.cancel() }
    await newerLoadStarted.wait()

    finishNewerLoad.signal()
    await newerSeek.value
    finishOlderLoad.signal()
    await olderSeek.value

    #expect(avPlayer.seekRequests == [newerTime])
  }

  @Test("seek completion cannot save time to a newer episode")
  func seekCompletionCannotSaveTimeToNewerEpisode() async throws {
    await playManager.start()
    let (seekingEpisode, incomingEpisode) = try await Create.twoPodcastEpisodes()
    let fakeRepo = try #require(repo as? FakeRepo)

    try await playManager.load(seekingEpisode)
    let seekStarted = AsyncSemaphore(value: 0)
    let finishSeek = AsyncSemaphore(value: 0)
    let seekApplied = AsyncSemaphore(value: 0)
    avPlayer.seekHandler = { _ in
      seekStarted.signal()
      await finishSeek.wait()
      return true
    }
    let observer = avPlayer.addPeriodicTimeObserver(
      forInterval: .milliseconds(250),
      queue: nil
    ) { _ in
      seekApplied.signal()
    }
    defer {
      avPlayer.removeTimeObserver(observer)
      finishSeek.signal()
    }

    await playManager.seek(to: .seconds(1))
    await seekStarted.wait()
    try await playManager.load(incomingEpisode)
    fakeRepo.clearAllCalls()

    finishSeek.signal()
    await seekApplied.wait()
    await Task.yield()
    _ = try await repo.episode(incomingEpisode.id)

    try fakeRepo.expectNoCall(methodName: "updateCurrentTime")
    let storedIncomingEpisode = try #require(try await repo.episode(incomingEpisode.id))
    #expect(storedIncomingEpisode.currentTime == .zero)
  }
}
