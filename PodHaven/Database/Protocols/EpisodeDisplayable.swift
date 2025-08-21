// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

protocol EpisodeDisplayable: Hashable, Identifiable, Searchable {
  var title: String { get }
  var pubDate: Date { get }
  var duration: CMTime { get set }
  var cached: Bool { get }
  var completed: Bool { get }
}
