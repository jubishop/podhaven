// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Foundation

extension Container {
  var audioFileProvider: Factory<any AudioFileProviding> {
    Factory(self) { AudioFileProvider() }.scope(.cached)
  }
}

struct AudioFileProvider: AudioFileProviding {
  fileprivate init() {}

  func audioFile(forReading url: URL) throws -> any AudioFileReading {
    try AVAudioFile(forReading: url)
  }
}
