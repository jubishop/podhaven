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
  @ObservationIgnored @DynamicInjected(\.sharedState) private var sharedState

  nonisolated private static let log = Log.as(LogSubsystem.SearchView.recommendations)

  @ObservationIgnored let collector: SearchRecommendationCollector
  @ObservationIgnored let source: SearchRecommendationCollector.Source
  @ObservationIgnored private var backingPickByMediaGUID: [MediaGUID: ScoredEpisode] = [:]

  // The score that ranked each row; passed along on navigation so the detail
  // view can show it immediately instead of waiting on a fresh scoring pass.
  @ObservationIgnored private(set) var similarityScoreByMediaGUID: [MediaGUID: Float] = [:]

  struct SavedObservationKey: Hashable {
    let removalFeedURL: FeedURL
    let episodeFeedURL: FeedURL
    let mediaGUID: MediaGUID

    var matchingFeedURLs: Set<FeedURL> { [removalFeedURL, episodeFeedURL] }
  }

  struct SavedObservationTaskKey: Hashable {
    let picks: Set<SavedObservationKey>
    let currentEpisodeID: Episode.ID?
  }

  private struct SavedRowLookupKey: Hashable {
    let feedURL: FeedURL
    let mediaGUID: MediaGUID
  }

  // DB rows backing picks that have been saved (e.g. by caching, which keeps
  // the pick listed). Episode uniqueness is per podcast, so keep the backing
  // feed in the key even though the rendered row identity is still mediaGUID.
  @ObservationIgnored private var savedByPickKey: [SavedObservationKey: ListablePodcastEpisode] =
    [:]

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
      backingPickByMediaGUID = Dictionary(
        picks.map { ($0.id, $0) },
        uniquingKeysWith: { first, _ in first }
      )
      similarityScoreByMediaGUID = backingPickByMediaGUID.mapValues(\.score)
      savedByPickKey = savedByPickKey.filter {
        backingPickByMediaGUID[$0.key.mediaGUID]?.feedURL == $0.key.removalFeedURL
      }
      // The collector coalesces by mediaGUID first; keep this defensive so a
      // duplicate never trips the uniqueElements precondition at the view edge.
      episodeList.allEntries = IdentifiedArray(
        picks.map { pick in
          let key = savedObservationKey(for: pick)
          if let saved = savedByPickKey[key] {
            return ListedEpisode(saved)
          }
          return ListedEpisode(pick.episode)
        },
        uniquingIDsWith: { first, _ in first }
      )
    case .loading, .empty:
      backingPickByMediaGUID = [:]
      similarityScoreByMediaGUID = [:]
      savedByPickKey = [:]
      episodeList.allEntries = []
    }
  }

  // MARK: - Saved-Row Observation

  // A Set so a pure score reorder of the same picks doesn't restart the
  // observation; reorder is re-projected by syncEntries.
  private var savedObservationKey: Set<SavedObservationKey> {
    guard case .picks(let picks) = discoveryListState else { return [] }
    return Set(picks.map(savedObservationKey))
  }

  // Keys the restart off `currentEpisodeID`, which moves only on episode
  // transitions; reading `onDeck` here would put every playback tick in the
  // view body's tracked region.
  var savedObservationTaskKey: SavedObservationTaskKey {
    let picks = savedObservationKey
    return SavedObservationTaskKey(
      picks: picks,
      currentEpisodeID: picks.isEmpty ? nil : sharedState.currentEpisodeID
    )
  }

  private func savedObservationKey(
    for pick: ScoredEpisode
  ) -> SavedObservationKey {
    SavedObservationKey(
      removalFeedURL: pick.feedURL,
      episodeFeedURL: pick.episode.feedURL,
      mediaGUID: pick.id
    )
  }

  // Continuously mirrors the DB rows backing the current picks so a pick that
  // becomes saved while staying listed re-renders as `.saved`, with a live
  // episodeID and cacheStatus for the status icons. Rows that stop passing
  // the discovery candidate gate (e.g. queued, rated, played, or finished
  // from the detail screen) drop their pick from the collector instead of
  // staying listed stale. Driven by the view's
  // `.task(id: savedObservationTaskKey)`, which restarts when the pick set
  // or current episode changes and cancels on disappear — a gate broken
  // while this view was covered is caught by the restarted observation's
  // first emission.
  // `savedByPickKey` is intentionally not cleared across restarts so swapped
  // rows don't flicker back to `.unsaved` before the new observation's first
  // emission.
  func observeSavedEpisodes() async {
    // Populate backingPickByMediaGUID before the observation's single
    // up-front emission, in case this task starts before the view's onChange.
    syncEntries(for: discoveryListState)

    let key = savedObservationKey
    guard !key.isEmpty else { return }

    do {
      let guids = Set(key.map(\.mediaGUID.guid))
      var pickKeyBySavedRowKey: [SavedRowLookupKey: SavedObservationKey] = [:]
      for pickKey in key {
        for feedURL in pickKey.matchingFeedURLs {
          let lookupKey = SavedRowLookupKey(feedURL: feedURL, mediaGUID: pickKey.mediaGUID)
          pickKeyBySavedRowKey[lookupKey] = pickKey
        }
      }

      let observation = observatory.listablePodcastEpisodes(
        filter: guids.contains(Episode.Columns.guid)
      )
      for try await listables in observation {
        try Task.checkCancellation()
        // The guid-only SQL filter over-matches: the same (guid, mediaURL) can
        // exist under multiple podcasts, so keep only rows owned by this pick.
        var saved: [SavedObservationKey: ListablePodcastEpisode] = [:]
        for listable in listables {
          let lookupKey = SavedRowLookupKey(
            feedURL: listable.feedURL,
            mediaGUID: listable.mediaGUID
          )
          guard let pickKey = pickKeyBySavedRowKey[lookupKey] else { continue }
          if saved[pickKey] == nil || listable.feedURL == pickKey.episodeFeedURL {
            saved[pickKey] = listable
          }
        }
        let onDeckID = sharedState.onDeck?.id
        for (pickKey, row) in saved
        where !SearchPipelineRunner.isDiscoveryCandidate(row, excludingOnDeck: onDeckID) {
          saved.removeValue(forKey: pickKey)
          collector.removePick(mediaGUID: pickKey.mediaGUID, feedURL: pickKey.removalFeedURL)
        }
        savedByPickKey = saved
        syncEntries(for: discoveryListState)
      }
    } catch is CancellationError {
    } catch {
      Self.log.caughtError("observeSavedEpisodes: observation failed", error)
    }
  }

  // MARK: - ManagingEpisodes

  func didPerformAction(_ episode: ListedEpisode) {
    guard let pick = backingPickByMediaGUID[episode.mediaGUID] else { return }
    collector.removePick(mediaGUID: episode.mediaGUID, feedURL: pick.feedURL)
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
      guard let pick = backingPickByMediaGUID[episode.mediaGUID] else { continue }
      collector.removePick(mediaGUID: episode.mediaGUID, feedURL: pick.feedURL)
    }
  }
}
