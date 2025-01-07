// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

@propertyWrapper
struct OptionalURL: Decodable, Sendable {
  private let value: URL?
  var wrappedValue: URL? { value }
  init(wrappedValue: URL?) { self.value = wrappedValue }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self.value = URL(string: try container.decode(String.self))
  }
}
