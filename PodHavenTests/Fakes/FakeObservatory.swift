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

  // Same shape as `scoringContextInputsScript` but for podcastEpisodeWithTags.
  let podcastEpisodeWithTagsScript = ThreadSafe<
    [@Sendable (Episode.ID) -> AsyncValueObservation<PodcastEpisodeWithTags?>]
  >([])

  // Same shape as `scoringContextInputsScript` but for podcastSeriesDetail.
  let podcastSeriesDetailScript = ThreadSafe<
    [@Sendable (Podcast.ID) -> AsyncValueObservation<PodcastSeriesDetail?>]
  >([])

  let embeddedCandidateEpisodesScript = ThreadSafe<
    [@Sendable () -> AsyncValueObservation<[CandidateEpisode]>]
  >([])

  let episodesNeedingEmbeddingsScript = ThreadSafe<
    [@Sendable (Int) -> AsyncValueObservation<[Episode.ID]>]
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

  // MARK: - Listable PodcastEpisodes

  func listablePodcastEpisodes(
    filter: SQLExpression,
    order: SQLOrdering?,
    limit: Int
  ) -> AsyncValueObservation<[ListablePodcastEpisode]> {
    recordCall(methodName: "listablePodcastEpisodes(filter:order:limit:)", parameters: limit)
    return observatory.listablePodcastEpisodes(filter: filter, order: order, limit: limit)
  }

  // MARK: - Episodes

  func episodeIDs(filter: SQLExpression) -> AsyncValueObservation<[Episode.ID]> {
    recordCall(methodName: "episodeIDs", parameters: ())
    return observatory.episodeIDs(filter: filter)
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

  func episodeCountsByTag() -> AsyncValueObservation<[Tag.ID: Int]> {
    recordCall(methodName: "episodeCountsByTag", parameters: ())
    return observatory.episodeCountsByTag()
  }

  // MARK: - On Deck

  func onDeck(_ episodeID: Episode.ID) -> AsyncValueObservation<OnDeck?> {
    recordCall(methodName: "onDeck", parameters: episodeID)
    return observatory.onDeck(episodeID)
  }

  // MARK: - Singular Observations

  func podcastSeriesDetail(_ podcastID: Podcast.ID)
    -> AsyncValueObservation<PodcastSeriesDetail?>
  {
    recordCall(methodName: "podcastSeriesDetail", parameters: podcastID)
    var script = podcastSeriesDetailScript()
    if let next = script.first {
      script.removeFirst()
      podcastSeriesDetailScript(script)
      return next(podcastID)
    }
    return observatory.podcastSeriesDetail(podcastID)
  }

  func podcastEpisodeWithTags(_ episodeID: Episode.ID)
    -> AsyncValueObservation<PodcastEpisodeWithTags?>
  {
    recordCall(methodName: "podcastEpisodeWithTags", parameters: episodeID)
    var script = podcastEpisodeWithTagsScript()
    if let next = script.first {
      script.removeFirst()
      podcastEpisodeWithTagsScript(script)
      return next(episodeID)
    }
    return observatory.podcastEpisodeWithTags(episodeID)
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

  func episodesNeedingEmbeddings(revision: Int) -> AsyncValueObservation<[Episode.ID]> {
    recordCall(methodName: "episodesNeedingEmbeddings", parameters: revision)
    var script = episodesNeedingEmbeddingsScript()
    if let next = script.first {
      script.removeFirst()
      episodesNeedingEmbeddingsScript(script)
      return next(revision)
    }
    return observatory.episodesNeedingEmbeddings(revision: revision)
  }
}
