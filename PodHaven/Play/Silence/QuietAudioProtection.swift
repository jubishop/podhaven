// Copyright Justin Bishop, 2026

import Foundation
import GRDB

enum QuietAudioProtection: String, Codable, DatabaseValueConvertible, DefaultsStorable,
  CaseIterable, Identifiable, Sendable
{
  case high, medium, low

  var id: String { rawValue }
  var title: String { rawValue.capitalized }

  var threshold: Float {
    switch self {
    case .high: 0.001
    case .medium: Float(pow(10, -55.0 / 20))
    case .low: Float(pow(10, -50.0 / 20))
    }
  }

  static func resolve(temporary: Self?, podcast: Self?, global: Self) -> Self {
    temporary ?? podcast ?? global
  }
}

struct QuietAudioProtectionOverride: Equatable, Sendable {
  let episodeID: Episode.ID
  let protection: QuietAudioProtection
}
