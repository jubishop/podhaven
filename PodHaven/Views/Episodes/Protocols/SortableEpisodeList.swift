// Copyright Justin Bishop, 2025

import Foundation

@MainActor protocol SortableEpisodeList: AnyObject {
  associatedtype EpisodeType: EpisodeDisplayable
  associatedtype SortMethodType: SortingMethod

  var currentSortMethod: SortMethodType { get set }
  var allSortMethods: [SortMethodType] { get }
}
