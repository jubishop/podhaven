// Copyright Justin Bishop, 2025

import Foundation

enum EpisodeFilterMethod: String, CaseIterable {
  case all = "All Episodes"
  case unstarted = "Unstarted"
  case unfinished = "Unfinished"
  case unqueued = "Unqueued"

  func filterMethod<T: EpisodeFilterable>(for type: T.Type) -> (T) -> Bool {
    switch self {
    case .all:
      return { _ in true }
    case .unstarted:
      return { !$0.started }
    case .unfinished:
      return { !$0.completed }
    case .unqueued:
      return { !$0.queued }
    }
  }
}

@MainActor
protocol PodcastDetailViewableModel:
  ManagingEpisodes,
  SelectableEpisodeListModel
where EpisodeType: EpisodeDisplayable {
  associatedtype NavigationDestination: Hashable

  var podcast: any PodcastDisplayable { get }
  var subscribable: Bool { get }
  var refreshable: Bool { get }
  var currentFilterMethod: EpisodeFilterMethod { get set }
  var displayAboutSection: Bool { get set }
  var mostRecentEpisodeDate: Date { get }

  func execute() async
  func subscribe()
  func unsubscribe()
  func refreshSeries() async
  func navigationDestination(for episode: EpisodeType) -> NavigationDestination
}
