// Copyright Justin Bishop, 2026

import AVFoundation
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

  // MARK: - PodcastEpisodes

  func podcastEpisodes<T: FetchableRecord & Equatable>(
    filter: SQLExpression,
    order: SQLOrdering,
    limit: Int
  ) -> AsyncValueObservation<[T]> {
    recordCall(methodName: "podcastEpisodes(filter:order:limit:)", parameters: limit)
    return observatory.podcastEpisodes(filter: filter, order: order, limit: limit)
  }

  func podcastEpisodes<T: FetchableRecord & Equatable>(
    _ mediaGUIDs: [MediaGUID],
    order: SQLOrdering,
    limit: Int
  ) -> AsyncValueObservation<[T]> {
    recordCall(
      methodName: "podcastEpisodes(mediaGUIDs:order:limit:)",
      parameters: (mediaGUIDs: mediaGUIDs, limit: limit)
    )
    return observatory.podcastEpisodes(mediaGUIDs, order: order, limit: limit)
  }

  // MARK: - Listable PodcastEpisodes

  func listablePodcastEpisodes(
    filter: SQLExpression,
    order: SQLOrdering,
    limit: Int
  ) -> AsyncValueObservation<[ListablePodcastEpisode]> {
    recordCall(methodName: "listablePodcastEpisodes(filter:order:limit:)", parameters: limit)
    return observatory.listablePodcastEpisodes(filter: filter, order: order, limit: limit)
  }

  func listablePodcastEpisodes(
    ids: Set<Episode.ID>
  ) -> AsyncValueObservation<[ListablePodcastEpisode]> {
    recordCall(methodName: "listablePodcastEpisodes(ids:)", parameters: ids)
    return observatory.listablePodcastEpisodes(ids: ids)
  }

  // MARK: - Queue

  func queuedPodcastEpisodes(limit: Int) -> AsyncValueObservation<[ListablePodcastEpisode]> {
    recordCall(methodName: "queuedPodcastEpisodes", parameters: limit)
    return observatory.queuedPodcastEpisodes(limit: limit)
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

  // MARK: - On Deck

  func onDeck(_ episodeID: Episode.ID) -> AsyncValueObservation<OnDeck?> {
    recordCall(methodName: "onDeck", parameters: episodeID)
    return observatory.onDeck(episodeID)
  }

  // MARK: - Singular Observations

  func podcastSeries(_ podcastID: Podcast.ID) -> AsyncValueObservation<PodcastSeries?> {
    recordCall(methodName: "podcastSeries", parameters: podcastID)
    return observatory.podcastSeries(podcastID)
  }

  func episode<T: FetchableRecord & Equatable>(
    _ episodeID: Episode.ID
  ) -> AsyncValueObservation<T?> {
    recordCall(methodName: "episode", parameters: episodeID)
    return observatory.episode(episodeID)
  }

  // MARK: - Recommendations

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

  func candidateGateExclusions() -> AsyncValueObservation<Set<Episode.ID>> {
    recordCall(methodName: "candidateGateExclusions", parameters: ())
    return observatory.candidateGateExclusions()
  }
}
