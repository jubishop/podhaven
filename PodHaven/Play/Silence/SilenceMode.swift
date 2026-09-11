// Copyright Justin Bishop, 2026

import Foundation
import GRDB

enum SilenceMode: String, Codable, DatabaseValueConvertible, DefaultsStorable, CaseIterable,
  Identifiable, Sendable
{
  case gentle, balanced, aggressive, off

  var id: String { rawValue }
  var title: String { rawValue.capitalized }

  static func resolve(temporary: Self?, podcast: Self?, global: Self) -> Self {
    temporary ?? podcast ?? global
  }
}

struct SilenceOverride: Equatable, Sendable {
  let episodeID: Episode.ID
  let mode: SilenceMode
}

struct SilenceSourceRejection: Equatable, Sendable {
  let episodeID: Episode.ID
  let filename: String
  let generation: String
}

struct QuietInterval: Codable, Equatable, Sendable {
  let start: Double
  let end: Double
}

struct SilencePolicy: Sendable {
  let mode: SilenceMode
  let rate: Double

  var minimumGap: Double {
    let baseline: Double =
      switch mode {
      case .gentle: 1.2
      case .balanced: 0.9
      case .aggressive: 0.65
      case .off: .infinity
      }
    return baseline / sqrt(safeRate)
  }

  var padding: Double {
    let retained: Double =
      switch mode {
      case .gentle: 0.6
      case .balanced: 0.4
      case .aggressive: 0.28
      case .off: .infinity
      }
    return max(0.1, retained / sqrt(safeRate) / 2)
  }

  private var safeRate: Double {
    rate.isFinite && rate > 0 ? rate.clamped(to: 0.8...2.0) : 1
  }

  func cut(in interval: QuietInterval, from time: Double) -> Double? {
    guard mode != .off, time.isFinite,
      interval.start.isFinite, interval.end.isFinite,
      interval.start >= 0, interval.end - interval.start >= minimumGap,
      time >= interval.start + padding,
      (interval.end - padding - time) / safeRate >= 0.15
    else { return nil }
    return interval.end - padding
  }
}
