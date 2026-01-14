// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

@testable import PodHaven

class FakeAVPlayerItem: AVPlayableItem {
  // MARK: - Helper Classes

  struct ObservationHandler<T>: Sendable {
    weak var observation: NSKeyValueObservation?
    let handler: @Sendable (T) -> Void
  }

  // MARK: - State Management

  private var statusObservations: [ObservationHandler<AVPlayerItem.Status>] = []

  private var _status: AVPlayerItem.Status = .unknown {
    didSet {
      // Clean up deallocated observations and call active handlers
      statusObservations = statusObservations.compactMap { observationHandler in
        guard observationHandler.observation != nil else { return nil }
        observationHandler.handler(_status)
        return observationHandler
      }
    }
  }

  let url: URL
  init(url: URL) {
    self.url = url
  }

  // MARK: - AVPlayableItem

  nonisolated var description: String { url.absoluteString }
  var asset: AVAsset { AVURLAsset(url: url) }

  func observeStatus(
    options: NSKeyValueObservingOptions,
    changeHandler: @escaping @Sendable (AVPlayerItem.Status) -> Void
  ) -> NSKeyValueObservation {
    let observation = NSObject().observe(\.description, options: []) { _, _ in }
    statusObservations.append(ObservationHandler(observation: observation, handler: changeHandler))

    if options.contains(.initial) {
      changeHandler(_status)
    }

    return observation
  }

  // MARK: - Testing Manipulators

  func setStatus(_ status: AVPlayerItem.Status) {
    _status = status
  }
}
