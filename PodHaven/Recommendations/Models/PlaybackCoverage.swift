// Copyright Justin Bishop, 2026

import AVFoundation
import Foundation

// Bitmap that records which `bitWidthSeconds`-wide chunks of an episode the
// user actually heard. The byte buffer is what gets persisted on
// `Episode.playbackCoverage`; coverage feeds the partial-listen
// recommendation signal so episodes the user listened to without rating can
// still influence scoring. Chunk width tracks `PodAVPlayer.playbackTickSeconds`
// so each playback tick lands on a chunk boundary.
struct PlaybackCoverage: Equatable, Sendable {
  static let bitWidthSeconds: Int = PodAVPlayer.playbackTickSeconds

  let durationSeconds: Int
  private(set) var bytes: [UInt8]

  // MARK: - Init

  init(durationSeconds: Int, data: Data? = nil) {
    let bits = Self.bitCount(forDurationSeconds: durationSeconds)
    let expectedByteCount = (bits + 7) / 8
    self.durationSeconds = durationSeconds
    guard let data else {
      self.bytes = [UInt8](repeating: 0, count: expectedByteCount)
      return
    }
    var stored = [UInt8](data)
    if stored.count < expectedByteCount {
      stored.append(contentsOf: [UInt8](repeating: 0, count: expectedByteCount - stored.count))
    } else if stored.count > expectedByteCount {
      stored.removeLast(stored.count - expectedByteCount)
    }
    // Canonicalize the final byte: any bits beyond `bits` are padding and
    // must read 0. Otherwise a corrupt blob (or one written under a longer
    // duration) would inflate `coveredSeconds` via the popcount.
    let trailingBits = bits % 8
    if trailingBits > 0, !stored.isEmpty {
      stored[stored.count - 1] &= UInt8((1 << trailingBits) - 1)
    }
    self.bytes = stored
  }

  init(duration: CMTime, data: Data? = nil) {
    self.init(durationSeconds: duration.positiveFiniteSeconds, data: data)
  }

  // MARK: - Mutation

  // Returns true when at least one bit was set, so callers can skip
  // persisting an all-zero bitmap for ranges that fall entirely outside the
  // valid duration (a non-nil zero blob would still satisfy `hasCoverage`).
  @discardableResult
  mutating func mark(startSeconds: Int, endSeconds: Int) -> Bool {
    guard endSeconds > startSeconds else { return false }
    let bits = Self.bitCount(forDurationSeconds: durationSeconds)
    guard bits > 0 else { return false }

    let firstBit = max(0, startSeconds / Self.bitWidthSeconds)
    // End is exclusive; (endSeconds - 1) keeps a range that ends on a chunk
    // boundary from spilling into the next chunk.
    let lastBit = min(bits - 1, (endSeconds - 1) / Self.bitWidthSeconds)
    guard firstBit <= lastBit else { return false }

    for bit in firstBit...lastBit {
      bytes[bit / 8] |= UInt8(1 << (bit % 8))
    }
    return true
  }

  @discardableResult
  mutating func mark(from start: CMTime, to end: CMTime) -> Bool {
    mark(
      startSeconds: start.positiveFiniteSeconds,
      endSeconds: end.positiveFiniteSeconds
    )
  }

  // MARK: - Read

  var data: Data { Data(bytes) }

  var coveredSeconds: Int {
    var setBits = 0
    for byte in bytes {
      setBits += byte.nonzeroBitCount
    }
    return setBits * Self.bitWidthSeconds
  }

  var ratio: Double {
    guard durationSeconds > 0 else { return 0 }
    return min(1.0, Double(coveredSeconds) / Double(durationSeconds))
  }

  // MARK: - Helpers

  private static func bitCount(forDurationSeconds duration: Int) -> Int {
    guard duration > 0 else { return 0 }
    return (duration + bitWidthSeconds - 1) / bitWidthSeconds
  }
}
