// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

protocol EpisodeDisplayable: Hashable, Identifiable, Searchable {
  var title: String { get }
  var pubDate: Date { get }
  var duration: CMTime { get }
  var image: URL { get }
  var cached: Bool { get }
  var completed: Bool { get }
  var queued: Bool { get }
}
