// Copyright Justin Bishop, 2025 

import Foundation

protocol EpisodeFilterable {
  var started: Bool { get }
  var completed: Bool { get }
  var queued: Bool { get }
}
