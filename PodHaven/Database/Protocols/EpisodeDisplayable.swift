// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

protocol EpisodeDisplayable:
  EpisodeInformable,
  EpisodeListable,
  Sendable
{
  var feedURL: FeedURL { get }
  var podcastTitle: String { get }
}
