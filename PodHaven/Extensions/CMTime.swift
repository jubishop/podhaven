// Copyright Justin Bishop, 2025

import AVFoundation
import GRDB

extension CMTime:
  Codable,
  @retroactive CustomStringConvertible,
  @retroactive DatabaseValueConvertible
{
  // MARK: - Conversions

  func asDuration() -> Duration {
    Duration.seconds(CMTimeGetSeconds(self))
  }

  func asTimeInterval() -> TimeInterval {
    TimeInterval.seconds(CMTimeGetSeconds(self))
  }

  // MARK: - Creation Helpers

  static func seconds(_ seconds: Double) -> CMTime {
    CMTime(seconds: seconds, preferredTimescale: 60)
  }

  static func minutes(_ minutes: Double) -> CMTime {
    seconds(minutes * 60)
  }

  // MARK: - CustomStringConvertible

  public var description: String {
    let totalSeconds = CMTimeGetSeconds(self)
    guard !totalSeconds.isNaN && totalSeconds.isFinite
    else { return "Unknown" }

    let hours = Int(totalSeconds) / 3600
    let minutes = (Int(totalSeconds) % 3600) / 60
    let seconds = Int(totalSeconds) % 60

    guard hours > 0
    else { return String(format: "%d:%02d", minutes, seconds) }

    return String(format: "%d:%02d:%02d", hours, minutes, seconds)
  }

  // MARK: - Codable

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(seconds)
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = CMTime.seconds(try container.decode(Double.self))
  }

  // MARK: - DatabaseValueConvertible

  public var databaseValue: DatabaseValue {
    if !isValid { return .null }

    return seconds.databaseValue
  }

  public static func fromDatabaseValue(_ dbValue: DatabaseValue) -> CMTime? {
    guard let seconds = Double.fromDatabaseValue(dbValue)
    else { return nil }

    return CMTime.seconds(seconds)
  }
}
