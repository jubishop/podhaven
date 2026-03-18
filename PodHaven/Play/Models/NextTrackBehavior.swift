// Copyright Justin Bishop, 2026

import Foundation

enum NextTrackBehavior: String, Codable, DefaultsStorable, CaseIterable, Identifiable, Sendable {
  case nextEpisode = "Next Episode"
  case skipInterval = "Skip Interval"
  case nextChapter = "Next Chapter"

  var id: String { rawValue }
}
