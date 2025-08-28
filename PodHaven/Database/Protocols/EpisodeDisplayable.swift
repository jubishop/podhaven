// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

protocol EpisodeDisplayable: Identifiable, Searchable {
  var mediaURL: MediaURL { get }
  var title: String { get }
  var pubDate: Date { get }
  var duration: CMTime { get }
  var image: URL { get }
  var cached: Bool { get }
  var completed: Bool { get }
  var queued: Bool { get }
  var description: String? { get }
  var podcastTitle: String { get }
}
