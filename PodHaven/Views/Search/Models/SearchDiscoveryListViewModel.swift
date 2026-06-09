// Copyright Justin Bishop, 2026

import Foundation
import IdentifiedCollections

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

  @ObservationIgnored let collector: SearchRecommendationCollector
  @ObservationIgnored let source: SearchRecommendationCollector.Source
  @ObservationIgnored private var backingPickByMediaGUID:
    [MediaGUID: SearchRecommendationCollector.ScoredEpisode] = [:]

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
      // The collector coalesces by mediaGUID first; keep this defensive so a
      // duplicate never trips the uniqueElements precondition at the view edge.
      episodeList.allEntries = IdentifiedArray(
        picks.map { ListedEpisode($0.episode) },
        uniquingIDsWith: { first, _ in first }
      )
    case .loading, .empty:
      backingPickByMediaGUID = [:]
      episodeList.allEntries = []
    }
  }

  // The score that ranked this row; passed along on navigation so the detail
  // view can show it immediately instead of waiting on a fresh scoring pass.
  func similarityScore(for mediaGUID: MediaGUID) -> Float? {
    backingPickByMediaGUID[mediaGUID]?.score
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
