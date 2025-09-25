// Copyright Justin Bishop, 2025

import AVFoundation
import GRDB

extension CMTime:
  @retroactive Codable,
  @retroactive CustomStringConvertible,
  @retroactive DatabaseValueConvertible
{
  // MARK: - Conversions

  var asDuration: Duration { Duration.seconds(CMTimeGetSeconds(self)) }
  var asTimeInterval: TimeInterval { TimeInterval.seconds(CMTimeGetSeconds(self)) }

  // MARK: - Creation Helpers

  static func milliseconds(_ milliseconds: Double) -> CMTime {
    seconds(milliseconds / 1000)
  }

  static func seconds(_ seconds: Double) -> CMTime {
    CMTime(seconds: seconds, preferredTimescale: 60)
  }

  static func minutes(_ minutes: Double) -> CMTime {
    seconds(minutes * 60)
  }

  // MARK: - CustomStringConvertible

  private var timeComponents: (hours: Int, minutes: Int, seconds: Int)? {
    let totalSeconds = CMTimeGetSeconds(self)
    guard !totalSeconds.isNaN && totalSeconds.isFinite else { return nil }

    let hours = Int(totalSeconds) / 3600
    let minutes = (Int(totalSeconds) % 3600) / 60
    let seconds = Int(totalSeconds) % 60

    return (hours, minutes, seconds)
  }

  public var description: String {
    guard let (hours, minutes, seconds) = timeComponents
    else { return "Unknown" }

    guard hours > 0
    else { return String(format: "%d:%02d", minutes, seconds) }

    return String(format: "%d:%02d:%02d", hours, minutes, seconds)
  }

  var shortDescription: String {
    guard let (hours, minutes, seconds) = timeComponents
    else { return "Unknown" }

    guard hours > 0
    else { return "\(minutes)m \(seconds)s" }

    return "\(hours)h \(minutes)m"
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
