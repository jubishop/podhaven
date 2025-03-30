// Copyright Justin Bishop, 2025

import Foundation

protocol PodcastSearchContext {
  var contextLabel: String { get }
  var unsavedPodcast: UnsavedPodcast { get }
}
