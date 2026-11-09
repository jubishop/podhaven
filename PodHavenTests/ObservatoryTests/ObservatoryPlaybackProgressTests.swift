// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

// Each observation here shows the playing episode, so a fetch after a playback
// tick would read a new stored position and emit: `removeDuplicates` cannot
// hide it. Counting emissions therefore counts fetches.
@Suite("of Observatory playback progress tests", .container)
actor ObservatoryPlaybackProgressTests {
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.sharedState) private var sharedState

  private final class Emissions<Value: Sendable>: Sendable {
    private let values = ThreadSafe<[Value]>([])

    var all: [Value] { values() }

    func append(_ value: Value) {
      values { $0.append(value) }
    }
  }

  // MARK: - Helpers

  private func record<Value: Sendable>(
    _ observation: some AsyncSequence<Value, any Error> & Sendable,
    into emissions: Emissions<Value>
  ) -> Task<Void, Never> {
    Task {
      do {
        for try await value in observation {
          emissions.append(value)
        }
      } catch is CancellationError {
      } catch {
        Issue.record(error)
      }
    }
  }

  // Already started, so ticks stay off the zero boundary, where flipping
  // `playbackStarted` is a real change that wakes full-episode observations.
  private func makePlayingEpisode() async throws -> PodcastEpisode {
    try await Create.podcastEpisode(
      Create.unsavedEpisode(duration: .seconds(1800), currentTime: .seconds(1))
    )
  }

  private func playTicks(_ episodeID: Episode.ID, through lastSecond: Int) async throws {
    for second in stride(from: 3, through: lastSecond, by: 3) {
      _ = try await repo.updatePlayback(
        episodeID,
        currentTime: .seconds(Double(second)),
        playedFrom: .seconds(Double(second - 3)),
        now: Date()
      )
    }
  }

  private func waitForCount<Value>(_ emissions: Emissions<Value>, _ count: Int) async throws {
    try await Wait.until(
      { emissions.all.count >= count },
      { "Expected \(count) emissions, got \(emissions.all.count)" }
    )
  }

  // MARK: - Playback Ticks

  @Test("updatePlayback causes no listablePodcastEpisodes fetch")
  func listablePodcastEpisodesIgnorePlaybackTicks() async throws {
    let playing = try await makePlayingEpisode()
    let emissions = Emissions<[ListablePodcastEpisode]>()
    let task = record(
      observatory.listablePodcastEpisodes(filter: Episode.Columns.id == playing.id),
      into: emissions
    )
    defer { task.cancel() }
    try await waitForCount(emissions, 1)

    try await playTicks(playing.id, through: 30)
    // Deliveries keep commit order, so a tick that woke the list would emit
    // before the rating change does.
    _ = try await repo.updateRating(playing.id, rating: .liked)

    try await Wait.until(
      { emissions.all.last?.first?.rating == .liked },
      { "Expected the rating change to wake the list" }
    )
    #expect(emissions.all.count == 2)
    #expect(emissions.all.last?.first?.currentTime.seconds == 30)
  }

  @Test("updatePlayback causes no queuedPodcastEpisodes fetch")
  func queuedPodcastEpisodesIgnorePlaybackTicks() async throws {
    let playing = try await makePlayingEpisode()
    try await queue.unshift(playing.id)
    let emissions = Emissions<[ListablePodcastEpisode]>()
    let task = record(observatory.queuedPodcastEpisodes(limit: Int.max), into: emissions)
    defer { task.cancel() }
    try await Wait.until(
      { emissions.all.last?.count == 1 },
      { "Expected the queued episode" }
    )
    let baseline = emissions.all.count

    try await playTicks(playing.id, through: 30)
    _ = try await repo.updateRating(playing.id, rating: .liked)

    try await Wait.until(
      { emissions.all.last?.first?.rating == .liked },
      { "Expected the rating change to wake the queue" }
    )
    #expect(emissions.all.count == baseline + 1)
    #expect(emissions.all.last?.first?.currentTime.seconds == 30)
  }

  @Test("updatePlayback causes no podcastSeriesDetail fetch")
  func podcastSeriesDetailIgnoresPlaybackTicks() async throws {
    let playing = try await makePlayingEpisode()
    let emissions = Emissions<PodcastSeriesDetail?>()
    let task = record(observatory.podcastSeriesDetail(playing.podcast.id), into: emissions)
    defer { task.cancel() }
    try await waitForCount(emissions, 1)

    try await playTicks(playing.id, through: 30)
    _ = try await repo.updateRating(playing.id, rating: .liked)

    try await Wait.until(
      { emissions.all.last??.episodes.first?.rating == .liked },
      { "Expected the rating change to wake the series detail" }
    )
    #expect(emissions.all.count == 2)
    #expect(emissions.all.last??.episodes.first?.currentTime.seconds == 30)
  }

  @Test("updatePlayback causes no podcastEpisodeWithTags fetch")
  func podcastEpisodeWithTagsIgnoresPlaybackTicks() async throws {
    let playing = try await makePlayingEpisode()
    let emissions = Emissions<PodcastEpisodeWithTags?>()
    let task = record(observatory.podcastEpisodeWithTags(playing.id), into: emissions)
    defer { task.cancel() }
    try await waitForCount(emissions, 1)

    try await playTicks(playing.id, through: 30)
    _ = try await repo.updateRating(playing.id, rating: .liked)

    try await Wait.until(
      { emissions.all.last??.podcastEpisode.rating == .liked },
      { "Expected the rating change to wake the episode" }
    )
    #expect(emissions.all.count == 2)
    #expect(emissions.all.last??.podcastEpisode.currentTime.seconds == 30)
  }

  // MARK: - Position Refreshes

  @Test("a settled position save refreshes listed positions")
  func settledPositionRefreshesList() async throws {
    let playing = try await makePlayingEpisode()
    let emissions = Emissions<[ListablePodcastEpisode]>()
    let task = record(
      observatory.listablePodcastEpisodes(filter: Episode.Columns.id == playing.id),
      into: emissions
    )
    defer { task.cancel() }
    try await waitForCount(emissions, 1)

    try await playTicks(playing.id, through: 30)
    _ = try await repo.updateCurrentTime(playing.id, currentTime: .seconds(31))

    try await Wait.until(
      { emissions.all.last?.first?.currentTime.seconds == 31 },
      { "Expected the paused position, got \(emissions.all.map { $0.first?.currentTime })" }
    )
  }

  @Test("a settled position save refreshes the series detail and episode")
  func settledPositionRefreshesDetails() async throws {
    let playing = try await makePlayingEpisode()
    let series = Emissions<PodcastSeriesDetail?>()
    let episode = Emissions<PodcastEpisodeWithTags?>()
    let seriesTask = record(observatory.podcastSeriesDetail(playing.podcast.id), into: series)
    let episodeTask = record(observatory.podcastEpisodeWithTags(playing.id), into: episode)
    defer {
      seriesTask.cancel()
      episodeTask.cancel()
    }
    try await waitForCount(series, 1)
    try await waitForCount(episode, 1)

    _ = try await repo.updateCurrentTime(playing.id, currentTime: .seconds(42))

    try await Wait.until(
      { series.all.last??.episodes.first?.currentTime.seconds == 42 },
      { "Expected the series detail to show the paused position" }
    )
    try await Wait.until(
      { episode.all.last??.podcastEpisode.currentTime.seconds == 42 },
      { "Expected the episode to show the paused position" }
    )
  }

  @Test("changing the current episode refreshes listed positions")
  func currentEpisodeChangeRefreshesList() async throws {
    let outgoing = try await makePlayingEpisode()
    let incoming = try await makePlayingEpisode()
    sharedState.currentEpisodeID = outgoing.id
    let emissions = Emissions<[ListablePodcastEpisode]>()
    let task = record(
      observatory.listablePodcastEpisodes(filter: Episode.Columns.id == outgoing.id),
      into: emissions
    )
    defer { task.cancel() }
    try await waitForCount(emissions, 1)

    try await playTicks(outgoing.id, through: 30)
    sharedState.currentEpisodeID = incoming.id

    try await Wait.until(
      { emissions.all.last?.first?.currentTime.seconds == 30 },
      { "Expected the outgoing episode's last stored position" }
    )
  }
}
