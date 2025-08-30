// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

protocol EpisodeDisplayable: Identifiable, Searchable, Sendable {
  var mediaGUID: MediaGUID { get }
  var title: String { get }
  var pubDate: Date { get }
  var duration: CMTime { get }
  var image: URL { get }
  var cached: Bool { get }
  var description: String? { get }
  var podcastTitle: String { get }
  var started: Bool { get }
  var completed: Bool { get }
  var queued: Bool { get }
}
