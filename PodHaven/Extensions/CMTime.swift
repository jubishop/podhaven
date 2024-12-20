// Copyright Justin Bishop, 2024

import AVFoundation

extension CMTime: Codable {
  static func inSeconds(_ seconds: Double) -> CMTime {
    CMTime(seconds: seconds, preferredTimescale: 60)
  }

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
}
