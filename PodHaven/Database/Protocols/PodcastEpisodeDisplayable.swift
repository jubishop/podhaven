// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

protocol PodcastEpisodeDisplayable: Hashable, Identifiable {
  var title: String { get }
  var pubDate: Date { get }
  var duration: CMTime { get }
  var cachedFilename: String? { get }
  var image: URL { get }
}
