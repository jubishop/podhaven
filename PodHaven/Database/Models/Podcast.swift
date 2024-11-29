// Copyright Justin Bishop, 2024

import Foundation
import GRDB

struct UnsavedPodcast: Savable {
  let feedURL: URL
  var title: String
}

typealias Podcast = Saved<UnsavedPodcast>
