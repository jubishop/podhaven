// Copyright Justin Bishop, 2026

import Foundation

enum NextTrackBehavior: String, Codable, DefaultsStorable, CaseIterable, Identifiable, Sendable {
  case nextEpisode = "Next Episode"
  case skipInterval = "Skip Interval"

  var id: String { rawValue }
}
