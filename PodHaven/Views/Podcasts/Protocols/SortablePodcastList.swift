// Copyright Justin Bishop, 2025

import Foundation

@MainActor protocol SortablePodcastList: AnyObject {
  associatedtype PodcastType: PodcastDisplayable
  associatedtype SortMethodType: SortingMethod

  var currentSortMethod: SortMethodType { get set }
  var allSortMethods: [SortMethodType] { get }
}
