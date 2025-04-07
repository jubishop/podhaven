// Copyright Justin Bishop, 2025

import Foundation

protocol SearchedPodcast: Hashable {
  var searchedText: String { get }
  var unsavedPodcast: UnsavedPodcast { get }
}
