// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("of AudioFileHasher", .container)
struct AudioFileHasherTests {
  @Test("streams the complete file into a lowercase SHA-256 digest")
  func hashesCompleteFile() throws {
    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    try Data(repeating: 0x61, count: 1_048_577).write(to: fileURL)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let digest = try Container.shared.makeAudioFileHasher().sha256(of: fileURL)

    #expect(digest == "4a3f0c0c213adea174f9a3d4c13177315b588bdb2e9c1012d3d0bf0453ca0f6a")
  }
}
