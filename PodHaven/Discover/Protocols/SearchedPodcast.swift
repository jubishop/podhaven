// Copyright Justin Bishop, 2025

import Foundation

protocol SearchedPodcast {
  var searchedText: String { get }
  var unsavedPodcast: UnsavedPodcast { get }
}
