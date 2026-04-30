// Copyright Justin Bishop, 2026

import AVFoundation
import Foundation
import Testing

@testable import PodHaven

@Suite("PlaybackCoverage tests")
struct PlaybackCoverageTests {
  // MARK: - Init / sizing

  @Test("empty bitmap has zero coverage")
  func emptyBitmapZeroCoverage() {
    let coverage = PlaybackCoverage(durationSeconds: 60)
    #expect(coverage.coveredSeconds == 0)
    #expect(coverage.ratio == 0.0)
  }

  @Test("byte count is ceil(durationSeconds / bitWidth / 8)")
  func byteCountSizing() {
    // 60s / 3s = 20 bits → 3 bytes
    let oneMin = PlaybackCoverage(durationSeconds: 60)
    #expect(oneMin.bytes.count == 3)

    // 1s / 3s = ceil(1/3) = 1 bit → 1 byte
    let tiny = PlaybackCoverage(durationSeconds: 1)
    #expect(tiny.bytes.count == 1)

    // 24s / 3s = 8 bits → 1 byte
    let exact = PlaybackCoverage(durationSeconds: 24)
    #expect(exact.bytes.count == 1)

    // 25s / 3s = ceil(25/3) = 9 bits → 2 bytes
    let overflow = PlaybackCoverage(durationSeconds: 25)
    #expect(overflow.bytes.count == 2)
  }

  @Test("zero duration yields zero-byte bitmap and 0 ratio")
  func zeroDuration() {
    let coverage = PlaybackCoverage(durationSeconds: 0)
    #expect(coverage.bytes.isEmpty)
    #expect(coverage.ratio == 0.0)
  }

  // MARK: - Mark

  @Test("mark a single chunk sets exactly one bit")
  func markSingleChunk() {
    var coverage = PlaybackCoverage(durationSeconds: 60)
    coverage.mark(startSeconds: 0, endSeconds: 3)
    #expect(coverage.coveredSeconds == 3)
  }

  @Test("re-marking the same range is a no-op")
  func reMarkNoDoubleCount() {
    var coverage = PlaybackCoverage(durationSeconds: 60)
    coverage.mark(startSeconds: 0, endSeconds: 30)
    let firstPass = coverage.coveredSeconds
    coverage.mark(startSeconds: 0, endSeconds: 30)
    #expect(coverage.coveredSeconds == firstPass)
    #expect(coverage.coveredSeconds == 30)
  }

  @Test("disjoint marks accumulate")
  func disjointMarks() {
    var coverage = PlaybackCoverage(durationSeconds: 60)
    coverage.mark(startSeconds: 0, endSeconds: 15)
    coverage.mark(startSeconds: 30, endSeconds: 45)
    #expect(coverage.coveredSeconds == 30)
  }

  @Test("range exactly on a chunk boundary doesn't bleed into next chunk")
  func rangeOnBoundary() {
    var coverage = PlaybackCoverage(durationSeconds: 60)
    // [0, 3) is exactly one chunk. Should mark bit 0 only, not bit 1.
    coverage.mark(startSeconds: 0, endSeconds: 3)
    #expect(coverage.coveredSeconds == 3)

    // Now [3, 6) should mark bit 1 only.
    coverage.mark(startSeconds: 3, endSeconds: 6)
    #expect(coverage.coveredSeconds == 6)
  }

  @Test("partial overlap with a chunk still marks the whole chunk")
  func partialChunkOverlap() {
    var coverage = PlaybackCoverage(durationSeconds: 60)
    // [1, 2) overlaps chunk [0, 3) → bit 0 set, coverage rounds up to 3s
    coverage.mark(startSeconds: 1, endSeconds: 2)
    #expect(coverage.coveredSeconds == 3)
  }

  @Test("empty range is a no-op")
  func emptyRange() {
    var coverage = PlaybackCoverage(durationSeconds: 60)
    coverage.mark(startSeconds: 10, endSeconds: 10)
    #expect(coverage.coveredSeconds == 0)
  }

  @Test("backward range is a no-op (no implicit swap)")
  func backwardRange() {
    var coverage = PlaybackCoverage(durationSeconds: 60)
    coverage.mark(startSeconds: 30, endSeconds: 10)
    #expect(coverage.coveredSeconds == 0)
  }

  @Test("range past duration is clamped to last chunk")
  func rangePastDuration() {
    var coverage = PlaybackCoverage(durationSeconds: 60)
    coverage.mark(startSeconds: 50, endSeconds: 200)
    // Last chunk is [57, 60). [50, 60) covers chunks [48, 51, 54, 57] = 4 × 3s.
    #expect(coverage.coveredSeconds == 12)
  }

  // MARK: - Round-trip

  @Test("round-trip via Data preserves bits")
  func roundTrip() {
    var original = PlaybackCoverage(durationSeconds: 60)
    original.mark(startSeconds: 0, endSeconds: 15)
    original.mark(startSeconds: 30, endSeconds: 45)

    let restored = PlaybackCoverage(durationSeconds: 60, data: original.data)
    #expect(restored.coveredSeconds == original.coveredSeconds)
    #expect(restored.bytes == original.bytes)
  }

  @Test("decode pads when stored data is shorter than expected")
  func decodePadsShortData() {
    let coverage = PlaybackCoverage(durationSeconds: 60, data: Data([0xFF]))
    // Expected 3 bytes for 60s, only 1 supplied. Remaining bytes should be 0.
    #expect(coverage.bytes.count == 3)
    #expect(coverage.bytes[0] == 0xFF)
    #expect(coverage.bytes[1] == 0)
    #expect(coverage.bytes[2] == 0)
  }

  @Test("decode truncates when stored data is longer than expected")
  func decodeTruncatesLongData() {
    let coverage = PlaybackCoverage(
      durationSeconds: 60,
      data: Data([0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
    )
    #expect(coverage.bytes.count == 3)
  }

  @Test("padding bits in the final byte do not count as coverage")
  func paddingBitsExcludedFromCoverage() {
    // durationSeconds 1 → 1 valid bit in a 1-byte buffer; bits 1..7 are padding.
    // 0xFE has bit 0 clear and the 7 padding bits set, so a popcount-everything
    // implementation would report 21s of coverage on a 1s episode.
    let coverage = PlaybackCoverage(durationSeconds: 1, data: Data([0xFE]))
    #expect(coverage.coveredSeconds == 0)
    #expect(coverage.ratio == 0.0)
  }

  // MARK: - Ratio

  @Test("ratio is coveredSeconds / durationSeconds, clamped to 1.0")
  func ratioClamped() {
    var coverage = PlaybackCoverage(durationSeconds: 60)
    coverage.mark(startSeconds: 0, endSeconds: 30)
    #expect(abs(coverage.ratio - 0.5) < 0.001)

    coverage.mark(startSeconds: 30, endSeconds: 60)
    #expect(abs(coverage.ratio - 1.0) < 0.001)
  }

  // MARK: - CMTime convenience

  @Test("CMTime mark agrees with seconds-based mark on aligned boundaries")
  func cmTimeMark() {
    var coverage = PlaybackCoverage(duration: CMTime.seconds(60))
    coverage.mark(from: CMTime.seconds(9), to: CMTime.seconds(39))
    #expect(coverage.coveredSeconds == 30)
  }

  @Test("CMTime mark on a mid-chunk start rounds up to the chunk boundary")
  func cmTimeMarkMidChunk() {
    var coverage = PlaybackCoverage(duration: CMTime.seconds(60))
    coverage.mark(from: CMTime.seconds(10), to: CMTime.seconds(40))
    // [10, 40) overlaps chunks [9,12)..[39,42); 11 chunks × 3s = 33s.
    #expect(coverage.coveredSeconds == 33)
  }
}
