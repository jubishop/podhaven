// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

@propertyWrapper
struct OptionalURL: Decodable, Hashable, Sendable {
  let wrappedValue: URL?

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    wrappedValue = URL(string: try container.decode(String.self))
  }
}
