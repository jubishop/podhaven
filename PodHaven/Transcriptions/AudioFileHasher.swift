// Copyright Justin Bishop, 2026

import CryptoKit
import FactoryKit
import Foundation

// MARK: - Container

extension Container {
  func makeAudioFileHasher() -> any AudioFileHashing {
    AudioFileHasher()
  }

  var audioFileHasher: Factory<any AudioFileHashing> {
    Factory(self) { self.makeAudioFileHasher() }.scope(.cached)
  }
}

// MARK: - AudioFileHashing

protocol AudioFileHashing: Sendable {
  func sha256(of fileURL: URL) throws -> String
}

// MARK: - AudioFileHasher

struct AudioFileHasher: AudioFileHashing {
  private static let blockSize = 1_048_576

  fileprivate init() {}

  func sha256(of fileURL: URL) throws -> String {
    let fileHandle = try FileHandle(forReadingFrom: fileURL)
    var hasher = SHA256()

    while true {
      try Task.checkCancellation()
      guard
        let data = try fileHandle.read(upToCount: Self.blockSize),
        !data.isEmpty
      else {
        break
      }
      hasher.update(data: data)
    }

    try fileHandle.close()
    let hexDigits: [Character] = Array("0123456789abcdef")
    return hasher.finalize()
      .reduce(into: "") { result, byte in
        result.append(hexDigits[Int(byte >> 4)])
        result.append(hexDigits[Int(byte & 0x0F)])
      }
  }
}
