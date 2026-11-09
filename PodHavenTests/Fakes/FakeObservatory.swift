// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Tagged

@testable import PodHaven

struct FakeObservatory: Sendable, FakeCallable, Observing {
  let callOrder = ThreadSafe<Int>(0)
  let callsByType = ThreadSafe<[ObjectIdentifier: [any MethodCalling]]>([:])

  // Optional override for scoringContextInputsWithoutPartialSignals(). Each
  // call pops one entry off the front of the script; once the script is
  // empty the fake falls through to the wrapped real observatory. Tests use
  // this to inject an observation that throws on iteration so the engine's
  // retry loop has something to recover from.
  let scoringContextInputsScript = ThreadSafe<
    [@Sendable () -> AsyncValueObservation<ScoringContextInputs>]
  >([])

  // Same shape as `scoringContextInputsScript` but for podcastEpisodeWithTags.
  let podcastEpisodeWithTagsScript = ThreadSafe<
    [@Sendable (Episode.ID) -> AsyncValueObservation<PodcastEpisodeWithTags?>]
  >([])

  let transcriptionCheckpointScript = ThreadSafe<
    [@Sendable (Episode.ID) -> AsyncValueObservation<TranscriptionCheckpoint?>]
  >([])

  // Same shape as `scoringContextInputsScript` but for podcastSeriesDetail.
  let podcastSeriesDetailScript = ThreadSafe<
    [@Sendable (Podcast.ID) -> AsyncValueObservation<PodcastSeriesDetail?>]
  >([])

  let embeddedCandidateEpisodesScript = ThreadSafe<
    [@Sendable () -> AsyncValueObservation<[CandidateEpisode]>]
  >([])

  let embeddingWorkSignalScript = ThreadSafe<
    [@Sendable () -> AsyncValueObservation<
      (
        latestEpisodeContentUpdate: Date?,
        latestPodcastContentUpdate: Date?
      )
    >]
  >([])

  private struct HeldDelivery: Sendable {
    private struct State: Sendable {
      var armed: DispatchQueue?
      var active: DispatchQueue?
    }

    private let label: String
    private let state = ThreadSafe(State())

    init(label: String) {
      self.label = label
    }

    func holdNext() {
      let queue = DispatchQueue(label: label)
      queue.suspend()
      release()
      state { state in
        state.armed = queue
      }
    }

    func takeArmedQueue() -> DispatchQueue? {
      state { state in
        let queueToUse = state.armed
        state.armed = nil
        state.active = queueToUse
        return queueToUse
      }
    }

    func release() {
      guard
        let queue = state({ state in
          let queueToRelease = state.active ?? state.armed
          state.active = nil
          state.armed = nil
          return queueToRelease
        })
      else { return }
      queue.resume()
    }
  }
  private let heldListablePodcastEpisodes = HeldDelivery(
    label: "FakeObservatory.listablePodcastEpisodes.hold"
  )
  private let heldQueuedPodcastEpisodes = HeldDelivery(
    label: "FakeObservatory.queuedPodcastEpisodes.hold"
  )

  private let observatory: any Observing

  init(_ observatory: any Observing) {
    self.observatory = observatory
  }

  // MARK: - Podcasts

  func podcasts(_ filter: SQLExpression, limit: Int) -> AsyncValueObservation<[Podcast]> {
    recordCall(methodName: "podcasts(filter:limit:)", parameters: limit)
    return observatory.podcasts(filter, limit: limit)
  }

  func podcasts(_ feedURLs: [FeedURL], limit: Int) -> AsyncValueObservation<[Podcast]> {
    recordCall(
      methodName: "podcasts(feedURLs:limit:)",
      parameters: (feedURLs: feedURLs, limit: limit)
    )
    return observatory.podcasts(feedURLs, limit: limit)
  }

  func podcastCounts() -> AsyncValueObservation<PodcastCounts> {
    recordCall(methodName: "podcastCounts", parameters: ())
    return observatory.podcastCounts()
  }

  func podcastsWithEpisodeMetadata(
    _ filter: @escaping PodcastFilter,
    limit: Int
  ) -> AsyncValueObservation<[PodcastWithEpisodeMetadata<Podcast>]> {
    recordCall(methodName: "podcastsWithEpisodeMetadata(filter:limit:)", parameters: limit)
    return observatory.podcastsWithEpisodeMetadata(filter, limit: limit)
  }

  func podcastsWithEpisodeMetadata(
    _ feedURLs: [FeedURL],
    iTunesIDs: [ITunesPodcastID],
    limit: Int
  ) -> AsyncValueObservation<[PodcastWithEpisodeMetadata<Podcast>]> {
    recordCall(
      methodName: "podcastsWithEpisodeMetadata(feedURLs:iTunesIDs:limit:)",
      parameters: (feedURLs: feedURLs, iTunesIDs: iTunesIDs, limit: limit)
    )
    return observatory.podcastsWithEpisodeMetadata(feedURLs, iTunesIDs: iTunesIDs, limit: limit)
  }

  // MARK: - Listable Podcasts

  func listablePodcastsWithEpisodeMetadata(
    _ filter: @escaping PodcastFilter,
    limit: Int
  ) -> AsyncValueObservation<[PodcastWithEpisodeMetadata<ListablePodcast>]> {
    recordCall(
      methodName: "listablePodcastsWithEpisodeMetadata(filter:limit:)",
      parameters: limit
    )
    return observatory.listablePodcastsWithEpisodeMetadata(filter, limit: limit)
  }

  func listablePodcastsWithEpisodeMetadata(
    _ feedURLs: [FeedURL],
    iTunesIDs: [ITunesPodcastID],
    limit: Int
  ) -> AsyncValueObservation<[PodcastWithEpisodeMetadata<ListablePodcast>]> {
    recordCall(
      methodName: "listablePodcastsWithEpisodeMetadata(feedURLs:iTunesIDs:limit:)",
      parameters: (feedURLs: feedURLs, iTunesIDs: iTunesIDs, limit: limit)
    )
    return observatory.listablePodcastsWithEpisodeMetadata(
      feedURLs,
      iTunesIDs: iTunesIDs,
      limit: limit
    )
  }

  // MARK: - Listable PodcastEpisodes

  func listablePodcastEpisodes(
    filter: SQLExpression,
    order: SQLOrdering?,
    limit: Int
  ) -> SettledPlaybackObservation<[ListablePodcastEpisode]> {
    recordCall(methodName: "listablePodcastEpisodes(filter:order:limit:)", parameters: limit)
    if let queue = heldListablePodcastEpisodes.takeArmedQueue() {
      return listablePodcastEpisodes(filter: filter, order: order, limit: limit, deliveredOn: queue)
    }
    return observatory.listablePodcastEpisodes(filter: filter, order: order, limit: limit)
  }

  func holdNextListablePodcastEpisodesDelivery() {
    heldListablePodcastEpisodes.holdNext()
  }

  func releaseHeldListablePodcastEpisodesDelivery() {
    heldListablePodcastEpisodes.release()
  }

  private func listablePodcastEpisodes(
    filter: SQLExpression,
    order: SQLOrdering?,
    limit: Int,
    deliveredOn queue: DispatchQueue
  ) -> SettledPlaybackObservation<[ListablePodcastEpisode]> {
    let db = Container.shared.appDB().unsafeTestDB
    return SettledPlaybackObservation(
      observe: {
        ValueObservation
          .tracking { db in
            try ListablePodcastEpisode
              .request(filter: filter, order: order, limit: limit)
              .fetchAll(db)
          }
          .removeDuplicates()
          .values(in: db, scheduling: .async(onQueue: queue))
      },
      refreshes: { [] }
    )
  }

  // MARK: - Episodes

  func episodeIDs(filter: SQLExpression) -> AsyncValueObservation<[Episode.ID]> {
    recordCall(methodName: "episodeIDs", parameters: ())
    return observatory.episodeIDs(filter: filter)
  }

  // MARK: - Queue

  func queuedPodcastEpisodes(limit: Int) -> SettledPlaybackObservation<[ListablePodcastEpisode]> {
    recordCall(methodName: "queuedPodcastEpisodes", parameters: limit)
    if let queue = heldQueuedPodcastEpisodes.takeArmedQueue() {
      return listablePodcastEpisodes(
        filter: Episode.queued,
        order: Episode.Columns.queueOrder.asc,
        limit: limit,
        deliveredOn: queue
      )
    }
    return observatory.queuedPodcastEpisodes(limit: limit)
  }

  func holdNextQueuedPodcastEpisodesDelivery() {
    heldQueuedPodcastEpisodes.holdNext()
  }

  func releaseHeldQueuedPodcastEpisodesDelivery() {
    heldQueuedPodcastEpisodes.release()
  }

  // MARK: - Tags

  func tags() -> AsyncValueObservation<IdentifiedArrayOf<Tag>> {
    recordCall(methodName: "tags", parameters: ())
    return observatory.tags()
  }

  func podcastCountsByTag() -> AsyncValueObservation<[Tag.ID: Int]> {
    recordCall(methodName: "podcastCountsByTag", parameters: ())
    return observatory.podcastCountsByTag()
  }

  func episodeCountsByTag() -> AsyncValueObservation<[Tag.ID: Int]> {
    recordCall(methodName: "episodeCountsByTag", parameters: ())
    return observatory.episodeCountsByTag()
  }

  // MARK: - Smart Lists

  func smartLists() -> AsyncValueObservation<[SmartList]> {
    recordCall(methodName: "smartLists", parameters: ())
    return observatory.smartLists()
  }

  func smartList(_ id: SmartList.ID) -> AsyncValueObservation<SmartList?> {
    recordCall(methodName: "smartList", parameters: id)
    return observatory.smartList(id)
  }

  func smartListUnreadCounts() -> AsyncValueObservation<[SmartList.ID: Int]> {
    recordCall(methodName: "smartListUnreadCounts", parameters: ())
    return observatory.smartListUnreadCounts()
  }

  // MARK: - On Deck

  func onDeck(_ episodeID: Episode.ID) -> AsyncValueObservation<OnDeck?> {
    recordCall(methodName: "onDeck", parameters: episodeID)
    return observatory.onDeck(episodeID)
  }

  // MARK: - Singular Observations

  func podcastSeriesDetail(_ podcastID: Podcast.ID)
    -> SettledPlaybackObservation<PodcastSeriesDetail?>
  {
    recordCall(methodName: "podcastSeriesDetail", parameters: podcastID)
    var script = podcastSeriesDetailScript()
    if let next = script.first {
      script.removeFirst()
      podcastSeriesDetailScript(script)
      return SettledPlaybackObservation(observe: { next(podcastID) }, refreshes: { [] })
    }
    return observatory.podcastSeriesDetail(podcastID)
  }

  func podcastEpisodeWithTags(_ episodeID: Episode.ID)
    -> SettledPlaybackObservation<PodcastEpisodeWithTags?>
  {
    recordCall(methodName: "podcastEpisodeWithTags", parameters: episodeID)
    var script = podcastEpisodeWithTagsScript()
    if let next = script.first {
      script.removeFirst()
      podcastEpisodeWithTagsScript(script)
      return SettledPlaybackObservation(observe: { next(episodeID) }, refreshes: { [] })
    }
    return observatory.podcastEpisodeWithTags(episodeID)
  }

  func transcript(_ episodeID: Episode.ID) -> AsyncValueObservation<Transcript?> {
    recordCall(methodName: "transcript", parameters: episodeID)
    return observatory.transcript(episodeID)
  }

  func transcriptionCheckpoint(_ episodeID: Episode.ID)
    -> AsyncValueObservation<TranscriptionCheckpoint?>
  {
    recordCall(methodName: "transcriptionCheckpoint", parameters: episodeID)
    var script = transcriptionCheckpointScript()
    if let next = script.first {
      script.removeFirst()
      transcriptionCheckpointScript(script)
      return next(episodeID)
    }
    return observatory.transcriptionCheckpoint(episodeID)
  }

  // MARK: - Recommendations

  func embeddedCandidateEpisodes(filter: SQLExpression) -> AsyncValueObservation<[CandidateEpisode]>
  {
    recordCall(methodName: "embeddedCandidateEpisodes", parameters: ())
    var script = embeddedCandidateEpisodesScript()
    if let next = script.first {
      script.removeFirst()
      embeddedCandidateEpisodesScript(script)
      return next()
    }
    return observatory.embeddedCandidateEpisodes(filter: filter)
  }

  func scoringContextInputsWithoutPartialSignals()
    -> AsyncValueObservation<ScoringContextInputs>
  {
    recordCall(methodName: "scoringContextInputsWithoutPartialSignals", parameters: ())
    var script = scoringContextInputsScript()
    if let next = script.first {
      script.removeFirst()
      scoringContextInputsScript(script)
      return next()
    }
    return observatory.scoringContextInputsWithoutPartialSignals()
  }

  func embeddingWorkSignal() -> AsyncValueObservation<
    (
      latestEpisodeContentUpdate: Date?,
      latestPodcastContentUpdate: Date?
    )
  > {
    recordCall(methodName: "embeddingWorkSignal", parameters: ())
    var script = embeddingWorkSignalScript()
    if let next = script.first {
      script.removeFirst()
      embeddingWorkSignalScript(script)
      return next()
    }
    return observatory.embeddingWorkSignal()
  }
}
