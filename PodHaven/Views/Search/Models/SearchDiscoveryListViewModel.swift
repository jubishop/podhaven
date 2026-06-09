// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging

// Backs a single discovery list (one Source). Projects the collector's picks
// for that source into a PowerList so the shared selectable-episode toolbar
// works here too, and drops picks once a consuming action (row or bulk) lands.
// All action plumbing comes from the protocol default implementations; only
// the post-success hooks and pick projection live here.
@Observable @MainActor
final class SearchDiscoveryListViewModel:
  ManagingEpisodes,
  SelectableEpisodeList,
  nonisolated Hashable
{
  typealias EpisodeType = ListedEpisode

  nonisolated static func == (
    lhs: SearchDiscoveryListViewModel,
    rhs: SearchDiscoveryListViewModel
  ) -> Bool {
    lhs === rhs
  }

  nonisolated func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(self))
  }

  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory

  nonisolated private static let log = Log.as(LogSubsystem.SearchView.recommendations)

  @ObservationIgnored let collector: SearchRecommendationCollector
  @ObservationIgnored let source: SearchRecommendationCollector.Source
  @ObservationIgnored private var backingFeedURLByMediaGUID: [MediaGUID: FeedURL] = [:]

  // DB rows backing picks that have been saved (e.g. by caching, which keeps
  // the pick listed). Keyed by mediaGUID: the collector coalesces to one
  // feedURL per mediaGUID, and entries are gated on that pick's feedURL, so
  // there is at most one row per key even though (guid, mediaURL) is only
  // unique per podcast.
  @ObservationIgnored private var savedByMediaGUID: [MediaGUID: ListablePodcastEpisode] = [:]

  var episodeList = PowerList<ListedEpisode>()

  init(collector: SearchRecommendationCollector, source: SearchRecommendationCollector.Source) {
    self.collector = collector
    self.source = source
  }

  // The collector is the source of truth; mirror its current state for this
  // source and keep the PowerList's entries in sync for selection.
  var discoveryListState: SearchRecommendationCollector.DiscoveryListState {
    collector.discoveryListState(for: source)
  }

  func syncEntries(for state: SearchRecommendationCollector.DiscoveryListState) {
    switch state {
    case .picks(let picks):
      backingFeedURLByMediaGUID = Dictionary(
        picks.map { ($0.id, $0.feedURL) },
        uniquingKeysWith: { first, _ in first }
      )
      savedByMediaGUID = savedByMediaGUID.filter {
        backingFeedURLByMediaGUID[$0.key] != nil
      }
      // The collector coalesces by mediaGUID first; keep this defensive so a
      // duplicate never trips the uniqueElements precondition at the view edge.
      episodeList.allEntries = IdentifiedArray(
        picks.map { pick in
          if let saved = savedByMediaGUID[pick.id] {
            return ListedEpisode(saved)
          }
          return ListedEpisode(pick.episode)
        },
        uniquingIDsWith: { first, _ in first }
      )
    case .loading, .empty:
      backingFeedURLByMediaGUID = [:]
      savedByMediaGUID = [:]
      episodeList.allEntries = []
    }
  }

  // MARK: - Saved-Row Observation

  // A Set so a pure score reorder of the same picks doesn't restart the
  // observation; reorder is re-projected by syncEntries.
  var savedObservationKey: Set<MediaGUID> {
    guard case .picks(let picks) = discoveryListState else { return [] }
    return Set(picks.map(\.id))
  }

  // Continuously mirrors the DB rows backing the current picks so a pick that
  // becomes saved while staying listed re-renders as `.saved`, with a live
  // episodeID and cacheStatus for the status icons. Driven by the view's
  // `.task(id: savedObservationKey)`, which restarts when the pick set
  // changes and cancels on disappear. `savedByMediaGUID` is intentionally not
  // cleared across restarts so swapped rows don't flicker back to `.unsaved`
  // before the new observation's first emission.
  func observeSavedEpisodes() async {
    // Populate backingFeedURLByMediaGUID before the observation's single
    // up-front emission, in case this task starts before the view's onChange.
    syncEntries(for: discoveryListState)

    let key = savedObservationKey
    guard !key.isEmpty else { return }

    do {
      let guids = Set(key.map(\.guid))
      let observation = observatory.listablePodcastEpisodes(
        filter: guids.contains(Episode.Columns.guid)
      )
      for try await listables in observation {
        try Task.checkCancellation()
        // The guid-only SQL filter over-matches: the same (guid, mediaURL)
        // can exist under multiple podcasts, so keep only the row from the
        // pick's own feed.
        var saved: [MediaGUID: ListablePodcastEpisode] = [:]
        for listable in listables
        where backingFeedURLByMediaGUID[listable.mediaGUID] == listable.feedURL {
          saved[listable.mediaGUID] = listable
        }
        savedByMediaGUID = saved
        syncEntries(for: discoveryListState)
      }
    } catch is CancellationError {
    } catch {
      Self.log.caughtError("observeSavedEpisodes: observation failed", error)
    }
  }

  // MARK: - ManagingEpisodes

  func didPerformAction(_ episode: ListedEpisode) {
    guard let feedURL = backingFeedURLByMediaGUID[episode.mediaGUID] else { return }
    collector.removePick(mediaGUID: episode.mediaGUID, feedURL: feedURL)
  }

  // MARK: - SelectableEpisodeList

  var selectedPodcastEpisodes: [PodcastEpisode] {
    get async throws {
      let episodes = selectedEpisodes
      var podcastEpisodes = [PodcastEpisode](capacity: episodes.count)
      for episode in episodes {
        podcastEpisodes.append(try await episode.getOrCreatePodcastEpisode())
      }
      return podcastEpisodes
    }
  }

  func didPerformBulkAction(on episodes: [ListedEpisode]) {
    for episode in episodes {
      guard let feedURL = backingFeedURLByMediaGUID[episode.mediaGUID] else { continue }
      collector.removePick(mediaGUID: episode.mediaGUID, feedURL: feedURL)
    }
  }
}
