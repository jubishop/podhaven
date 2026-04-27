// Copyright Justin Bishop, 2026

import AVFoundation
import Foundation

struct PlaybackCoverage: Equatable, Sendable {
  static let bitWidthSeconds: Int = 3

  let durationSeconds: Int
  private(set) var bytes: [UInt8]

  // MARK: - Init

  init(durationSeconds: Int) {
    let bits = Self.bitCount(forDurationSeconds: durationSeconds)
    self.durationSeconds = durationSeconds
    self.bytes = [UInt8](repeating: 0, count: (bits + 7) / 8)
  }

  init(data: Data, durationSeconds: Int) {
    let bits = Self.bitCount(forDurationSeconds: durationSeconds)
    let expectedByteCount = (bits + 7) / 8
    self.durationSeconds = durationSeconds
    var stored = [UInt8](data)
    if stored.count < expectedByteCount {
      stored.append(contentsOf: [UInt8](repeating: 0, count: expectedByteCount - stored.count))
    } else if stored.count > expectedByteCount {
      stored.removeLast(stored.count - expectedByteCount)
    }
    self.bytes = stored
  }

  init(data: Data, duration: CMTime) {
    self.init(data: data, durationSeconds: Self.seconds(duration))
  }

  // MARK: - Mutation

  mutating func mark(startSeconds: Int, endSeconds: Int) {
    guard endSeconds > startSeconds else { return }
    let bits = Self.bitCount(forDurationSeconds: durationSeconds)
    guard bits > 0 else { return }

    let firstBit = max(0, startSeconds / Self.bitWidthSeconds)
    // End is exclusive; (endSeconds - 1) keeps a range that ends on a chunk
    // boundary from spilling into the next chunk.
    let lastBit = min(bits - 1, (endSeconds - 1) / Self.bitWidthSeconds)
    guard firstBit <= lastBit else { return }

    for bit in firstBit...lastBit {
      bytes[bit / 8] |= UInt8(1 << (bit % 8))
    }
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

  private static func seconds(_ time: CMTime) -> Int {
    guard time.isValid, !time.isIndefinite else { return 0 }
    let s = time.seconds
    guard s.isFinite, s > 0 else { return 0 }
    return Int(s.rounded(.down))
  }
}

// MARK: - CMTime convenience

extension PlaybackCoverage {
  init(duration: CMTime) {
    self.init(durationSeconds: Self.seconds(duration))
  }

  mutating func mark(from start: CMTime, to end: CMTime) {
    mark(
      startSeconds: Self.seconds(start),
      endSeconds: Self.seconds(end)
    )
  }
}
