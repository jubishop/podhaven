// Copyright Justin Bishop, 2026

import Foundation

@testable import PodHaven

struct FakeAudioFileHasher: AudioFileHashing {
  static let defaultSHA256 =
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

  private let result: String

  init(result: String = Self.defaultSHA256) {
    self.result = result
  }

  func sha256(of _: URL) throws -> String {
    result
  }
}
