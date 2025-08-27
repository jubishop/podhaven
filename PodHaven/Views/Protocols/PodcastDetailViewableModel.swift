// Copyright Justin Bishop, 2025

import Foundation

@MainActor
protocol PodcastDetailViewableModel:
  EpisodeQueueable,
  QueueableSelectableListModel
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
