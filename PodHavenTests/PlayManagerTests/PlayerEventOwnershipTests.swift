// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import Semaphore
import Testing

@testable import PodHaven

@Suite("of Player event ownership tests", .container)
@MainActor struct PlayerEventOwnershipTests {
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.stateManager) private var stateManager

  private var avPlayer: FakeAVPlayer {
    guard let avPlayer = Container.shared.avPlayer() as? FakeAVPlayer else {
      Assert.fatal("Expected FakeAVPlayer")
    }
    return avPlayer
  }

  init() {
    stateManager.start()
    cacheManager.start()
  }

  @Test("buffered retired failure is ignored before current failure")
  func bufferedRetiredFailureIgnoredBeforeCurrentFailure() async throws {
    let (retiredEpisode, replacementEpisode) = try await Create.twoPodcastEpisodes()
    let fakeQueue = try #require(queue as? FakeQueue)

    try await playManager.load(retiredEpisode)
    let retiredItem = try #require(avPlayer.current as? FakeAVPlayerItem)
    retiredItem.setStatus(.failed)

    try await playManager.load(replacementEpisode)
    let replacementItem = try #require(avPlayer.current as? FakeAVPlayerItem)
    let firstFailedEpisodeID = ThreadSafe<Episode.ID?>(nil)
    let failureHandled = AsyncSemaphore(value: 0)
    let replacementQueued = AsyncSemaphore(value: 0)
    let queueStream = sharedState.$queuedPodcastEpisodes.stream()
    let queueObservationTask = Task {
      for await episodes in queueStream
      where episodes.contains(where: {
        $0.id == replacementEpisode.id
      }) {
        replacementQueued.signal()
        return
      }
    }
    defer { queueObservationTask.cancel() }

    fakeQueue.beforeUnshiftEpisode { episodeID in
      firstFailedEpisodeID(episodeID)
      failureHandled.signal()
    }
    replacementItem.setStatus(.failed)

    playManager.startStreamConsumers()
    await failureHandled.wait()

    try #require(firstFailedEpisodeID() == replacementEpisode.id)
    await replacementQueued.wait()
    #expect(sharedState.onDeck == nil)
  }

  @Test("buffered current time from retired episode cannot update replacement")
  func bufferedCurrentTimeCannotUpdateReplacement() async throws {
    let (retiredEpisode, replacementEpisode) = try await Create.twoPodcastEpisodes()

    try await playManager.load(retiredEpisode)
    let podAVPlayer = Container.shared.podAVPlayer()
    avPlayer.seekHandler = { _ in false }
    await podAVPlayer.seek(to: .seconds(30))

    try await playManager.load(replacementEpisode)
    let replacementTimeApplied = AsyncSemaphore(value: 0)
    let onDeckStream = sharedState.$onDeck.stream()
    let observationTask = Task {
      for await onDeck in onDeckStream where onDeck?.id == replacementEpisode.id {
        guard onDeck?.currentTime == .seconds(5) else { continue }
        replacementTimeApplied.signal()
        return
      }
    }
    defer { observationTask.cancel() }

    playManager.startStreamConsumers()
    await podAVPlayer.seek(to: .seconds(5))
    await replacementTimeApplied.wait()

    #expect(sharedState.onDeck?.id == replacementEpisode.id)
    #expect(sharedState.onDeck?.maxPlaybackTime == .seconds(5))
  }

  @Test("retired control status cannot alter replacement playback state")
  func retiredControlStatusCannotAlterReplacementState() async throws {
    let (retiredEpisode, replacementEpisode) = try await Create.twoPodcastEpisodes()

    try await playManager.load(retiredEpisode)
    let retiredObservation = try #require(avPlayer.statusObservations.last)
    try await playManager.load(replacementEpisode)
    retiredObservation.handler(.playing)

    let observedStatuses = ThreadSafe<[PlaybackStatus]>([])
    let waitingObserved = AsyncSemaphore(value: 0)
    let statusStream = sharedState.$playbackStatus.stream()
    let observationTask = Task {
      for await status in statusStream {
        observedStatuses { $0.append(status) }
        if status == .waiting {
          waitingObserved.signal()
          return
        }
      }
    }
    defer { observationTask.cancel() }

    playManager.startStreamConsumers()
    avPlayer.waitingToPlay()
    await waitingObserved.wait()

    #expect(observedStatuses().contains(.playing) == false)
    #expect(sharedState.onDeck?.id == replacementEpisode.id)
  }

  @Test("retired rate cannot alter replacement playback state")
  func retiredRateCannotAlterReplacementState() async throws {
    let (retiredEpisode, replacementEpisode) = try await Create.twoPodcastEpisodes()

    try await playManager.load(retiredEpisode)
    let retiredObservation = try #require(avPlayer.rateObservations.last)
    try await playManager.load(replacementEpisode)
    retiredObservation.handler(2)

    let currentRate: Float = 1.25
    let observedRates = ThreadSafe<[Float]>([])
    let currentRateObserved = AsyncSemaphore(value: 0)
    let rateStream = sharedState.$playRate.stream()
    let observationTask = Task {
      for await rate in rateStream {
        observedRates { $0.append(rate) }
        if rate == currentRate {
          currentRateObserved.signal()
          return
        }
      }
    }
    defer { observationTask.cancel() }

    playManager.startStreamConsumers()
    avPlayer.setRate(currentRate)
    await currentRateObserved.wait()

    #expect(observedRates().contains(2) == false)
    #expect(sharedState.onDeck?.id == replacementEpisode.id)
  }

  @Test("end notification from retired item cannot finish replacement")
  func retiredEndNotificationCannotFinishReplacement() async throws {
    let notificationSource = AcknowledgingNotificationSource()
    Container.shared.notifications.context(.test) {
      { name in notificationSource.stream(for: name) }
    }

    let (retiredEpisode, replacementEpisode) = try await Create.twoPodcastEpisodes()
    let (nextEpisode, followingEpisode) = try await Create.twoPodcastEpisodes()
    let fakeRepo = try #require(repo as? FakeRepo)
    let endNotification = AVPlayerItem.didPlayToEndTimeNotification

    try await playManager.load(retiredEpisode)
    let retiredItem = try #require(avPlayer.current as? FakeAVPlayerItem)
    await notificationSource.waitForStreamRequest(for: endNotification)

    try await playManager.load(replacementEpisode)
    let replacementItem = try #require(avPlayer.current as? FakeAVPlayerItem)
    await notificationSource.waitForStreamRequest(for: endNotification)
    try await queue.replace([nextEpisode.id, followingEpisode.id])
    let nextEpisodeObserved = AsyncSemaphore(value: 0)
    let followingEpisodeObserved = AsyncSemaphore(value: 0)
    let onDeckStream = sharedState.$onDeck.stream()
    let observationTask = Task {
      for await onDeck in onDeckStream {
        if onDeck?.id == nextEpisode.id {
          nextEpisodeObserved.signal()
        } else if onDeck?.id == followingEpisode.id {
          followingEpisodeObserved.signal()
          return
        }
      }
    }
    defer { observationTask.cancel() }

    nonisolated(unsafe) let retiredNotification = Notification(
      name: endNotification,
      object: retiredItem
    )
    notificationSource.continuation(for: endNotification).yield(retiredNotification)

    nonisolated(unsafe) let replacementNotification = Notification(
      name: endNotification,
      object: replacementItem
    )
    notificationSource.continuation(for: endNotification).yield(replacementNotification)

    fakeRepo.clearAllCalls()
    playManager.startStreamConsumers()
    await nextEpisodeObserved.wait()
    await notificationSource.waitForStreamRequest(for: endNotification)
    let followingEpisodePlaying = AsyncSemaphore(value: 0)
    let playbackStatusStream = sharedState.$playbackStatus.stream()
    let playbackStatusTask = Task {
      for await status in playbackStatusStream where status == .playing {
        guard sharedState.onDeck?.id == followingEpisode.id else { continue }
        followingEpisodePlaying.signal()
        return
      }
    }
    defer { playbackStatusTask.cancel() }

    let nextItem = try #require(avPlayer.current as? FakeAVPlayerItem)
    nonisolated(unsafe) let nextNotification = Notification(
      name: endNotification,
      object: nextItem
    )
    notificationSource.continuation(for: endNotification).yield(nextNotification)
    await followingEpisodeObserved.wait()
    await followingEpisodePlaying.wait()

    let finishedEpisodeIDs = fakeRepo.calls(of: MethodCall<Episode.ID>.self)
      .filter { $0.methodName == "markFinished" }
      .map(\.parameters)
    #expect(finishedEpisodeIDs == [replacementEpisode.id, nextEpisode.id])
  }
}

private final class AcknowledgingNotificationSource: Sendable {
  private struct Channel {
    let stream: AsyncStream<Notification>
    let continuation: AsyncStream<Notification>.Continuation
  }

  private let channels = ThreadSafe<[Notification.Name: Channel]>([:])
  private let streamRequests = ThreadSafe<[Notification.Name: AsyncSemaphore]>([:])

  func stream(for name: Notification.Name) -> AsyncStream<Notification> {
    let stream = channels { channels in
      let (stream, continuation) = AsyncStream.makeStream(of: Notification.self)
      channels[name] = Channel(stream: stream, continuation: continuation)
      return stream
    }
    streamRequest(for: name).signal()
    return stream
  }

  func continuation(for name: Notification.Name) -> AsyncStream<Notification>.Continuation {
    guard let channel = channels()[name] else {
      Assert.fatal("Notification stream for \(name) was never requested")
    }
    return channel.continuation
  }

  func waitForStreamRequest(for name: Notification.Name) async {
    await streamRequest(for: name).wait()
  }

  private func streamRequest(for name: Notification.Name) -> AsyncSemaphore {
    streamRequests { requests in
      if let request = requests[name] {
        return request
      }
      let request = AsyncSemaphore(value: 0)
      requests[name] = request
      return request
    }
  }
}
