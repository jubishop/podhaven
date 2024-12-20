// Copyright Justin Bishop, 2024

import AVFoundation
import GRDB

extension CMTime: Codable, @retroactive DatabaseValueConvertible {
  // MARK: - Static Methods

  static func inSeconds(_ seconds: Double) -> CMTime {
    CMTime(seconds: seconds, preferredTimescale: 60)
  }

  // MARK: - Codable

  enum CodingKeys: String, CodingKey {
    case seconds
    case timescale
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(seconds, forKey: .seconds)
    try container.encode(timescale, forKey: .timescale)
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let seconds = try container.decode(Double.self, forKey: .seconds)
    let timescale = try container.decode(Int32.self, forKey: .timescale)
    self = CMTime(seconds: seconds, preferredTimescale: timescale)
  }

  // Mark: - DatabaseValueConvertible

  public var databaseValue: DatabaseValue { seconds.databaseValue }

  public static func fromDatabaseValue(_ dbValue: DatabaseValue) -> Self? {
    guard let value = Double.fromDatabaseValue(dbValue) else { return nil }
    return CMTime.inSeconds(value)
  }
}
