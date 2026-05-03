// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import IdentifiedCollections

// Mirror of `Observatory`'s public API. Carved out so tests can stand in a
// `FakeObservatory` (recording calls, scripting throws/values, etc.) the
// same way `Databasing` enables `FakeRepo` and `Queueing` enables
// `FakeQueue`. Callers should depend on `any Observing`, never the
// concrete `Observatory`, so the test seam is consistent.
//
// Each requirement spells out every parameter explicitly because protocol
// requirements can't carry default values. The convenience extension below
// re-introduces the defaults via fewer-parameter overloads that delegate
// down to the requirements.
protocol Observing: Sendable {
  // MARK: - Podcasts

  func podcasts(_ filter: SQLExpression, limit: Int) -> AsyncValueObservation<[Podcast]>
  func podcasts(_ feedURLs: [FeedURL], limit: Int) -> AsyncValueObservation<[Podcast]>
  func podcastCounts() -> AsyncValueObservation<PodcastCounts>
  func podcastsWithEpisodeMetadata(
    _ filter: @escaping PodcastFilter,
    limit: Int
  ) -> AsyncValueObservation<[PodcastWithEpisodeMetadata<Podcast>]>
  func podcastsWithEpisodeMetadata(
    _ feedURLs: [FeedURL],
    iTunesIDs: [ITunesPodcastID],
    limit: Int
  ) -> AsyncValueObservation<[PodcastWithEpisodeMetadata<Podcast>]>

  // MARK: - Listable Podcasts

  func listablePodcastsWithEpisodeMetadata(
    _ filter: @escaping PodcastFilter,
    limit: Int
  ) -> AsyncValueObservation<[PodcastWithEpisodeMetadata<ListablePodcast>]>
  func listablePodcastsWithEpisodeMetadata(
    _ feedURLs: [FeedURL],
    iTunesIDs: [ITunesPodcastID],
    limit: Int
  ) -> AsyncValueObservation<[PodcastWithEpisodeMetadata<ListablePodcast>]>

  // MARK: - PodcastEpisodes

  func podcastEpisodes<T: FetchableRecord & Equatable>(
    filter: SQLExpression,
    order: SQLOrdering,
    limit: Int
  ) -> AsyncValueObservation<[T]>
  func podcastEpisodes<T: FetchableRecord & Equatable>(
    _ mediaGUIDs: [MediaGUID],
    order: SQLOrdering,
    limit: Int
  ) -> AsyncValueObservation<[T]>

  // MARK: - Listable PodcastEpisodes

  func listablePodcastEpisodes(
    filter: SQLExpression,
    order: SQLOrdering,
    limit: Int
  ) -> AsyncValueObservation<[ListablePodcastEpisode]>

  // MARK: - Queue

  func queuedPodcastEpisodes(limit: Int) -> AsyncValueObservation<[ListablePodcastEpisode]>

  // MARK: - Tags

  func tags() -> AsyncValueObservation<IdentifiedArrayOf<Tag>>
  func podcastCountsByTag() -> AsyncValueObservation<[Tag.ID: Int]>

  // MARK: - On Deck

  func onDeck(_ episodeID: Episode.ID) -> AsyncValueObservation<OnDeck?>

  // MARK: - Singular Observations

  func podcastSeries(_ podcastID: Podcast.ID) -> AsyncValueObservation<PodcastSeries?>
  func episode<T: FetchableRecord & Equatable>(
    _ episodeID: Episode.ID
  ) -> AsyncValueObservation<T?>

  // MARK: - Recommendations

  func scoringContextInputsWithoutPartialSignals() -> AsyncValueObservation<ScoringContextInputs>
  func candidateGateExclusions() -> AsyncValueObservation<CandidateGateExclusions>
}

// MARK: - Defaulted Convenience Overloads

// Each overload has a strictly smaller parameter list than its requirement
// so the two coexist as distinct signatures.
extension Observing {
  // Podcasts

  func podcasts(_ filter: SQLExpression) -> AsyncValueObservation<[Podcast]> {
    podcasts(filter, limit: Int.max)
  }

  func podcasts(_ feedURLs: [FeedURL]) -> AsyncValueObservation<[Podcast]> {
    podcasts(feedURLs, limit: Int.max)
  }

  // PodcastsWithEpisodeMetadata (filter form)

  func podcastsWithEpisodeMetadata()
    -> AsyncValueObservation<[PodcastWithEpisodeMetadata<Podcast>]>
  {
    podcastsWithEpisodeMetadata({ $0 }, limit: Int.max)
  }

  func podcastsWithEpisodeMetadata(
    _ filter: @escaping PodcastFilter
  ) -> AsyncValueObservation<[PodcastWithEpisodeMetadata<Podcast>]> {
    podcastsWithEpisodeMetadata(filter, limit: Int.max)
  }

  // PodcastsWithEpisodeMetadata (feedURLs form)

  func podcastsWithEpisodeMetadata(
    _ feedURLs: [FeedURL]
  ) -> AsyncValueObservation<[PodcastWithEpisodeMetadata<Podcast>]> {
    podcastsWithEpisodeMetadata(feedURLs, iTunesIDs: [], limit: Int.max)
  }

  func podcastsWithEpisodeMetadata(
    _ feedURLs: [FeedURL],
    iTunesIDs: [ITunesPodcastID]
  ) -> AsyncValueObservation<[PodcastWithEpisodeMetadata<Podcast>]> {
    podcastsWithEpisodeMetadata(feedURLs, iTunesIDs: iTunesIDs, limit: Int.max)
  }

  func podcastsWithEpisodeMetadata(
    _ feedURLs: [FeedURL],
    limit: Int
  ) -> AsyncValueObservation<[PodcastWithEpisodeMetadata<Podcast>]> {
    podcastsWithEpisodeMetadata(feedURLs, iTunesIDs: [], limit: limit)
  }

  // ListablePodcastsWithEpisodeMetadata (filter form)

  func listablePodcastsWithEpisodeMetadata()
    -> AsyncValueObservation<[PodcastWithEpisodeMetadata<ListablePodcast>]>
  {
    listablePodcastsWithEpisodeMetadata({ $0 }, limit: Int.max)
  }

  func listablePodcastsWithEpisodeMetadata(
    _ filter: @escaping PodcastFilter
  ) -> AsyncValueObservation<[PodcastWithEpisodeMetadata<ListablePodcast>]> {
    listablePodcastsWithEpisodeMetadata(filter, limit: Int.max)
  }

  // ListablePodcastsWithEpisodeMetadata (feedURLs form)

  func listablePodcastsWithEpisodeMetadata(
    _ feedURLs: [FeedURL]
  ) -> AsyncValueObservation<[PodcastWithEpisodeMetadata<ListablePodcast>]> {
    listablePodcastsWithEpisodeMetadata(feedURLs, iTunesIDs: [], limit: Int.max)
  }

  func listablePodcastsWithEpisodeMetadata(
    _ feedURLs: [FeedURL],
    iTunesIDs: [ITunesPodcastID]
  ) -> AsyncValueObservation<[PodcastWithEpisodeMetadata<ListablePodcast>]> {
    listablePodcastsWithEpisodeMetadata(feedURLs, iTunesIDs: iTunesIDs, limit: Int.max)
  }

  func listablePodcastsWithEpisodeMetadata(
    _ feedURLs: [FeedURL],
    limit: Int
  ) -> AsyncValueObservation<[PodcastWithEpisodeMetadata<ListablePodcast>]> {
    listablePodcastsWithEpisodeMetadata(feedURLs, iTunesIDs: [], limit: limit)
  }

  // PodcastEpisodes (filter form)

  func podcastEpisodes<T: FetchableRecord & Equatable>(
    filter: SQLExpression
  ) -> AsyncValueObservation<[T]> {
    podcastEpisodes(filter: filter, order: Episode.Columns.pubDate.desc, limit: Int.max)
  }

  func podcastEpisodes<T: FetchableRecord & Equatable>(
    filter: SQLExpression,
    order: SQLOrdering
  ) -> AsyncValueObservation<[T]> {
    podcastEpisodes(filter: filter, order: order, limit: Int.max)
  }

  func podcastEpisodes<T: FetchableRecord & Equatable>(
    filter: SQLExpression,
    limit: Int
  ) -> AsyncValueObservation<[T]> {
    podcastEpisodes(filter: filter, order: Episode.Columns.pubDate.desc, limit: limit)
  }

  // PodcastEpisodes (mediaGUIDs form)

  func podcastEpisodes<T: FetchableRecord & Equatable>(
    _ mediaGUIDs: [MediaGUID]
  ) -> AsyncValueObservation<[T]> {
    podcastEpisodes(mediaGUIDs, order: Episode.Columns.pubDate.desc, limit: Int.max)
  }

  func podcastEpisodes<T: FetchableRecord & Equatable>(
    _ mediaGUIDs: [MediaGUID],
    order: SQLOrdering
  ) -> AsyncValueObservation<[T]> {
    podcastEpisodes(mediaGUIDs, order: order, limit: Int.max)
  }

  func podcastEpisodes<T: FetchableRecord & Equatable>(
    _ mediaGUIDs: [MediaGUID],
    limit: Int
  ) -> AsyncValueObservation<[T]> {
    podcastEpisodes(mediaGUIDs, order: Episode.Columns.pubDate.desc, limit: limit)
  }

  // ListablePodcastEpisodes

  func listablePodcastEpisodes(
    filter: SQLExpression
  ) -> AsyncValueObservation<[ListablePodcastEpisode]> {
    listablePodcastEpisodes(filter: filter, order: Episode.Columns.pubDate.desc, limit: Int.max)
  }

  func listablePodcastEpisodes(
    filter: SQLExpression,
    order: SQLOrdering
  ) -> AsyncValueObservation<[ListablePodcastEpisode]> {
    listablePodcastEpisodes(filter: filter, order: order, limit: Int.max)
  }

  func listablePodcastEpisodes(
    filter: SQLExpression,
    limit: Int
  ) -> AsyncValueObservation<[ListablePodcastEpisode]> {
    listablePodcastEpisodes(filter: filter, order: Episode.Columns.pubDate.desc, limit: limit)
  }

  // Queue

  func queuedPodcastEpisodes() -> AsyncValueObservation<[ListablePodcastEpisode]> {
    queuedPodcastEpisodes(limit: Int.max)
  }
}
